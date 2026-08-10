//
//  DSMFileStationModels.swift
//  NasMon
//
//  Created by Brian Li on 8/1/26.
//

import Foundation
import SwiftUI

// MARK: - Shared Response Envelope

/// Generic File Station response envelope: `{"success": true, "data": {...}}`
/// or `{"success": false, "error": {"code": ...}}`.
struct DSMFSResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: DSMFSError?
}

/// Error detail returned by File Station APIs.
struct DSMFSError: Codable {
    let code: Int
}

// MARK: - List Shares (SYNO.FileStation.List / list_share)

struct DSMListShareResponse: Codable {
    let success: Bool
    let data: DSMListShareData?
    let error: DSMFSError?
}

struct DSMListShareData: Codable {
    let shares: [DSMShare]
    let total: Int
}

/// A shared folder on the NAS.
struct DSMShare: Codable, Identifiable, Hashable {
    /// Unique path of the shared folder, used as the identifier.
    var id: String { path }

    /// Path of the shared folder, e.g. "/home".
    let path: String
    /// Name of the shared folder, e.g. "home".
    let name: String
    /// Whether this is a directory (always true for shares).
    let isdir: Bool?
    /// Additional info for some shares (disk/volume info for `SYNO.FileStation.List.Additional`).
    let additional: DSMShareAdditional?
}

// MARK: - Additional Share Info

struct DSMShareAdditional: Codable, Hashable {
    let volume: DSMVolume?
    let size: Int64?
    let time: DSMFileTime?
}

struct DSMVolume: Codable, Hashable {
    let free_space: Int64?
    let total_space: Int64?
}

// MARK: - List Files (SYNO.FileStation.List / list)

struct DSMListFilesResponse: Codable {
    let success: Bool
    let data: DSMListFilesData?
    let error: DSMFSError?
}

struct DSMListFilesData: Codable {
    let files: [DSMFile]
    let total: Int
}

/// A file or folder entry returned by `SYNO.FileStation.List`.
struct DSMFile: Codable, Identifiable, Hashable {
    /// Unique path of the file/folder, used as the identifier.
    var id: String { path }

    let path: String
    let name: String
    let isdir: Bool
    let additional: DSMFileAdditional?
}

struct DSMFileAdditional: Codable, Hashable {
    let size: Int64?
    let type: String?
    let mtime: Int64?
    let atime: Int64?
    let ctime: Int64?
    let crtime: Int64?
    let owner: DSMFileOwner?
    /// Nested time object: `{"atime":..., "crtime":..., "ctime":..., "mtime":...}`
    let time: DSMFileTime?
    let perm: DSMFilePermission?
    let mountPointType: String?
    let realPath: String?
    let volumeStatus: DSMVolumeStatus?

    enum CodingKeys: String, CodingKey {
        case size
        case type
        case mtime
        case atime
        case ctime
        case crtime
        case owner
        case time
        case perm
        case mountPointType = "mount_point_type"
        case realPath = "real_path"
        case volumeStatus = "volume_status"
    }
}

/// Nested time object returned in `additional.time`.
struct DSMFileTime: Codable, Hashable {
    let atime: Int64?
    let crtime: Int64?
    let ctime: Int64?
    let mtime: Int64?
}

struct DSMFileOwner: Codable, Hashable {
    let user: String?
    let group: String?
    let uid: Int?
    let gid: Int?
}

struct DSMFilePermission: Codable, Hashable {
    let aclEnabled: Bool?
    /// ACL object: `{"append":true,"del":true,"exec":true,"read":true,"write":true}`
    let acl: DSMFileACL?
    let isACLEnabled: Bool?
    let isAccessRightEditable: Bool?
    let isAccessRightEditableAndEnabled: Bool?
    let posix: Int?

    enum CodingKeys: String, CodingKey {
        case acl
        case aclEnabled = "acl_enabled"
        case isACLEnabled = "is_acl_enabled"
        case isAccessRightEditable = "is_access_right_editable"
        case isAccessRightEditableAndEnabled = "is_access_right_editable_and_enabled"
        case posix
    }
}

/// ACL permission object returned in `additional.perm.acl`.
struct DSMFileACL: Codable, Hashable {
    let append: Bool?
    let del: Bool?
    let exec: Bool?
    let read: Bool?
    let write: Bool?
}

struct DSMVolumeStatus: Codable, Hashable {
    let free_space: Int64?
    let total_space: Int64?
    let readonly: Bool?
}

// MARK: - File Preview Type

/// Categorizes a file for preview rendering.
enum FilePreviewType {
    /// Image formats (jpg, png, heic, etc.)
    case image
    /// Video formats (mp4, mov, mkv, etc.)
    case video
    /// Audio formats (mp3, flac, m4a, etc.)
    case audio
    /// PDF documents
    case pdf
    /// Plain-text / code files (txt, md, json, swift, etc.)
    case text
    /// Any other file type — show metadata only
    case other
}

// MARK: - Formatters

