//
//  StreamingMediaDataSource.swift
//  NasMon
//
//  Created by Brian Li on 8/5/26.
//
//  AVAssetResourceLoader data source that feeds media bytes to AVPlayer over
//  a custom `nasstream://` URL, so video/audio starts playing before the whole
//  file is downloaded (see ADR-0002).
//
//  - Range-capable channels (WebDAV / File Station-with-Range) serve real
//    HTTP byte ranges: seeking is instant and only the requested bytes are
//    transferred.
//  - The raw File Station stream cannot seek. A "fake seek" restarts the
//    download from byte 0 and discards the prefix up to the requested offset
//    (confirmed contract, Q10), while the player shows a loading state.
//

import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Supplies media bytes to `AVPlayer` through `AVAssetResourceLoader`.
///
/// The data source is retained by `MediaPlayerViewModel` for as long as the
/// player lives. AVFoundation calls the resource-loader delegate on the queue
/// passed to `setDelegate(_:queue:)`; network chunks arrive on a URLSession
/// background queue and are handed to AVPlayer via `respond(with:)`.
final class StreamingMediaDataSource: NSObject, @unchecked Sendable {

    // MARK: - Configuration

    let file: DSMFile
    let client: DSMClient
    let channel: StreamingChannel

    /// Total file size once known (listing metadata, content-information
    /// probe, or HTTP response headers).
    private var knownTotalLength: Int64?

    /// In-flight loading requests keyed by their `ObjectIdentifier`.
    private var activeRequests: [ObjectIdentifier: ActiveRequest] = [:]
    private let lock = NSLock()

    /// Dedicated session for media streaming (generous timeouts, same
    /// self-signed-cert trust policy as the client).
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3600
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(file: DSMFile, client: DSMClient, channel: StreamingChannel) {
        self.file = file
        self.client = client
        self.channel = channel
        self.knownTotalLength = file.additional?.size
    }

    /// Build the custom-scheme URL that routes this file's media requests
    /// through the resource loader. The URL is only a token — the data
    /// source already knows the file path and client.
    static func streamingURL(for file: DSMFile) -> URL? {
        var components = URLComponents()
        components.scheme = "nasstream"
        components.host = "media"
        components.path = file.path
        return components.url
    }

    // MARK: - Content Type

    /// Curated UTI map for common media extensions, used before falling back
    /// to `UTType` so AVPlayer reliably recognizes custom-scheme assets.
    private static let curatedContentTypes: [String: String] = [
        "mp3": "public.mp3",
        "m4a": "com.apple.m4a-audio",
        "m4b": "com.apple.m4b-audio",
        "aac": "public.aac-audio",
        "wav": "com.microsoft.waveform-audio",
        "aif": "public.aiff-audio",
        "aiff": "public.aiff-audio",
        "flac": "org.xiph.flac",
        "alac": "com.apple.alac-audio",
        "caf": "com.apple.coreaudio-format",
        "mp4": "public.mpeg-4",
        "m4v": "com.apple.m4v-video",
        "mov": "com.apple.quicktime-movie",
        "mpg": "public.mpeg",
        "mpeg": "public.mpeg",
        "3gp": "public.3gp",
        "3gpp": "public.3gp",
        "amr": "org.3gpp.adaptive-multi-rate-audio",
    ]

    /// The UTI AVPlayer should use to identify the media format.
    private static func contentType(for file: DSMFile) -> String {
        let ext = file.fileExtension.lowercased()
        if let mapped = curatedContentTypes[ext] { return mapped }
        if let type = UTType(filenameExtension: ext) { return type.identifier }
        return "public.data"
    }
}

// MARK: - AVAssetResourceLoaderDelegate

extension StreamingMediaDataSource: AVAssetResourceLoaderDelegate {

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let contentRequest = loadingRequest.contentInformationRequest
        let dataRequest = loadingRequest.dataRequest

        switch (contentRequest, dataRequest) {
        case (nil, nil):
            loadingRequest.finishLoading(with: Self.requestError("Empty loading request."))
            return true
        case (let content?, nil):
            handleContentInformation(content, loadingRequest: loadingRequest)
            return true
        case (_, let data?):
            startDataRequest(data, loadingRequest: loadingRequest)
            return true
        }
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        cancel(loadingRequest)
    }
}

// MARK: - Content Information

extension StreamingMediaDataSource {

