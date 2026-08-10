//
//  DSMClient.swift
//  NasMon
//
//  Core Synology DSM API client - provides connection management and URL building.
//  Functionality is organized into separate service extensions for easy extension
//  to other NAS brands:
//    - DSMAuthService:      Synology DSM authentication
//    - DSMSystemService:   Synology DSM system monitoring
//    - DSMFileStationService: Synology DSM file operations
//  For other NAS brands, create new client classes (e.g., QNAPClient, DS365Client)
//  with their own service extensions.
//  Trusts self-signed certs — only use against your own NAS on a trusted network/Tailscale.
//

import Foundation

// MARK: - Client
/// Core Synology DSM client that provides connection management and URL building for
/// DSM API endpoints. Functionality is organized into separate service extensions:
///   - DSMAuthService:      login, logout, session management
///   - DSMSystemService:   system info, utilization, power commands
///   - DSMFileStationService: file station operations
/// 
/// To support other NAS brands, create a new client class (e.g., QNAPClient)
/// with its own service extensions.
final class DSMClient: NSObject {

    let host: String       // e.g. "100.x.x.x" (Tailscale IP) or "in155n.synology.me"
    let port: Int          // usually 5001 for HTTPS
    var sid: String?
    /// Token-based auth token returned when login is called with
    /// `enable_syno_token=yes`. Required (as `SynoToken` query param or
    /// `X-SYNO-TOKEN` header) for File Station APIs.
    var synotoken: String?

    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        // Fail fast when the NAS is unreachable so the user gets feedback quickly
        // instead of waiting for the system default (~60s) timeout.
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// Dedicated streaming session.
    ///
    /// The regular `session` fails fast (10s request / 15s resource timeout)
    /// which is wrong for long-lived streaming connections. This session uses
    /// generous timeouts and the same self-signed-cert trust delegate.
    lazy var streamingSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3600
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// Cached streaming capabilities for this session.
    var streamingProbe = StreamingProbe()

    /// DSM account name (set at login; used for WebDAV Basic auth).
    var account: String?

    /// Stable identifier scoping the preview cache to this server and account.
    ///
    /// Cache keys are derived from the file path alone, so two servers (or two
    /// accounts on one NAS) exposing the same path would otherwise share one
    /// cache entry and show the wrong file. Including the scope keeps each
    /// server/account's cache separate. The account matters for `/home/...`
    /// paths, which resolve to different files per user.
    var cacheScope: String? {
        if let account {
            return "\(host):\(port)/\(account)"
        }
        return "\(host):\(port)"
    }

    init(host: String, port: Int = 5001) {
        self.host = host
        self.port = port
    }

    func makeURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port
        components.path = path
        components.queryItems = queryItems
        return components.url
    }

    /// Authentication query items for an authenticated DSM API call.
    ///
    /// DSM 7 returns error 119 ("session expired") for calls that pass only
    /// `_sid` when the session was created with `enable_syno_token=yes`; the
    /// `SynoToken` (a CSRF token returned by login) must also be included.
    /// Sending both keeps calls working regardless of server enforcement.
    var authQueryItems: [URLQueryItem] {
        guard let sid else { return [] }
        var items = [URLQueryItem(name: "_sid", value: sid)]
        if let synotoken {
            items.append(URLQueryItem(name: "SynoToken", value: synotoken))
        }
        return items
    }
}

// MARK: - Self-signed cert trust
/// Handles self-signed certificate validation for HTTPS connections to the NAS.
extension DSMClient: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // WARNING: trusts ANY cert for this host. Fine for local dev against your own NAS.
        // Tighten this later (pin your actual cert) before doing anything more permanent.
        guard challenge.protectionSpace.host == self.host,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
