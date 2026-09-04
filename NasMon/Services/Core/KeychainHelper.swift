//
//  KeychainHelper.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import Foundation

/// A simple Keychain wrapper for secure data storage.
class KeychainHelper {
    
    static let shared = KeychainHelper()
    
    private let serviceName = "com.nasmon.app"
    
    // MARK: - Public Methods
    
    /// Save string data to Keychain with the given key.
    @discardableResult
    func save(string: String, key: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data: data, key: key)
    }
    
    /// Save Data to Keychain with the given key.
    @discardableResult
    func save(data: Data, key: String) -> Bool {
        // Delete existing item first
        delete(key: key)
        
        var query = buildBaseQuery(key: key)
        query[kSecValueData as String] = data
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Load string from Keychain with the given key.
    func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Load Data from Keychain with the given key.
    func load(key: String) -> Data? {
        let query = buildLoadQuery(key: key) as CFDictionary
        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        
        guard status == errSecSuccess || status == errSecItemNotFound else { return nil }
        return result as? Data
    }
    
    /// Delete item from Keychain with the given key.
    func delete(key: String) {
        let query = buildBaseQuery(key: key) as CFDictionary
        SecItemDelete(query)
    }
    
    /// Delete all generic-password items stored under this app's service.
    ///
    /// The query is scoped to `kSecAttrService` = `serviceName`, so it only
    /// touches this app's own Keychain entries and never affects other apps.
    /// Returns `true` if the delete succeeded or nothing was found.
    @discardableResult
    func deleteAll() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Private
    
    /// Build a base query with service and account keys.
    private func buildBaseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
    }
    
    /// Build a query for loading data from Keychain.
    private func buildLoadQuery(key: String) -> [String: Any] {
        var query = buildBaseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
}