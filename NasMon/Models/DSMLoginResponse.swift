//
//  DSMLoginResponse.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import Foundation

struct DSMLoginResponse: Codable {
    let success: Bool
    let data: DSMLoginData?
    let error: DSMError?
}

struct DSMLoginData: Codable {
    let sid: String
    /// Token-based auth token. Returned when login is called with
    /// `enable_syno_token=yes`. Used for API calls via `SynoToken` query
    /// param or `X-SYNO-TOKEN` header (File Station, etc.).
    let synotoken: String?
}

struct DSMError: Codable {
    let code: Int
}