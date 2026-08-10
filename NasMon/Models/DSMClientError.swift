//
//  DSMClientError.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import Foundation

enum DSMClientError: Error {
    case invalidURL
    case loginFailed(code: Int?)
    case logoutFailed(code: Int?)
    case noSession
    case decodingFailed(Error)
    case shutdownFailed(String)
    case fileStationFailed(code: Int?)
}
