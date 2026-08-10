//
//  SessionStorage.swift
//  NasMon
//
//  Created by Brian Li on 8/2/26.
//

import Foundation

/// Handles per-server session storage in Keychain (SID, syno token, password).
final class SessionStorage {

    private let keychain = KeychainHelper.shared

    // MARK: - Keychain Keys

    /// Keychain key for storing a server's password.
    func passwordKey(host: String, port: Int) -> String {
        return "password_\(host)_\(port)"
    }

    /// Keychain key for storing a server's session SID (per-server).
    private func sessionSIDKey(host: String, port: Int) -> String {
        return "dsm_session_sid_\(host)_\(port)"
    }

    /// Keychain key for storing a server's syno token (per-server).
    private func sessionSynoTokenKey(host: String, port: Int) -> String {
        return "dsm_session_synotoken_\(host)_\(port)"
    }

    // MARK: - Password Operations

    /// Load the saved password for a server, if any.
    func loadSavedPassword(host: String, port: Int) -> String? {
        return keychain.loadString(key: passwordKey(host: host, port: port))
    }

    /// Delete the saved password for a server.
    ///
    /// Use this when the server rejects the saved credentials (e.g. the user
    /// changed the password on the NAS). Removing the stale password ensures
    /// the next auto-login attempt falls through to the manual login screen
    /// instead of looping on repeated failures.
    func deleteSavedPassword(host: String, port: Int) {
        keychain.delete(key: passwordKey(host: host, port: port))
    }

    // MARK: - Per-Server Session SID

    /// Save a session SID (and syno token) for a specific server (host:port).
    /// This allows the app to try the cached SID when the user taps a
    /// previously-connected server, avoiding a fresh login if the session
    /// is still valid.
    func saveServerSession(host: String, port: Int, sid: String, synotoken: String? = nil) {
        keychain.save(string: sid, key: sessionSIDKey(host: host, port: port))
        if let synotoken {
            keychain.save(string: synotoken, key: sessionSynoTokenKey(host: host, port: port))
        }
    }

    /// Restore a DSMClient with the per-server cached SID (+ syno token), if any.
    /// Returns a client ready for session validation (e.g. `checkAdminPrivilege`)
    /// and File Station calls (uses the syno token via `SynoToken`).
    func restoreServerSession(host: String, port: Int) -> DSMClient? {
        guard let sid = keychain.loadString(key: sessionSIDKey(host: host, port: port)) else {
            return nil
        }
        let client = DSMClient(host: host, port: port)
        client.sid = sid
        client.synotoken = keychain.loadString(key: sessionSynoTokenKey(host: host, port: port))
        return client
    }

    /// Clear the per-server cached SID + syno token for a specific server.
    /// Called when the session expires (DSM code 119) or the user deletes the server.
    func clearServerSession(host: String, port: Int) {
        keychain.delete(key: sessionSIDKey(host: host, port: port))
        keychain.delete(key: sessionSynoTokenKey(host: host, port: port))
    }

    // MARK: - Global Session Pointers

    /// Update the global session pointers (host/port) to the given server.
    /// Called when auto-login succeeds with a per-server SID, so that
    /// `restoreSession()` on the next app launch finds the right server.
    func setGlobalSessionPointers(host: String, port: Int) {
        keychain.save(string: host, key: "dsm_host")
        keychain.save(string: String(port), key: "dsm_port")
    }

    /// Clear all saved session and credential data for the globally-set server.
    func clearGlobalSessionAndCredentials() {
        if let host = keychain.loadString(key: "dsm_host") {
            let portString = keychain.loadString(key: "dsm_port") ?? "5001"
            let port = Int(portString) ?? 5001
            keychain.delete(key: "password_\(host)_\(portString)")
            clearServerSession(host: host, port: port)
        }
        keychain.delete(key: "dsm_host")
        keychain.delete(key: "dsm_port")
    }

    // MARK: - Full Wipe

    /// Wipe every Keychain entry this app stores (global session pointers,
    /// global SID/syno token, and per-server passwords/SIDs/syno tokens),
    /// scoped to this app's Keychain service.
    ///
    /// Used on first launch after a reinstall: the app's UserDefaults (server
    /// list) is wiped on uninstall but Keychain entries survive, so a reinstall
    /// would otherwise silently resurrect the previous session. Per-server keys
    /// are keyed by host/port, which we can no longer enumerate once the server
    /// list is gone, so this clears the entire app service rather than trying
    /// to target individual keys.
    func clearAllCredentials() {
        keychain.deleteAll()
    }
}
