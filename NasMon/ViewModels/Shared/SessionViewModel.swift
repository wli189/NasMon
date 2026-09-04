//
//  SessionViewModel.swift
//  NasMon
//
//  Created by Brian Li on 8/1/26.
//

import Foundation
import Observation

@Observable
final class SessionViewModel {

    // MARK: - Connection state

    enum ConnectionState: Equatable {
        case idle
        case loggingIn
        case loggedIn
        case failed(String)
    }

    var connectionState: ConnectionState = .idle

    // MARK: - Data

    var isAdmin = false
    var savedServers: [SavedServer] = []
    /// The ID of the server currently attempting auto-login, if any.
    var autoLoggingInServerID: UUID?

    /// When set, the server selection view auto-presents the login sheet for
    /// this server. Used on app startup when the saved password is stale (DSM
    /// error 407) so the user is prompted to re-enter credentials without
    /// having to manually tap the server.
    var pendingLoginServer: SavedServer?

    /// Whether the most recent login failed due to rejected credentials
    /// (as opposed to a network/connectivity problem). Used by `tryAutoLogin`
    /// to decide whether the saved password is stale and should be removed.
    private var lastLoginWasCredentialError = false

    // MARK: - Dependencies

    /// The active DSM client for the current session.
    var activeClient: DSMClient?

    private let sessionService = SessionService.shared
    private let storage = SessionStorage()
    private let serverStore = ServerStore.shared

    // MARK: - Server List

    /// Load the saved server list.
    /// The server matching the active client (with a valid session) is sorted to the top.
    func loadServers() {
        var servers = serverStore.loadServers()
        // If there's an active client with a valid session, move its server to the front.
        if let client = activeClient, client.sid != nil {
            servers.sort { a, b in
                let aIsActive = a.host == client.host && a.port == client.port
                let bIsActive = b.host == client.host && b.port == client.port
                return aIsActive && !bIsActive
            }
        }
        savedServers = servers
    }

    /// Remove a saved server.
    /// Clears the per-server cached SID and saved password, then removes the
    /// server from the list. If the server being removed is the active session,
    /// also performs server-side logout and clears local session state.
    func removeServer(_ server: SavedServer) async {
        // Always clear the per-server SID and saved password for the removed server
        storage.clearServerSession(host: server.host, port: server.port)
        storage.deleteSavedPassword(host: server.host, port: server.port)

        // If this server is the active session, perform server-side logout first
        if let client = activeClient,
           client.sid != nil,
           client.host == server.host,
           client.port == server.port {
            await sessionService.logout(client: client)
            clearSession()
        } else {
            // Just remove the server from the list
            serverStore.removeServer(server)
        }
        loadServers()
    }

    // MARK: - Login

    func login(host: String, account: String, password: String, name: String = "") async {
        connectionState = .loggingIn

        do {
            let client = try await sessionService.login(
                host: host,
                account: account,
                password: password,
                name: name
            )
            self.activeClient = client

            // Check if the account has admin privileges
            isAdmin = try await client.checkAdminPrivilege()

            connectionState = .loggedIn
        } catch {
            // Record whether the failure was a credential rejection (DSM error
            // code 407 = wrong password, 400 = invalid account) as opposed to a
            // network/connectivity problem. `tryAutoLogin` uses this flag to
            // decide whether the saved password is stale and should be deleted.
            lastLoginWasCredentialError = {
                if case DSMClientError.loginFailed(let code) = error {
                    // 400 = no such account, 401 = account disabled,
                    // 403 = permission denied, 404 = guest account disabled,
                    // 405 = account not specified, 406 = password not specified,
                    // 407 = account/password mismatch
                    if let code, (400...407).contains(code) {
                        return true
                    }
                }
                return false
            }()
            connectionState = .failed(sessionService.describeError(error))
        }
    }

