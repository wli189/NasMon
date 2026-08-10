//  PreviewCache.swift
//  NasMon
//
//  Created by Brian Li on 8/3/26.
//
//  Manages the Caches/PreviewCache/ directory where downloaded preview
//  files are stored. Files here are invisible to the user's Files app.
//
//  Supports resumable cache entries (see ADR-0003): each cached file may have
//  a `.streammeta` sidecar recording expected size, downloaded byte count,
//  and completion flag. Entries without a sidecar are legacy complete files.
//
//  Quota policy (confirmed): 1 GB total with LRU eviction, per-file caps
//  (200 MB non-media / 2 GB media). In-progress entries are protected from
//  eviction. Media playback buffers live in a separate `MediaStreamCache/`
//  directory and never count against the preview quota.
//

import Foundation

/// Manages the on-disk cache for downloaded preview files.
///
/// All preview files live in `Caches/PreviewCache/`. The cache URL for a
/// given NAS file is derived from a stable hash of its path plus its original
/// extension, so the same file always maps to the same local URL (enabling
/// cache hits) without collisions.
struct PreviewCache {

    // MARK: - Quota (confirmed in design session)

    /// Total preview cache budget: 1 GB.
    static let totalQuota: Int64 = 1 << 30
    /// Per-file cap for non-media previews: 200 MB.
    static let nonMediaFileCap: Int64 = 200 << 20
    /// Per-file cap for media: 2 GB.
    static let mediaFileCap: Int64 = 2 << 30

    // MARK: - Paths

