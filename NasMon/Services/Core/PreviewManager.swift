//  PreviewManager.swift
//  NasMon
//
//  Created by Brian Li on 8/3/26.
//
//  Orchestrates the "get me a local previewable file" flow for the
//  download-then-display preview surfaces (image / pdf / quickLook).
//  Video and audio are handled by their own dedicated players and do not
//  go through this cache pipeline.
//
//  Streams bytes into the resumable `PreviewCache` and reports progress so
//  surfaces can render progressively (see ADR-0003). Classification lives in
//  `PreviewRouter`; this manager owns only the cache + streaming orchestration.
//

import Foundation

/// Orchestrates obtaining a local copy of a file for preview.
///
/// Owns: cache lookup → streaming download → return local URL.
/// Never touches UI state and never decides *which* preview surface to use
/// (that is `PreviewRouter`'s job).
struct PreviewManager {

    /// Prepare a local previewable copy of the file, streaming into the cache.
    ///
    /// Flow:
    /// 1. Reject unsupported file types (via `PreviewRouter`).
    /// 2. If a complete cached copy exists, return it immediately.
    /// 3. Otherwise stream the file into `PreviewCache/`, reporting progress
    ///    as bytes arrive. Byte-offset resume is used when the active
    ///    transport supports Range; otherwise a failed/interrupted download
    ///    restarts from byte 0 (confirmed resume contract, ADR-0002/0003).
    ///
    /// - Parameters:
    ///   - file: The NAS file to preview.
    ///   - client: The active DSM client.
    ///   - category: The preview surface category (drives cache caps).
    ///   - onProgress: Called with (receivedBytes, expectedSize) as data
    ///     arrives; called on a background queue.
    /// - Returns: Local URL of the previewable file.
    static func preparePreview(
        file: DSMFile,
        client: DSMClient,
        category: PreviewCategory? = nil,
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }
    ) async throws -> URL {
        let category = category ?? PreviewRouter.category(for: file)
        guard category != .unsupported else {
            throw PreviewError.notPreviewable
        }

        let scope = client.cacheScope
        let destination = PreviewCache.url(for: file, server: scope)

        // Complete cache hit → open immediately.
        if PreviewCache.isComplete(for: file, server: scope) {
            onProgress(PreviewCache.meta(for: file, server: scope)?.downloadedBytes ?? 0, nil)
            return destination
        }

        // Confirmed retry contract (Q8): automatic retry up to 2 times with
        // exponential backoff (1s, 2s). Range-capable channels resume from the
        // sidecar offset on each attempt; the raw-stream channel restarts.
        let maxAttempts = 3
        var lastError: Error = PreviewError.notPreviewable
        for attempt in 1...maxAttempts {
            if Task.isCancelled { throw CancellationError() }
            do {
                return try await streamOnce(
                    file: file, client: client, category: category,
                    onProgress: onProgress
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                // The failed attempt used the WebDAV channel and WebDAV can't
                // serve this file (request can't be built, or the WebDAV server
                // answered non-2xx). Drop WebDAV for the rest of the session so
                // the next attempt picks File Station instead of re-selecting
                // WebDAV and failing again (see StreamingProbe.disableWebDAV).
                if client.streamingProbe.webDAVPort != nil,
                   Self.shouldFallBackFromWebDAV(error) {
                    client.streamingProbe.disableWebDAV()
                }
                guard attempt < maxAttempts else { break }
                let backoffSeconds = Duration.seconds(1 << (attempt - 1)) // 1, 2
                try? await Task.sleep(for: backoffSeconds)
            }
        }
        throw lastError
    }

    /// Whether a streaming error means the WebDAV channel itself cannot serve
    /// the file (request can't be built, or the WebDAV server answered non-2xx).
    /// Transient network/disk errors are excluded so a temporary outage doesn't
    /// permanently disable WebDAV for the whole session.
    private static func shouldFallBackFromWebDAV(_ error: Error) -> Bool {
        guard let error = error as? DSMClientError else { return false }
        switch error {
        case .invalidURL, .fileStationFailed:
            return true
        default:
            return false
        }
    }

    /// Single streaming attempt (see `preparePreview` for the retry wrapper).
    private static func streamOnce(
        file: DSMFile,
        client: DSMClient,
        category: PreviewCategory,
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> URL {
        let scope = client.cacheScope
        let destination = PreviewCache.url(for: file, server: scope)
        let expectedSize = file.additional?.size
        let channel = await client.streamingChannel(for: file)

        // Decide the resume offset. Byte-offset resume requires a Range-capable
        // channel; otherwise a partial file from a previous run is discarded.
        var resumeOffset: Int64 = 0
        if channel != .fileStationStream {
            if let meta = PreviewCache.meta(for: file, server: scope), !meta.isComplete {
                resumeOffset = meta.downloadedBytes
            }
        }
        if resumeOffset > 0 {
            // Truncate the partial file to exactly the resumed offset so
            // appending continues cleanly.
            if let handle = try? FileHandle(forUpdating: destination) {
                try? handle.truncate(atOffset: UInt64(resumeOffset))
                try? handle.close()
            }
        } else if PreviewCache.exists(for: file, server: scope) {
            try? FileManager.default.removeItem(at: destination)
        }

        // Oversized files stream without being persisted (per-file cap).
        let persist = PreviewCache.shouldCache(expectedSize: expectedSize, category: category)

        // Protect the in-progress entry from LRU eviction while streaming.
        PreviewCache.enforceQuota(protecting: destination)

        let request = try client.makeStreamingRequest(
            path: file.path,
            channel: channel,
            range: resumeOffset > 0 ? "bytes=\(resumeOffset)-" : nil
        )

        if persist {
            try await streamToCache(
                request: request,
                destination: destination,
                file: file,
                expectedSize: expectedSize,
                resumeOffset: resumeOffset,
                server: scope,
                onProgress: onProgress
            )
        } else {
            // Stream to a temp file (not persisted) — large-file path.
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(file.fileExtension)
            try await streamToCache(
                request: request,
                destination: temp,
                file: nil,
                expectedSize: expectedSize,
                resumeOffset: resumeOffset,
                server: scope,
                onProgress: onProgress
            )
            // The temp file replaces the cache entry only when it fits the cap
            // (size may have been unknown up front). The move consumes `temp`.
            if let expectedSize, expectedSize <= PreviewCache.fileCap(forCategory: category) {
                _ = try PreviewCache.save(from: temp, for: file, server: scope)
                return destination
            }
            return temp
        }

        return destination
    }

    // MARK: - Private

    /// Run a `StreamingDownloader`, updating the cache sidecar as bytes land.
    private static func streamToCache(
        request: URLRequest,
        destination: URL,
        file: DSMFile?,
        expectedSize: Int64?,
        resumeOffset: Int64,
        server: String?,
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws {
        let downloader = StreamingDownloader(
            request: request,
            destination: destination,
            writeOffset: resumeOffset,
            expectedSize: expectedSize
        ) { received, total in
            if let file {
                PreviewCache.updateProgress(
                    for: file, downloadedBytes: received, expectedSize: total ?? expectedSize,
                    server: server
                )
            }
            onProgress(received, total ?? expectedSize)
        }

        _ = try await downloader.start()

        // Success: mark the cache entry complete.
        if let file {
            let meta = PreviewCache.meta(for: file, server: server)
            PreviewCache.markComplete(for: file, expectedSize: meta?.expectedSize ?? expectedSize, server: server)
        }
        onProgress(expectedSize ?? 0, expectedSize)
    }
}

/// Errors thrown by the preview system.
enum PreviewError: Error {
    /// The file type cannot be previewed with any preview surface.
    case notPreviewable
}