extension DSMFile {
    /// Human-readable file size (e.g. "1.5 MB").
    var formattedSize: String {
        guard let size = additional?.size else {
            return isdir ? "—" : "—"
        }
        return Self.formatBytes(size)
    }

    /// Human-readable last-modified time.
    /// DSM returns `mtime` inside the nested `additional.time` object.
    var formattedModifiedDate: String {
        guard let mtime = additional?.time?.mtime ?? additional?.mtime else { return "—" }
        let date = Date(timeIntervalSince1970: Double(mtime))
        return Self.formattedDateFormatter.string(from: date)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Format a Unix timestamp as a human-readable date string.
    static func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp))
        return formattedDateFormatter.string(from: date)
    }

    // MARK: - File Type Helpers

    /// Lowercased file extension (without the dot), e.g. "jpg".
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    /// Categorize the file for preview rendering.
    ///
    /// Only formats that AVFoundation can actually decode are treated as
    /// playable media. iOS has no decoder for WMA/OGG/OPUS audio or
    /// AVI/MKV/WEBM/FLV/WMV video — classifying them as `.other` avoids
    /// downloading the file just to fail playback.
    var previewType: FilePreviewType {
        switch fileExtension {
        // Images
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tiff":
            return .image
        // Videos (iOS-decodable containers only)
        case "mp4", "mov", "m4v", "mpg", "mpeg", "3gp":
            return .video
        // Audio (iOS-decodable formats only)
        case "mp3", "wav", "flac", "aac", "m4a", "aiff", "alac":
            return .audio
        // PDF
        case "pdf":
            return .pdf
        // Text / code
        case "txt", "md", "text", "json", "xml", "html", "css", "js", "ts",
             "swift", "py", "sh", "yml", "yaml", "c", "cpp", "h", "java",
             "go", "rb", "php", "csv", "rtf", "log", "conf", "ini", "sql",
             "dockerfile", "makefile", "properties":
            return .text
        default:
            return .other
        }
    }

    /// Whether the file is a code file (for monospace rendering).
    var isCodeFile: Bool {
        switch fileExtension {
        case "swift", "py", "js", "ts", "html", "css", "json", "xml",
             "c", "cpp", "h", "java", "go", "rb", "php", "sh", "yml", "yaml",
             "sql", "dockerfile", "makefile":
            return true
        default:
            return false
        }
    }

    private static let formattedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - File Type Icon

    /// SF Symbol name for the file/folder based on its type.
    var iconName: String {
        if isdir { return "folder.fill" }

        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        // Images
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tiff", "svg", "raw":
            return "photo.fill"
        // Videos
        case "mp4", "mov", "avi", "mkv", "webm", "flv", "wmv", "m4v", "mpg", "mpeg", "3gp":
            return "film.fill"
        // Audio
        case "mp3", "wav", "flac", "aac", "m4a", "ogg", "opus", "wma", "aiff", "alac":
            return "music.note"
        // Documents
        case "pdf":
            return "doc.richtext.fill"
        case "doc", "docx", "pages", "rtf", "txt", "md", "text":
            return "doc.text.fill"
        case "xls", "xlsx", "numbers", "csv":
            return "tablecells.fill"
        case "ppt", "pptx", "key":
            return "chart.bar.fill"
        // Archives
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "iso", "dmg":
            return "archivebox.fill"
        // Code
        case "swift", "py", "js", "ts", "html", "css", "json", "xml", "c", "cpp", "h", "java", "go", "rb", "php", "sh", "yml", "yaml":
            return "chevron.left.forwardslash.chevron.right"
        // Executables
        case "app", "exe", "pkg", "deb", "rpm":
            return "app.fill"
        default:
            return "doc.fill"
        }
    }

    /// Color for the file/folder icon.
    var iconColor: Color {
        if isdir { return .nasMonAccent }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tiff", "svg", "raw":
            return .nasMonFileImage
        case "mp4", "mov", "avi", "mkv", "webm", "flv", "wmv", "m4v", "mpg", "mpeg", "3gp":
            return .nasMonFileVideo
        case "mp3", "wav", "flac", "aac", "m4a", "ogg", "opus", "wma", "aiff", "alac":
            return .nasMonFileAudio
        case "pdf":
            return .nasMonCritical
        case "doc", "docx", "pages", "rtf", "txt", "md", "text":
            return .nasMonAccent
        case "xls", "xlsx", "numbers", "csv":
            return .nasMonOnline
        case "ppt", "pptx", "key":
            return .nasMonWarning
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "iso", "dmg":
            return .secondary
        case "swift", "py", "js", "ts", "html", "css", "json", "xml", "c", "cpp", "h", "java", "go", "rb", "php", "sh", "yml", "yaml":
            return .nasMonFileText
        default:
            return .secondary
        }
    }
}

extension DSMShare {
    /// Human-readable free space string (e.g. "1.2 TB free").
    var formattedFreeSpace: String {
        guard let free = additional?.volume?.free_space else { return "—" }
        return DSMFile.formatBytes(free)
    }
}