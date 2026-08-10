//
//  SavedServer.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import Foundation

/// Represents a saved NAS server that the user has logged into.
struct SavedServer: Codable, Identifiable, Hashable {
    let id: UUID
    let host: String
    let port: Int
    var name: String
    var displayName: String {
        name.isEmpty ? "\(host):\(port)" : name
    }
    var lastLoginAccount: String?

    init(host: String, port: Int = 5001, name: String = "", lastLoginAccount: String? = nil) {
        self.id = UUID()
        self.host = host
        self.port = port
        self.name = name
        self.lastLoginAccount = lastLoginAccount
    }
}
