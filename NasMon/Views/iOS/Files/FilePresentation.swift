//
//  FilePresentation.swift
//  NasMon
//
//  SwiftUI presentation details for NAS files. File semantics remain in the
//  platform-neutral Models layer.
//

import SwiftUI

extension DSMFile {
    /// Theme color for the file/folder icon.
    var iconColor: Color {
        if isdir { return .nasMonAccent }

        switch fileExtension {
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
