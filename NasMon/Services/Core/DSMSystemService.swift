//
//  DSMSystemService.swift
//  NasMon
//
//  DSM system monitoring service - handles system info, utilization data,
//  and power management (reboot/shutdown) for Synology DSM devices.
//  Designed to be extended for other NAS brands by creating separate
//  service modules (e.g., DS365SystemService, QNAPSystemService).
//

import Foundation

// MARK: - DSM System Service
/// Handles system monitoring operations for Synology DSM devices including fetching
/// system info, utilization data, and power management (reboot/shutdown).
extension DSMClient {
    
    // MARK: System Info
    
    func fetchSystemInfo() async throws -> DSMSystemInfoData {
        guard let sid, !sid.isEmpty else { throw DSMClientError.noSession }
        guard let url = makeURL(
            path: "/webapi/entry.cgi",
            queryItems: [
                URLQueryItem(name: "api", value: "SYNO.Core.System"),
                URLQueryItem(name: "version", value: "1"),
                URLQueryItem(name: "method", value: "info"),
            ] + authQueryItems
        ) else { throw DSMClientError.invalidURL }
        
        let (data, _) = try await session.data(from: url)
        
        // Print raw JSON while you're still confirming field names
        if let raw = String(data: data, encoding: .utf8) {
            print("Raw system info response:\n\(raw)\n")
        }
        
        let decoded = try JSONDecoder().decode(DSMSystemInfoResponse.self, from: data)
        guard let info = decoded.data else { throw DSMClientError.loginFailed(code: nil) }
        return info
    }
    
    // MARK: Utilization
    
    func fetchUtilization() async throws -> DSMUtilizationData {
        guard let sid, !sid.isEmpty else { throw DSMClientError.noSession }
        guard let url = makeURL(
            path: "/webapi/entry.cgi",
            queryItems: [
                URLQueryItem(name: "api", value: "SYNO.Core.System.Utilization"),
                URLQueryItem(name: "version", value: "1"),
                URLQueryItem(name: "method", value: "get"),
            ] + authQueryItems
        ) else { throw DSMClientError.invalidURL }
        
        let (data, _) = try await session.data(from: url)
        
        if let raw = String(data: data, encoding: .utf8) {
            print("Raw utilization response:\n\(raw)\n")
        }
        
        let decoded = try JSONDecoder().decode(DSMUtilizationResponse.self, from: data)
        guard let util = decoded.data else { throw DSMClientError.loginFailed(code: nil) }
        return util
    }
    
    // MARK: Reboot / Shutdown
    
    /// Send a reboot or shutdown command to the NAS.
    ///
    /// DSM's `SYNO.Core.System` API uses two separate methods:
    ///   - `method=reboot`   → reboot the NAS
    ///   - `method=shutdown` → shut the NAS down
    /// Passing the wrong method (e.g. always "shutdown") would shut down the NAS
    /// even when a reboot was requested.
    ///
    /// - Parameter method: "reboot" or "shutdown"
    private func sendPowerCommand(method: String) async throws {
        guard let sid, !sid.isEmpty else { throw DSMClientError.noSession }
        guard let url = makeURL(
            path: "/webapi/entry.cgi",
            queryItems: [
                URLQueryItem(name: "api", value: "SYNO.Core.System"),
                URLQueryItem(name: "version", value: "1"),
                URLQueryItem(name: "method", value: method),
            ] + authQueryItems
        ) else { throw DSMClientError.invalidURL }
        
        let (data, _) = try await session.data(from: url)
        
        if let raw = String(data: data, encoding: .utf8) {
            print("Raw \(method) response:\n\(raw)\n")
        }
        
        // Decode the response. DSM API returns {"success": true} on success.
        struct PowerResponse: Codable {
            let success: Bool
        }
        
        let decoded = try JSONDecoder().decode(PowerResponse.self, from: data)
        guard decoded.success else {
            throw DSMClientError.shutdownFailed("NAS returned failure for \(method) command.")
        }
    }
    
    /// Reboot the NAS.
    func reboot() async throws {
        try await sendPowerCommand(method: "reboot")
    }
    
    /// Shut down the NAS.
    func shutdown() async throws {
        try await sendPowerCommand(method: "shutdown")
    }
}
