//
//  SessionService.swift
//  NasMon
//
//  Created by Brian Li on 8/1/26.
//

import Foundation

/// Orchestrates DSM session lifecycle: login, logout, session persistence, and credential management.
///
/// Responsibilities delegated to:
/// - `SessionStorage`: Keychain session/credential persistence
/// - `NASConnectionParser`: Host/port parsing
/// - `DSMErrorCodeFormatter`: Error code to user-facing messages
final class SessionService {

    static let shared = SessionService()

    private let storage = SessionStorage()
    private let parser = NASConnectionParser()
    private let errorFormatter = DSMErrorCodeFormatter()
    private let keychain = KeychainHelper.shared
    private let serverStore = ServerStore.shared

    // MARK: - Login

    /// Perform login and persist the session, credentials, and server entry.
    func login(host: String, account: String, password: String, name: String = "") async throws -> DSMClient {
        let (cleanHost, port) = parser.parse(host)
        let client = DSMClient(host: cleanHost, port: port)

        try await client.login(account: account, password: password)

        // Save session to Keychain
        client.saveSession()
        storage.setGlobalSessionPointers(host: cleanHost, port: port)

        // Save per-server SID (+ syno token) so tapping this server later can
        // reuse the session and call File Station APIs without re-login
        if let sid = client.sid {
            storage.saveServerSession(host: cleanHost, port: port, sid: sid, synotoken: client.synotoken)
        }

        // Save password for auto-login
        keychain.save(string: password, key: storage.passwordKey(host: cleanHost, port: port))

        // Save this server to the server list
        let serverName = name.isEmpty ? cleanHost : name
        let server = SavedServer(host: cleanHost, port: port, name: serverName, lastLoginAccount: account)
        serverStore.addServer(server)

        return client
    }

    // MARK: - Session Persistence

    /// Attempt to restore a previously saved session.
    /// Returns a client with the restored SID if a saved session exists.
    func restoreSession() -> DSMClient? {
        // Fresh-install guard: uninstalling the app wipes UserDefaults (the
        // saved server list) but leaves Keychain entries behind, so a reinstall
        // could silently resurrect the previous session and auto-log-in. If
        // there are no saved servers, any leftover Keychain data is stale from
        // a previous install — wipe it and start from a logged-out state.
        if serverStore.loadServers().isEmpty {
            storage.clearAllCredentials()
        }

        guard let sid = DSMClient.restoreSession() else { return nil }

        // Load saved host and port from Keychain
        let host = keychain.loadString(key: "dsm_host") ?? ""
        guard !host.isEmpty else {
            DSMClient.clearSession()
            return nil
        }

        let portString = keychain.loadString(key: "dsm_port") ?? ""
        let port = Int(portString) ?? 5001

        let client = DSMClient(host: host, port: port)
        client.sid = sid  // Restore the saved session ID
        client.synotoken = DSMClient.restoreSynoToken()  // Restore the syno token too
        return client
    }

    /// Clear only the saved session ID, keeping saved credentials intact.
    ///
    /// Use this when a session expires or the NAS is temporarily unreachable.
    /// The saved password remains in the Keychain so `tryAutoLogin` can still
    /// perform a fresh login without the user having to type the password again.
    func clearSessionID() {
        DSMClient.clearSession()
    }

    /// Clear all saved session and credential data.
    ///
    /// This is a full wipe — it removes the session ID **and** the saved password.
    /// Only call this when the user explicitly chooses to log out or delete a server.
    /// Do NOT call this from session-resume failure paths, otherwise a temporarily
    /// offline NAS would silently erase the saved password and force the user to
    /// re-enter it manually.
    func clearSession() {
        DSMClient.clearSession()
        storage.clearGlobalSessionAndCredentials()
    }

    // MARK: - Logout

    /// Perform server-side logout and remove the server from the saved list.
    /// Also clears the per-server cached SID and saved password for that server.
    func logout(client: DSMClient?) async {
        if let client {
            do {
                try await client.logout()
            } catch {
                print("Server logout failed: \(error)\n")
            }
            // Clear per-server SID for the logged-out server
            storage.clearServerSession(host: client.host, port: client.port)
        }

        let host = keychain.loadString(key: "dsm_host") ?? ""
        let portString = keychain.loadString(key: "dsm_port") ?? "5001"
        let port = Int(portString) ?? 5001

        if !host.isEmpty {
            serverStore.removeServer(host: host, port: port)
        }
    }

    // MARK: - Error Formatting

    /// Convert an error into a user-facing message.
    func describeError(_ error: Error) -> String {
        return errorFormatter.describeError(error)
    }
}