    /// The `Caches/PreviewCache/` directory, created on first access.
    static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("PreviewCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The `Caches/MediaStreamCache/` directory for media playback buffers.
    /// Never counted against the preview quota; cleaned up on player close.
    static var mediaStreamDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("MediaStreamCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Compute the stable local cache URL for a NAS file.
    ///
    /// Uses a hash of the file's full path (so different folders with the
    /// same filename don't collide) plus the server scope (so different
    /// servers/accounts with the same path don't collide), and preserves the
    /// original extension so QuickLook can identify the file type. `server`
    /// is `DSMClient.cacheScope` (`host:port/account`) in production; a `nil`
    /// scope falls back to the legacy path-only key.
    static func url(for file: DSMFile, server: String?) -> URL {
        let key = server.map { "\($0)/\(file.path)" } ?? file.path
        let hash = stableHash(key)
        return directory
            .appendingPathComponent(hash)
            .appendingPathExtension(file.fileExtension)
    }

    /// URL of the `.streammeta` sidecar for a file.
    static func metaURL(for file: DSMFile, server: String?) -> URL {
        sidecarURL(forFileURL: url(for: file, server: server))
    }

    /// URL of the `.streammeta` sidecar for a cache file URL.
    static func sidecarURL(forFileURL url: URL) -> URL {
        url.appendingPathExtension("streammeta")
    }

    /// Whether a cached copy of the file exists on disk (complete or partial).
    static func exists(for file: DSMFile, server: String?) -> Bool {
        FileManager.default.fileExists(atPath: url(for: file, server: server).path)
    }

    /// Whether the cached copy is a complete, usable file.
    ///
    /// Legacy entries (no sidecar) are always complete. Entries with a
    /// sidecar are complete only when marked so (or when the downloaded byte
    /// count reached the expected size).
    static func isComplete(for file: DSMFile, server: String?) -> Bool {
        let fileURL = url(for: file, server: server)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        guard let meta = meta(for: file, server: server) else { return true }
        if meta.isComplete { return true }
        if let expected = meta.expectedSize, expected > 0 {
            return meta.downloadedBytes >= expected
        }
        return false
    }

    /// The sidecar metadata for a file, if any.
    static func meta(for file: DSMFile, server: String?) -> StreamCacheMeta? {
        guard let data = try? Data(contentsOf: metaURL(for: file, server: server)) else { return nil }
        return try? JSONDecoder().decode(StreamCacheMeta.self, from: data)
    }

    /// Update the sidecar for a file as its download progresses.
    static func updateProgress(for file: DSMFile, downloadedBytes: Int64, expectedSize: Int64?, server: String?) {
        var meta = meta(for: file, server: server) ?? StreamCacheMeta(
            expectedSize: expectedSize, downloadedBytes: downloadedBytes, isComplete: false
        )
        meta.downloadedBytes = downloadedBytes
        meta.expectedSize = expectedSize
        meta.updatedAt = Date()
        write(meta, for: file, server: server)
    }

    /// Mark a file's cache entry as complete.
    static func markComplete(for file: DSMFile, expectedSize: Int64? = nil, server: String?) {
        var meta = meta(for: file, server: server) ?? StreamCacheMeta(
            expectedSize: expectedSize, downloadedBytes: 0, isComplete: true
        )
        meta.isComplete = true
        if let expectedSize, expectedSize > 0 {
            meta.expectedSize = expectedSize
            meta.downloadedBytes = expectedSize
        }
        meta.updatedAt = Date()
        write(meta, for: file, server: server)
        enforceQuota()
    }

    /// Remove a partial entry (file + sidecar). Used on user-cancelled previews.
    static func removePartial(for file: DSMFile, server: String?) {
        let fileURL = url(for: file, server: server)
        if let meta = meta(for: file, server: server), !meta.isComplete {
            try? FileManager.default.removeItem(at: fileURL)
        }
        try? FileManager.default.removeItem(at: metaURL(for: file, server: server))
    }

    /// Remove every cached preview file and its sidecar.
    ///
    /// Used by the in-app Settings "Clear Cache" action. Only touches the
    /// `PreviewCache/` directory — the separate `MediaStreamCache/` buffer and
    /// saved servers / credentials are left untouched.
    static func clearAll() {
        let fm = FileManager.default
        let dir = directory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files {
            try? fm.removeItem(at: url)
        }
    }

    /// Move a freshly downloaded complete file into the cache.
    ///
    /// - Parameters:
    ///   - sourceURL: The temporary location the download wrote to.
    ///   - file: The NAS file being cached.
    /// - Returns: The final cache URL.
    static func save(from sourceURL: URL, for file: DSMFile, server: String?) throws -> URL {
        let destination = url(for: file, server: server)
        // Remove any stale copy before moving the new one in.
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: sourceURL, to: destination)
        markComplete(for: file, server: server)
        return destination
    }

    // MARK: - Quota / LRU

    /// Per-file cache cap for a preview category (media vs non-media).
    static func fileCap(forCategory category: PreviewCategory?) -> Int64 {
        switch category {
        case .video, .audio: return mediaFileCap
        default: return nonMediaFileCap
        }
    }

    /// Whether a file of the given size should be written to the preview
    /// cache at all. Larger files stream without being persisted.
    static func shouldCache(expectedSize: Int64?, category: PreviewCategory?) -> Bool {
        guard let expectedSize else { return true }
        return expectedSize <= fileCap(forCategory: category)
    }

    /// Evict LRU entries until the directory is under `totalQuota`.
    ///
    /// - Parameter protectedURL: A file that must not be evicted (e.g. the
    ///   entry currently being streamed).
    static func enforceQuota(protecting protectedURL: URL? = nil) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        // Sum sizes of cache files (skip sidecars), and collect eviction
        // candidates with their last-used date.
        var total: Int64 = 0
        var candidates: [(url: URL, date: Date)] = []
        for url in files {
            guard url.pathExtension != "streammeta" else { continue }
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { continue }
            total += Int64(size)
            let meta = StreamCacheMeta.fromSidecar(at: sidecarURL(forFileURL: url))
            let date = meta?.updatedAt
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            candidates.append((url, date))
        }

        guard total > totalQuota else { return }

        // Evict oldest first, skipping the protected file.
        candidates.sort { $0.date < $1.date }
        for candidate in candidates {
            guard total > totalQuota else { break }
            guard candidate.url != protectedURL else { continue }
            let size = (try? candidate.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            try? fm.removeItem(at: candidate.url)
            try? fm.removeItem(at: sidecarURL(forFileURL: candidate.url))
            total -= Int64(size)
        }
    }

    /// Total bytes currently stored in the preview cache (files only).
    static var currentBytes: Int64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { sum, url in
            guard url.pathExtension != "streammeta" else { return sum }
            return sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    // MARK: - Helpers

    /// Write sidecar metadata for a file.
    private static func write(_ meta: StreamCacheMeta, for file: DSMFile, server: String?) {
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL(for: file, server: server), options: .atomic)
        }
    }

    /// A stable, collision-resistant hash of a string (FNV-1a 64-bit).
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - Sidecar Metadata

/// Metadata recorded alongside a resumable cache entry.
struct StreamCacheMeta: Codable {
    var expectedSize: Int64?
    var downloadedBytes: Int64
    var isComplete: Bool
    var updatedAt: Date = Date()

    /// Read a sidecar for a cache file URL (`<file>.streammeta`).
    static func fromSidecar(at url: URL) -> StreamCacheMeta? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StreamCacheMeta.self, from: data)
    }
}
