//
//  StreamingTransport.swift
//  NasMon
//
//  Created by Brian Li on 8/5/26.
//
//  Streaming transport layer: runtime-probed capabilities decide how a
//  file's bytes are fetched for streaming (see ADR-0002).
//
//  Channel priority (best first):
//    1. WebDAV Server      — native HTTP Range (needs WebDAV package + saved password)
//    2. File Station Range — the Download API honors Range on this DSM
//    3. File Station stream— raw append-only stream, no byte-offset seeking
//
//  Capabilities are probed lazily and cached for the lifetime of the DSM
//  session so we don't probe on every file open.
//

import Foundation

// MARK: - Streaming Channel

/// How a file's bytes are fetched for streaming.
enum StreamingChannel: Equatable {
    /// WebDAV Server — native HTTP Range support.
    case webDAV
    /// File Station honors Range requests on this DSM.
    case fileStationRange
    /// File Station raw stream — append-only, no byte-offset seeking.
    case fileStationStream
}

// MARK: - Streaming Probe

/// Runtime-discovered streaming capabilities, cached per DSM session.
///
/// `fileStationRangeProbe` and `webDAVPort` are server-wide facts, so each is
/// probed at most once per session and reused for every file.
final class StreamingProbe {

    /// Whether File Station's Download API honored a `Range` request.
    /// `nil` = not probed yet.
    private(set) var fileStationRangeProbe: Bool?

    /// WebDAV HTTPS port when the WebDAV channel is reachable with saved
    /// credentials. `nil` = not available (or not probed yet).
    private(set) var webDAVPort: Int?

    /// DSM account used for WebDAV Basic auth (saved password comes from
    /// Keychain via `SessionStorage`).
    private(set) var webDAVAccount: String?

    /// URL scheme the reachable WebDAV server uses ("https" or "http").
    private(set) var webDAVScheme: String?

    /// Whether WebDAV has been permanently disabled for this session. Set
    /// when WebDAV was selected but failed to serve a real file, so
    /// `streamingChannel(for:)` never re-selects it (otherwise the preview
    /// retry loop would probe → select WebDAV → fail → loop forever).
    private(set) var webDAVDisabled = false

    func recordFileStationRange(_ supports: Bool) {
        fileStationRangeProbe = supports
    }

    func recordWebDAV(port: Int, scheme: String, account: String) {
        webDAVPort = port
        webDAVAccount = account
        webDAVScheme = scheme
    }

    /// Permanently drop the WebDAV channel for this session after a real
    /// streaming failure. Subsequent channel selection falls back to File
    /// Station for every file.
    func disableWebDAV() {
        webDAVDisabled = true
        webDAVPort = nil
        webDAVAccount = nil
        webDAVScheme = nil
    }

    func reset() {
        fileStationRangeProbe = nil
        webDAVDisabled = false
        webDAVPort = nil
        webDAVAccount = nil
        webDAVScheme = nil
    }
}

// MARK: - WebDAV Transport

/// Builds WebDAV requests against the Synology WebDAV Server package.
///
/// WebDAV serves the same shared-folder layout as File Station, so a File
/// Station path like `/home/music/song.mp3` maps directly to the WebDAV URL
/// `https://<host>:<port>/home/music/song.mp3` with HTTP Basic auth.
enum WebDAVTransport {

    /// Default HTTPS port for Synology's WebDAV Server package.
    static let defaultHTTPSPort = 5006
    /// Default HTTP port for Synology's WebDAV Server package.
    static let defaultHTTPPort = 5005

    /// Candidate (port, scheme) pairs to try, in order.
    static let candidates: [(port: Int, scheme: String)] = [
        (defaultHTTPSPort, "https"),
        (defaultHTTPPort, "http"),
    ]

    /// Build the WebDAV URL for a File Station path on the given host/port.
    static func url(host: String, port: Int, scheme: String, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = path
        return components.url
    }

    /// `Authorization` header value for HTTP Basic auth.
    static func basicAuthHeader(account: String, password: String) -> String {
        let credentials = "\(account):\(password)"
        let encoded = credentials.data(using: .utf8)?.base64EncodedString() ?? ""
        return "Basic \(encoded)"
    }
}

// MARK: - DSMClient Streaming Extension

extension DSMClient {