    /// Answer a content-information request. Synchronous when the total
    /// length is already known; otherwise probe HTTP headers (without
    /// downloading the body) and answer afterwards.
    private func handleContentInformation(
        _ contentRequest: AVAssetResourceLoadingContentInformationRequest,
        loadingRequest: AVAssetResourceLoadingRequest
    ) {
        if let total = currentTotalLength {
            fill(contentRequest, totalLength: total)
            loadingRequest.finishLoading()
            return
        }

        Task {
            do {
                let total = try await probeTotalLength()
                setTotalLength(total)
                guard !loadingRequest.isCancelled,
                      let content = loadingRequest.contentInformationRequest else { return }
                fill(content, totalLength: total)
                loadingRequest.finishLoading()
            } catch {
                guard !loadingRequest.isCancelled,
                      let content = loadingRequest.contentInformationRequest else { return }
                // Unknown size — declare a raw stream and let AVPlayer adapt.
                fill(content, totalLength: currentTotalLength ?? 0)
                loadingRequest.finishLoading()
            }
        }
    }

    /// Learn the file's total length from HTTP headers without downloading
    /// the body: start a streaming request, read the response, then cancel.
    private func probeTotalLength() async throws -> Int64 {
        let request = try client.makeStreamingRequest(path: file.path, channel: channel, range: nil)
        let (bytes, response) = try await client.streamingSession.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DSMClientError.fileStationFailed(code: nil)
        }
        if let total = Self.totalLength(from: http) {
            return total
        }
        throw DSMClientError.fileStationFailed(code: nil)
    }

    /// Populate a content-information request.
    private func fill(
        _ request: AVAssetResourceLoadingContentInformationRequest,
        totalLength: Int64
    ) {
        request.contentType = Self.contentType(for: file)
        request.contentLength = max(totalLength, 0)
        request.isByteRangeAccessSupported = channel != .fileStationStream
    }
}

// MARK: - Data Requests

extension StreamingMediaDataSource {

    /// Start streaming the bytes AVPlayer asked for.
    ///
    /// Range-capable channels issue an HTTP `Range` request. The raw stream
    /// channel issues a full-body request and discards the prefix up to
    /// `requestedOffset` (fake seek).
    private func startDataRequest(
        _ dataRequest: AVAssetResourceLoadingDataRequest,
        loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let offset = dataRequest.requestedOffset
        let length = dataRequest.requestedLength
        let requestsAll = dataRequest.requestsAllDataToEndOfResource

        // Nothing to deliver.
        if offset < 0 || (!requestsAll && length <= 0) {
            loadingRequest.finishLoading()
            return
        }

        // A request entirely past a known EOF needs no bytes.
        if let total = currentTotalLength, offset >= total {
            loadingRequest.finishLoading()
            return
        }

        // Content info riding along on the same request can be answered now
        // when the total length is known; otherwise it is filled in when the
        // HTTP response headers arrive.
        if let content = loadingRequest.contentInformationRequest, let total = currentTotalLength {
            fill(content, totalLength: total)
        }

        let rangeHeader: String?
        let toDiscard: Int64
        switch channel {
        case .webDAV, .fileStationRange:
            rangeHeader = requestsAll ? "bytes=\(offset)-" : "bytes=\(offset)-\(offset + Int64(length) - 1)"
            toDiscard = 0
        case .fileStationStream:
            rangeHeader = nil
            toDiscard = offset
        }

        let urlRequest: URLRequest
        do {
            urlRequest = try client.makeStreamingRequest(path: file.path, channel: channel, range: rangeHeader)
        } catch {
            loadingRequest.finishLoading(with: error as NSError)
            return
        }

        let active = ActiveRequest(
            loadingRequest: loadingRequest,
            requestedLength: requestsAll ? nil : Int64(length),
            toDiscard: toDiscard
        )
        register(active)
        let task = session.dataTask(with: urlRequest)
        active.task = task
        task.resume()
    }

    /// Finish a request successfully and stop its network task.
    private func finishSuccessfully(_ active: ActiveRequest) {
        guard !active.finished else { return }
        active.finished = true
        active.task?.cancel()
        active.loadingRequest.finishLoading()
        unregister(active)
    }

    /// Finish a request with an error and stop its network task.
    private func finish(_ active: ActiveRequest, withError error: Error) {
        guard !active.finished else { return }
        active.finished = true
        active.task?.cancel()
        active.loadingRequest.finishLoading(with: error as NSError)
        unregister(active)
    }

    /// AVPlayer cancelled a request — stop fetching and drop its state.
    /// (`finishLoading` must NOT be called on a cancelled request.)
    private func cancel(_ loadingRequest: AVAssetResourceLoadingRequest) {
        lock.lock()
        let active = activeRequests.removeValue(forKey: ObjectIdentifier(loadingRequest))
        lock.unlock()
        active?.finished = true
        active?.task?.cancel()
    }
}

