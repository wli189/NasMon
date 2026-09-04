//
//  DSMErrorCodeFormatter.swift
//  NasMon
//
//  Created by Brian Li on 8/2/26.
//

import Foundation

/// Maps DSM and File Station error codes to user-facing messages.
final class DSMErrorCodeFormatter {

    /// Convert an error into a user-facing message.
    func describeError(_ error: Error) -> String {
        if let dsmError = error as? DSMClientError {
            switch dsmError {
            case .invalidURL: return "Invalid host/URL."
            case .loginFailed(let code):
                // Provide user-friendly messages for common DSM auth error codes
                switch code {
                case 400: return "Account not found. Please check and re-enter your credentials."
                case 401: return "This account has been disabled on the NAS."
                case 403: return "Permission denied. This account may not have access."
                case 404: return "Guest account is disabled on the NAS."
                case 406: return "Password not specified."
                case 407: return "Incorrect password. The password may have been changed on the NAS — please re-enter it."
                case 119: return "Session expired. Please log in again."
                default: return "Login failed (code: \(code.map(String.init) ?? "?"))."
                }
            case .logoutFailed(let code): return "Logout failed (code: \(code.map(String.init) ?? "?"))."
            case .noSession: return "No active session."
            case .decodingFailed: return "Couldn't parse DSM response — check field names against raw JSON."
            case .shutdownFailed(let message): return message
            case .fileStationFailed(let code):
                if let code {
                    // Synology File Station WebAPI error codes
                    switch code {
                    case 400: return "Invalid parameter of file operation."
                    case 401: return "Unknown error of file operation."
                    case 402: return "The system is too busy."
                    case 403: return "Invalid user does this file operation."
                    case 404: return "Invalid group does this file operation."
                    case 405: return "Invalid user and group does this file operation."
                    case 406: return "Can't get user/group information from the account server."
                    case 407: return "Operation not permitted."
                    case 408: return "No such file or directory."
                    case 409: return "Non-supported file system."
                    case 410: return "Failed to connect internet-based file system (e.g., CIFS)."
                    case 411: return "Read-only file system."
                    case 412: return "Filename too long in the non-encrypted file system."
                    case 413: return "Filename too long in the encrypted file system."
                    case 414: return "File already exists."
                    case 415: return "Disk quota exceeded."
                    case 416: return "No space left on device."
                    case 417: return "Input/output error."
                    case 418: return "Illegal name or path."
                    case 419: return "Illegal file name."
                    case 420: return "Illegal file name on FAT file system."
                    case 421: return "Device or resource busy."
                    case 599: return "No such task of the file operation."
                    default: return "File Station error (code: \(code))."
                    }
                }
                return "File Station request failed. The NAS may have returned an HTML error page — check the API endpoint and parameters."
            }
        }
        // Preview system errors
        if let previewError = error as? PreviewError {
            switch previewError {
            case .notPreviewable:
                return "This file type cannot be previewed."
            }
        }

        // Give a clear message for network timeouts (e.g. NAS unreachable)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "Connection timed out. The NAS may be unreachable or offline."
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return "Cannot connect to the NAS. Check your network connection."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}