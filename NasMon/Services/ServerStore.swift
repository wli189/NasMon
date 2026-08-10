//
//  ServerStore.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import Foundation

/// Manages persistence of saved NAS servers using UserDefaults.
class ServerStore {

    static let shared = ServerStore()

    private let serversKey = "saved_servers"

    // MARK: - Public Methods

    /// Load all saved servers from UserDefaults.
    func loadServers() -> [SavedServer] {
        guard let data = UserDefaults.standard.data(forKey: serversKey) else {
            return []
        }
        do {
            let servers = try JSONDecoder().decode([SavedServer].self, from: data)
            return servers
        } catch {
            print("Failed to decode saved servers: \(error)\n")
            return []
        }
    }

    /// Save a list of servers to UserDefaults.
    func saveServers(_ servers: [SavedServer]) {
        do {
            let data = try JSONEncoder().encode(servers)
            UserDefaults.standard.set(data, forKey: serversKey)
        } catch {
            print("Failed to encode saved servers: \(error)\n")
        }
    }

    /// Add a server to the saved list (or update if already exists).
    func addServer(_ server: SavedServer) {
        var servers = loadServers()
        // Remove existing entry with same host:port
        servers.removeAll { $0.host == server.host && $0.port == server.port }
        servers.append(server)
        saveServers(servers)
    }

    /// Remove a server from the saved list.
    func removeServer(_ server: SavedServer) {
        var servers = loadServers()
        servers.removeAll { $0.id == server.id }
        saveServers(servers)
    }

    /// Update the last login account for a server.
    func updateLastLogin(host: String, port: Int, account: String) {
        var servers = loadServers()
        if let index = servers.firstIndex(where: { $0.host == host && $0.port == port }) {
            servers[index].lastLoginAccount = account
        }
        saveServers(servers)
    }

    /// Remove the server that was most recently used for login.
    /// This is used during logout to remove the server from the list.
    func removeLastServer() {
        var servers = loadServers()
        guard !servers.isEmpty else { return }
        // Remove the last server in the list (most recently added)
        servers.removeLast()
        saveServers(servers)
    }
    
    /// Remove a specific server by host and port.
    func removeServer(host: String, port: Int) {
        var servers = loadServers()
        servers.removeAll { $0.host == host && $0.port == port }
        saveServers(servers)
    }
}