// MARK: - Active Request Registry

extension StreamingMediaDataSource {

    /// State for one in-flight `AVAssetResourceLoadingRequest`.
    private final class ActiveRequest {
        let loadingRequest: AVAssetResourceLoadingRequest
        /// Bytes to deliver for this request; `nil` = to end of resource.
        let requestedLength: Int64?
        /// Bytes that must be discarded before responding (fake seek).
        var toDiscard: Int64
        /// Bytes already delivered to AVPlayer for this request.
        var delivered: Int64 = 0
        var task: URLSessionDataTask?
        var finished = false

        init(
            loadingRequest: AVAssetResourceLoadingRequest,
            requestedLength: Int64?,
            toDiscard: Int64
        ) {
            self.loadingRequest = loadingRequest
            self.requestedLength = requestedLength
            self.toDiscard = toDiscard
        }
    }

    private func register(_ active: ActiveRequest) {
        lock.lock()
        activeRequests[ObjectIdentifier(active.loadingRequest)] = active
        lock.unlock()
    }

    private func unregister(_ active: ActiveRequest) {
        lock.lock()
        activeRequests.removeValue(forKey: ObjectIdentifier(active.loadingRequest))
        lock.unlock()
    }

    private func activeRequest(for dataTask: URLSessionDataTask) -> ActiveRequest? {
        lock.lock()
        defer { lock.unlock() }
        return activeRequests.values.first { $0.task === dataTask }
    }

    private var currentTotalLength: Int64? {
        lock.lock()
        defer { lock.unlock() }
        return knownTotalLength
    }

    private func setTotalLength(_ value: Int64) {
        lock.lock()
        knownTotalLength = value
        lock.unlock()
    }

    /// Parse the file's total length from response headers.
    private static func totalLength(from response: HTTPURLResponse) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range") {
            // e.g. "bytes 0-1023/12345678" or "bytes */12345678"
            if let slash = contentRange.lastIndex(of: "/") {
                let total = contentRange[contentRange.index(after: slash)...]
                if total != "*", let value = Int64(total) {
                    return value
                }
            }
        }
        if response.statusCode == 200 {
            return response.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
        }
        return nil
    }

    /// A generic AVFoundation error for failed loading requests.
    private static func requestError(_ description: String) -> NSError {
        NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.unknown.rawValue,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

// MARK: - URLSessionDataDelegate

extension StreamingMediaDataSource: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let active = activeRequest(for: dataTask) else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(active, withError: Self.requestError("Invalid streaming response."))
            return
        }
        guard (200...299).contains(http.statusCode) else {
            completionHandler(.cancel)
            finish(active, withError: DSMClientError.fileStationFailed(code: http.statusCode))
            return
        }

        // Learn the total length from the response when not already known.
        if let total = Self.totalLength(from: http) {
            setTotalLength(total)
        }

        // Content info riding along on this request gets answered now that
        // the headers are available (fall back to the listing size / zero so
        // it is never left unanswered).
        if let content = active.loadingRequest.contentInformationRequest {
            let total = currentTotalLength ?? file.additional?.size ?? 0
            fill(content, totalLength: total)
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let active = activeRequest(for: dataTask), !active.finished else { return }
        var chunk = data

        // Fake seek: discard the prefix up to the requested offset.
        if active.toDiscard > 0 {
            if Int64(chunk.count) <= active.toDiscard {
                active.toDiscard -= Int64(chunk.count)
                return
            }
            chunk = chunk.dropFirst(Int(active.toDiscard))
            active.toDiscard = 0
        }

        // Cap the response at the requested length.
        if let requestedLength = active.requestedLength {
            let remaining = requestedLength - active.delivered
            if remaining <= 0 {
                finishSuccessfully(active)
                return
            }
            if Int64(chunk.count) > remaining {
                chunk = chunk.prefix(Int(remaining))
            }
        }

        guard !chunk.isEmpty else { return }
        active.delivered += Int64(chunk.count)
        active.loadingRequest.dataRequest?.respond(with: chunk)

        // Request satisfied → stop the network task and finish.
        if let requestedLength = active.requestedLength, active.delivered >= requestedLength {
            finishSuccessfully(active)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let dataTask = task as? URLSessionDataTask,
              let active = activeRequest(for: dataTask),
              !active.finished else { return }
        if let error {
            finish(active, withError: error)
        } else {
            finishSuccessfully(active)
        }
    }

    // Same self-signed-cert trust policy as DSMClient.
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