    /// Attempt to auto-login with saved credentials for a given server.
    /// Returns `true` if login succeeded OR if a network error occurred (the
    /// `.failed` state drives the error alert). Returns `false` if credentials
    /// are missing or were rejected, so the caller can present the login sheet.
    ///
    /// If the server rejects the saved credentials (e.g. the user changed the
    /// password on the NAS), the stale password is deleted from the Keychain and
    /// `false` is returned so the caller can present the manual login screen.
    /// Network failures (NAS offline/unreachable) keep the password intact so a
    /// later attempt can still auto-login without re-entering it.
    func tryAutoLogin(host: String, port: Int, account: String) async -> Bool {
        guard let password = storage.loadSavedPassword(host: host, port: port) else {
            return false
        }
        await login(host: "\(host):\(port)", account: account, password: password)

        // If the login failed because the server rejected the credentials,
        // the saved password is stale (e.g. changed on the NAS). Delete it so
        // the next attempt falls through to the manual login screen instead of
        // looping on repeated failures.
        if case .failed = connectionState,
            lastLoginWasCredentialError {
             storage.deleteSavedPassword(host: host, port: port)
            return false
        }

        // Success → .loggedIn, or network failure → .failed (error alert shows).
        // Either way, don't present the login sheet.
        return true
    }

    /// Try to auto-login to a saved server using the "SID-first → password-fallback" strategy.
    ///
    /// Flow:
    /// 1. If there's already an active client with a valid SID on the same server,
    ///    validate it with a lightweight API call. If valid → enter directly.
    /// 2. Try the per-server cached SID (from Keychain). If valid → enter directly.
    /// 3. If the SID is expired (DSM 119) or missing, fall back to password login
    ///    using the saved credentials. If the password is rejected (DSM 407),
    ///    delete the stale password and return `false` so the login sheet appears.
    /// 4. Network errors (timeout, unreachable) show an error alert and keep all
    ///    saved data intact so the user can retry.
    ///
    /// - Returns: `true` if login succeeded or a network error occurred (error
    ///   alert shown via `.failed`). `false` if credentials are missing/rejected
    ///   and the login sheet should be presented.
    func autoLogin(to server: SavedServer) async -> Bool {
        autoLoggingInServerID = server.id
        defer { autoLoggingInServerID = nil }

        // Step 1: Reuse the active client if it's already on the same server
        if let client = activeClient,
           client.sid != nil,
           client.host == server.host,
           client.port == server.port {
            do {
                isAdmin = try await client.checkAdminPrivilege()
                connectionState = .loggedIn
                return true
            } catch {
                if case DSMClientError.loginFailed(let code) = error, code == 119 {
                    // Session expired — clear SIDs and fall through to password login
                    client.sid = nil
                    sessionService.clearSessionID()
                    storage.clearServerSession(host: server.host, port: server.port)
                } else {
                    // Network error — keep state, show error alert
                    connectionState = .failed(sessionService.describeError(error))
                    return true
                }
            }
        }

        // Step 2: Try the per-server cached SID
        if let client = storage.restoreServerSession(host: server.host, port: server.port) {
            do {
                isAdmin = try await client.checkAdminPrivilege()
                // SID is still valid — use it directly, no login needed
                self.activeClient = client
                // Promote this session to the global session so resumeSession()
                // on the next app launch finds the right server
                client.saveSession()
                storage.setGlobalSessionPointers(host: server.host, port: server.port)
                connectionState = .loggedIn
                return true
            } catch {
                if case DSMClientError.loginFailed(let code) = error, code == 119 {
                    // Session expired — clear the stale per-server SID, fall through
                    storage.clearServerSession(host: server.host, port: server.port)
                } else {
                    // Network error — keep the client for the Active badge,
                    // show error alert, preserve password for retry
                    self.activeClient = client
                    connectionState = .failed(sessionService.describeError(error))
                    return true
                }
            }
        }

        // Step 3: No valid SID — fall back to saved password
        guard let account = server.lastLoginAccount else {
            return false
        }

        return await tryAutoLogin(
            host: server.host,
            port: server.port,
            account: account
        )
    }

    // MARK: - Session Resume (App Launch)