    /// File Station Download API URL for a path (`SYNO.FileStation.Download`).
    func fileStationDownloadURL(path: String) -> URL? {
        let auth = authQueryItems
        guard !auth.isEmpty else { return nil }
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.Download"),
            URLQueryItem(name: "version", value: "2"),
            URLQueryItem(name: "method", value: "download"),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "mode", value: "download"),
        ] + auth
        return makeURL(path: "/webapi/entry.cgi", queryItems: queryItems)
    }

    /// Resolve the account used for WebDAV auth: prefer the client's login
    /// account, then the saved server entry, then nil.
    private func resolvedAccount() -> String? {
        if let account { return account }
        let server = ServerStore.shared.loadServers()
            .first { $0.host == host && $0.port == port }
        return server?.lastLoginAccount
    }

    /// Build a streaming `URLRequest` for a file over the given channel.
    ///
    /// Shared by the preview pipeline (`PreviewManager`) and the media
    /// resource-loader data source (`StreamingMediaDataSource`).
    ///
    /// - Parameters:
    ///   - path: File Station path of the file.
    ///   - channel: Active streaming channel (see `streamingChannel(for:)`).
    ///   - range: Raw `Range` header value, e.g. `"bytes=0-1023"` or
    ///     `"bytes=1024-"`. `nil` requests the whole file.
    func makeStreamingRequest(
        path: String,
        channel: StreamingChannel,
        range: String? = nil
    ) throws -> URLRequest {
        switch channel {
        case .webDAV:
            guard let port = streamingProbe.webDAVPort,
                  let account = streamingProbe.webDAVAccount,
                  // The saved password lives under the DSM port key
                  // (SessionService.login), not the WebDAV port — using the
                  // WebDAV port here breaks every preview/playback attempt.
                  let password = SessionStorage().loadSavedPassword(host: host, port: self.port),
                  let url = WebDAVTransport.url(
                      host: host,
                      port: port,
                      scheme: streamingProbe.webDAVScheme ?? "https",
                      path: path
                  ) else {
                throw DSMClientError.invalidURL
            }
            var request = URLRequest(url: url)
            request.setValue(
                WebDAVTransport.basicAuthHeader(account: account, password: password),
                forHTTPHeaderField: "Authorization"
            )
            if let range {
                request.setValue(range, forHTTPHeaderField: "Range")
            }
            return request

        case .fileStationRange, .fileStationStream:
            guard let url = fileStationDownloadURL(path: path) else {
                throw DSMClientError.invalidURL
            }
            var request = URLRequest(url: url)
            if let range {
                request.setValue(range, forHTTPHeaderField: "Range")
            }
            return request
        }
    }

    /// Choose the best streaming channel for a file, probing capabilities as
    /// needed. Results are cached in `streamingProbe` for the session.
    func streamingChannel(for file: DSMFile) async -> StreamingChannel {
        // WebDAV first (native Range).
        if streamingProbe.webDAVPort != nil {
            return .webDAV
        }
        if streamingProbe.webDAVPort == nil && !streamingProbe.webDAVDisabled {
            if await probeWebDAV(for: file) {
                return .webDAV
            }
        }

        // File Station Range support (probe once per session).
        if let supports = streamingProbe.fileStationRangeProbe {
            return supports ? .fileStationRange : .fileStationStream
        }
        let supports = await probeFileStationRange(for: file)
        streamingProbe.recordFileStationRange(supports)
        return supports ? .fileStationRange : .fileStationStream
    }

    /// Probe whether File Station's Download API honors `Range` requests.
    private func probeFileStationRange(for file: DSMFile) async -> Bool {
        guard let url = fileStationDownloadURL(path: file.path) else { return false }
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        do {
            let (bytes, response) = try await streamingSession.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 206
                && http.value(forHTTPHeaderField: "Content-Range") != nil
        } catch {
            return false
        }
    }

    /// Probe whether WebDAV is reachable with the saved DSM password.
    /// Caches success (`webDAVPort`) so the probe runs once per session.
    private func probeWebDAV(for file: DSMFile) async -> Bool {
        guard let account = resolvedAccount() else { return false }
        let storage = SessionStorage()
        guard let password = storage.loadSavedPassword(host: host, port: port) else {
            return false
        }
        let authHeader = WebDAVTransport.basicAuthHeader(account: account, password: password)

        for candidate in WebDAVTransport.candidates {
            guard let url = WebDAVTransport.url(
                host: host,
                port: candidate.port,
                scheme: candidate.scheme,
                path: file.path
            ) else { continue }

            var request = URLRequest(url: url)
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

            do {
                let (bytes, response) = try await streamingSession.bytes(for: request)
                defer { bytes.task.cancel() }
                guard let http = response as? HTTPURLResponse else { continue }
                // 200/206 = reachable + authenticated (200 means Range was
                // ignored, but the channel is still usable as a raw stream).
                if http.statusCode == 200 || http.statusCode == 206 {
                    streamingProbe.recordWebDAV(port: candidate.port, scheme: candidate.scheme, account: account)
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }

    /// Fetch a byte range (or the whole stream) for a file over a
    /// range-capable channel. Throws when the channel cannot seek
    /// (`.fileStationStream`) — callers must use a sequential download there.
    ///
    /// - Returns: The requested bytes and the file's total length when known.
    func fetchBytes(
        path: String,
        channel: StreamingChannel,
        range: ClosedRange<Int64>? = nil
    ) async throws -> (data: Data, totalLength: Int64?) {
        let url: URL?
        var headers: [String: String] = [:]

        switch channel {
        case .webDAV:
            guard let port = streamingProbe.webDAVPort,
                  let account = streamingProbe.webDAVAccount else {
                throw DSMClientError.invalidURL
            }
            let storage = SessionStorage()
            let scheme = streamingProbe.webDAVScheme ?? "https"
            // Same as `makeStreamingRequest`: the saved password lives under
            // the DSM port key; the WebDAV port is only for the request URL.
            guard let password = storage.loadSavedPassword(host: host, port: self.port),
                  let webDAVURL = WebDAVTransport.url(
                      host: host, port: port, scheme: scheme, path: path
                  ) else {
                throw DSMClientError.invalidURL
            }
            url = webDAVURL
            headers["Authorization"] = WebDAVTransport.basicAuthHeader(
                account: account, password: password
            )
        case .fileStationRange:
            url = fileStationDownloadURL(path: path)
        case .fileStationStream:
            throw DSMClientError.fileStationFailed(code: nil)
        }

        guard let url else { throw DSMClientError.invalidURL }

        var request = URLRequest(url: url)
        if let range {
            request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await streamingSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DSMClientError.fileStationFailed(code: nil)
        }

        // Total length: parse Content-Range ("bytes 0-99/12345") or Content-Length.
        let totalLength = parseTotalLength(from: http, dataCount: Int64(data.count))
        return (data, totalLength)
    }

    /// Extract the file's total length from a streaming response.
    private func parseTotalLength(from response: HTTPURLResponse, dataCount: Int64) -> Int64? {
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
        return dataCount
    }
}
