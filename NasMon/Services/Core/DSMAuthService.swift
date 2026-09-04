//
//  DSMAuthService.swift
//  NasMon
//
//  DSM authentication service - handles login, logout, and session management
//  for Synology DSM devices. Designed to be extended for other NAS brands
//  by creating separate service modules (e.g., DS365AuthService, QNAPService).
//

import Foundation

// MARK: - Auth Service
/// Handles authentication operations for DSM devices including login, logout,
/// admin privilege checks, and session persistence.
extension DSMClient {
    
    // MARK: Login
    
    func login(account: String, password: String) async throws {
        guard let url = makeURL(
            path: "/webapi/auth.cgi",
            queryItems: [
                URLQueryItem(name: "api", value: "SYNO.API.Auth"),
                URLQueryItem(name: "version", value: "6"),
                URLQueryItem(name: "method", value: "login"),
                URLQueryItem(name: "account", value: account),
                URLQueryItem(name: "passwd", value: password),
                URLQueryItem(name: "format", value: "sid"),
                // Enable token-based auth so File Station APIs can be called
                // with `SynoToken` (the alternative to `_sid`).
                URLQueryItem(name: "enable_syno_token", value: "yes"),
            ]
        ) else { throw DSMClientError.invalidURL }
        
        let (data, _) = try await session.data(from: url)
        
        let decoded: DSMLoginResponse
        do {
            decoded = try JSONDecoder().decode(DSMLoginResponse.self, from: data)
        } catch {
            throw DSMClientError.decodingFailed(error)
        }
        
        guard decoded.success, let sid = decoded.data?.sid else {
            throw DSMClientError.loginFailed(code: decoded.error?.code)
        }
        
        self.sid = sid
        self.synotoken = decoded.data?.synotoken
        self.account = account
        // Streaming capabilities change with each login — clear the cached probe.
        self.streamingProbe.reset()
        print("DSM login OK, sid: \(sid.prefix(8))..., synotoken: \(self.synotoken?.prefix(8) ?? "none")...")
    }
    
    // MARK: - Account Info
    
    /// Check if the logged-in account has admin privileges.
    /// DSM returns privileges like "admin", "video_surveillance", etc.
    ///
    /// This method also serves as a session-validation probe: when the SID
    /// has expired, DSM returns error code 119, which is thrown as
    /// `DSMClientError.loginFailed(code: 119)` so callers can detect session
    /// expiry and trigger a silent re-login.
    func checkAdminPrivilege() async throws -> Bool {
        guard let sid, !sid.isEmpty else { throw DSMClientError.noSession }
        let queryItems = [
            URLQueryItem(name: "api", value: "SYNO.Core.System"),
            URLQueryItem(name: "version", value: "1"),
            URLQueryItem(name: "method", value: "info"),
        ] + authQueryItems
        guard let url = makeURL(path: "/webapi/entry.cgi", queryItems: queryItems)
        else { throw DSMClientError.invalidURL }
        
        let (data, _) = try await session.data(from: url)
        
        struct DSMGenericResponse: Codable {
            let success: Bool
            let error: DSMErrorDetail?
        }
        struct DSMErrorDetail: Codable {
            let code: Int
        }
        
        let decoded = try JSONDecoder().decode(DSMGenericResponse.self, from: data)
        
        if decoded.success {
            return true
        }
        
        // DSM returns code 1006 when the account lacks admin privileges.
        // Treat both as "logged in but not admin" instead of a login failure.
        if decoded.error?.code == 1006 {
            return false
        }
        
        throw DSMClientError.loginFailed(code: decoded.error?.code)
    }
    
    // MARK: Logout
    
    /// Log out from the DSM server by ending the session.
    func logout() async throws {
        guard let sid, !sid.isEmpty else { throw DSMClientError.noSession }
        guard let url = makeURL(
            path: "/webapi/entry.cgi",
            queryItems: [
                URLQueryItem(name: "api", value: "SYNO.API.Auth"),
                URLQueryItem(name: "version", value: "6"),
                URLQueryItem(name: "method", value: "logout"),
            ] + authQueryItems
        ) else {
            // Even if we can't reach the server, clear local state
            self.sid = nil
            throw DSMClientError.invalidURL
        }
        
        let (data, _) = try await session.data(from: url)
        
        struct DSMLogoutResponse: Codable {
            let success: Bool
            let error: DSMErrorDetail?
        }
        struct DSMErrorDetail: Codable {
            let code: Int
        }
        
        let decoded = try JSONDecoder().decode(DSMLogoutResponse.self, from: data)
        self.sid = nil  // Clear local session ID
        self.synotoken = nil  // Clear local syno token
        if !decoded.success {
            throw DSMClientError.logoutFailed(code: decoded.error?.code)
        }
        
        print("DSM logout successful")
    }
    
    // MARK: - Session Persistence
    
    /// Save the current session (SID + syno token) to Keychain for persistence.
    func saveSession() {
        guard let sid else { return }
        let saved = KeychainHelper.shared.save(string: sid, key: "dsm_session_sid")
        // Persist the syno token too so File Station calls work after session restore
        if let synotoken {
            KeychainHelper.shared.save(string: synotoken, key: "dsm_session_synotoken")
        }
        print("Session saved to Keychain: \(saved ? "yes" : "no")\n")
    }
    
    /// Restore the session SID from Keychain.
    /// Callers should also load the syno token via `restoreSynoToken()`.
    static func restoreSession() -> String? {
        return KeychainHelper.shared.loadString(key: "dsm_session_sid")
    }
    
    /// Restore the syno token from Keychain (saved alongside the SID).
    static func restoreSynoToken() -> String? {
        return KeychainHelper.shared.loadString(key: "dsm_session_synotoken")
    }
    
    /// Clear the saved session (SID + syno token) from Keychain.
    static func clearSession() {
        KeychainHelper.shared.delete(key: "dsm_session_sid")
        KeychainHelper.shared.delete(key: "dsm_session_synotoken")
    }
}
