//
//  PreviewRouter.swift
//  NasMon
//
//  Created by Brian Li on 8/3/26.
//
//  Routes a NAS file to the best preview surface based on its UTI type.
//  Always prefer Apple's recommended UTType conformance checks over
//  hand-maintained extension lists — the router only falls back to a
//  small allowlist for office/archive documents that QuickLook handles
//  well, and to the app's own classification for obscure extensions
//  UTType doesn't register.
//

import Foundation
import UniformTypeIdentifiers

/// The preview surface a file should be routed to.
enum PreviewCategory {
    /// Image formats → custom image viewer (future: zoom/swipe/gallery).
    case image
    /// PDF documents → PDFKit.
    case pdf
    /// Plain-text / code files → dedicated text viewer (Quick Look has no
    /// renderer for many text formats like YAML).
    case text
    /// Video formats → existing fullscreen AVPlayer player.
    case video
    /// Audio formats → existing fullscreen audio player.
    case audio
    /// Office/archive/text/etc. → Quick Look.
    case quickLook
    /// Everything else — no preview surface exists.
    case unsupported
}

/// Whether the surface can render a partial/growing file as bytes arrive
/// (progressive rendering, ADR-0003). QuickLook needs a complete file.
extension PreviewCategory {
    var isProgressive: Bool {
        switch self {
        case .image, .pdf, .text: return true
        case .quickLook, .video, .audio, .unsupported: return false
        }
    }
}

/// Classifies a NAS file into a `PreviewCategory` using `UTType`.
///
/// Classification order:
/// 1. Formats iOS cannot decode (WMA/OGG/MKV/AVI/…) are rejected up front —
///    never route them to the player just to fail after downloading the file.
/// 2. `UTType` conformance (image → pdf → movie/video → audio → text/archive
///    → vCard/calendar)
/// 3. Fallback to the app's existing `DSMFile.previewType` classification
/// 4. A minimal list only for formats that are registered but have no useful
///    conformance (office documents, rar, epub) or aren't registered at all
///    (e.g. `.env`)
enum PreviewRouter {

    /// Determine the best preview surface for a file.
    static func category(for file: DSMFile) -> PreviewCategory {
        guard !file.isdir else { return .unsupported }
        let ext = file.fileExtension

        // AVFoundation has no decoder for these — treat as unsupported so the
        // user gets a clear message instead of a broken/blank player.
        if unplayableMediaExtensions.contains(ext) { return .unsupported }

        // Preferred path: ask the system what kind of UTI this extension is.
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .pdf) { return .pdf }
            // Only check .movie/.video here. .audiovisualContent is a parent of both video and audio;
            // checking it first would misclassify all audio files as video.
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .text)
                || type.conforms(to: .sourceCode)
                || type.conforms(to: .plainText) {
                return .text
            }
            if type.conforms(to: .archive) { return .quickLook }
            if type.conforms(to: .vCard) || type.conforms(to: .calendarEvent) {
                return .quickLook
            }
        }

        // Fallback: UTType may not know the extension — use the app's own
        // curated classification (covers m4v, alac, md, log, dockerfile, etc.).
        switch file.previewType {
        case .image: return .image
        case .pdf: return .pdf
        case .video: return .video
        case .audio: return .audio
        case .text: return .text
        case .other: break
        }

        // Registered but UTType only gives .data with no useful conformance (office docs, rar, epub) — Quick Look handles them well.
        if quickLookFallbackExtensions.contains(ext) { return .quickLook }

        // Text extensions not registered by the system at all (e.g. .env).
        if textishFallbackExtensions.contains(ext) { return .text }

        return .unsupported
    }

    // MARK: - Fallbacks

    /// UTI registered by the system but only conforms to .data (no useful conformance), and Quick Look renders well.
    private static let quickLookFallbackExtensions: Set<String> = [
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key",
        "rar", "epub"
    ]

    /// Media formats iOS can't decode: reject up front to avoid downloading entire files only to fail playback.
    private static let unplayableMediaExtensions: Set<String> = [
        "wma", "ogg", "opus", "avi", "mkv", "webm", "flv", "wmv", "asf"
    ]

    /// Text-like extensions that are genuinely plain text but have no
    /// registered UTI (so `UTType(filenameExtension:)` returns nil).
    private static let textishFallbackExtensions: Set<String> = [
        "env"
    ]
}