    /// Attempt to resume a previously saved session on app launch.
    ///
    /// Flow:
    /// 1. Restore the global session (SID + host/port) and validate the SID.
    /// 2. If the SID is valid → enter Dashboard directly (no user interaction).
    /// 3. If the SID expired (DSM 119) → silently re-login with the saved password.
    ///    - If re-login succeeds → enter Dashboard.
    ///    - If re-login fails with 407 (credentials rejected) → delete the stale
    ///      password and set `pendingLoginServer` so the login sheet auto-appears.
    ///    - If re-login fails with a network error → show error alert, keep state.
    /// 4. If the SID validation fails with a network error → show error alert,
    ///    keep the Active badge and saved data so the user can retry.
    func resumeSession() async {
        guard let client = sessionService.restoreSession() else {
            connectionState = .idle
            return
        }

        // Validate the saved SID by fetching a lightweight API
        do {
            isAdmin = try await client.checkAdminPrivilege()
            self.activeClient = client
            connectionState = .loggedIn
        } catch {
            // Session expired (DSM 119) — silently re-login with saved password
            if case DSMClientError.loginFailed(let code) = error, code == 119 {
                sessionService.clearSessionID()
                storage.clearServerSession(host: client.host, port: client.port)

                // `resumeSession()` runs on app launch before the server list
                // view has appeared, so `savedServers` may not be populated yet.
                // Load from storage directly to reliably find the server entry.
                let servers = serverStore.loadServers()
                if let server = servers.first(where: {
                    $0.host == client.host && $0.port == client.port
                }),
                   let account = server.lastLoginAccount,
                   let password = storage.loadSavedPassword(
                    host: server.host,
                    port: server.port
                   ) {
                    await login(
                        host: "\(server.host):\(server.port)",
                        account: account,
                        password: password
                    )

                    // If re-login failed because credentials were rejected (407),
                    // the saved password is stale. Delete it and auto-present the
                    // login sheet so the user can re-enter the correct password.
                    if case .failed = connectionState, lastLoginWasCredentialError {
                        storage.deleteSavedPassword(host: server.host, port: server.port)
                        pendingLoginServer = server
                    }
                    // Network failure → .failed is set, error alert shows on
                    // server selection. Password and Active badge are preserved.
                    return
                }

                // No saved credentials to retry with — show server selection
                connectionState = .idle
                return
            }

            // Network/connectivity error (timeout, NAS offline, etc.)
            //
            // Keep `activeClient` and the SID intact so the server list still
            // shows the "Active" badge for the previously connected server.
            // When the user taps that server, `autoLogin` re-validates the SID:
            //   - NAS back online + SID valid   → straight into the dashboard
            //   - NAS back online + SID expired → falls through to `tryAutoLogin`
            //     using the saved password (no manual re-entry needed)
            //   - NAS still offline             → shows the connection error
            //
            // We deliberately do NOT call `clearSessionID()` here — clearing the
            // SID would remove the Active badge and force a fresh login even
            // though the session may still be perfectly valid.
            //
            // Set `.failed` so the server list's "Connection Failed" alert
            // explains why auto-login didn't happen (e.g. NAS offline).
            self.activeClient = client
            connectionState = .failed(sessionService.describeError(error))
        }
    }

    // MARK: - Logout / Session Clear

    /// Perform server-side logout, remove the server from the list, and clear local state.
    func logout() async {
        await sessionService.logout(client: activeClient)
        clearSession()
    }

    /// Clear local state without performing a server-side logout.
    func clearSession() {
        activeClient = nil
        isAdmin = false
        autoLoggingInServerID = nil
        pendingLoginServer = nil
        sessionService.clearSession()
        connectionState = .idle
    }

    /// Return to the server selection screen without clearing saved servers.
    func returnToServerSelection() {
        // Keep activeClient (and its SID) so the session can be reused when the
        // user re-selects the same server. Previously we nil'd it out here, which
        // forced a fresh login — minting a new SID — every time the user
        // re-entered from the server list.
        isAdmin = false
        connectionState = .idle
    }
}
