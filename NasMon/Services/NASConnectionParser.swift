//
//  NASConnectionParser.swift
//  NasMon
//
//  Created by Brian Li on 8/2/26.
//

import Foundation

/// Universal network address parser for NAS devices (Synology, QNAP, TrueNAS, etc.).
/// Supports formats like "192.168.1.1:5000" or "my-nas.local" (default port).
/// Note: IPv6 addresses (e.g. "::1") are not supported for this NAS use case.
final class NASConnectionParser {

    /// Default HTTPS port for NAS devices.
    private static let defaultPort = 5001

    /// Parse a "host:port" string into a clean hostname and optional port.
    func parse(_ input: String) -> (host: String, port: Int) {
        // Try to find the last colon
        if let colonIndex = input.lastIndex(of: ":") {
            let potentialPort = input[input.index(after: colonIndex)...]
            if let port = Int(potentialPort), port >= 1, port <= 65535 {
                let host = String(input[..<colonIndex])
                return (host, port)
            }
        }
        return (input, Self.defaultPort)
    }
}