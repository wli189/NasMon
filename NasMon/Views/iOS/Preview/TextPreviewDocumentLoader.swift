//  TextPreviewDocumentLoader.swift
//  NasMon
//
//  Builds Runestone state from the local file written by PreviewManager.
//  This type deliberately does not download, cache, or own a file URL.
//

import Foundation
import Runestone
import TreeSitterBashRunestone
import TreeSitterCRunestone
import TreeSitterCPPRunestone
import TreeSitterCSSRunestone
import TreeSitterGoRunestone
import TreeSitterHTMLRunestone
import TreeSitterJavaRunestone
import TreeSitterJavaScriptRunestone
import TreeSitterJSONRunestone
import TreeSitterMarkdownRunestone
import TreeSitterPHPRunestone
import TreeSitterPythonRunestone
import TreeSitterRubyRunestone
import TreeSitterSQLRunestone
import TreeSitterSwiftRunestone
import TreeSitterTypeScriptRunestone
import TreeSitterYAMLRunestone

/// Package-neutral value passed between the SwiftUI preview and the Runestone
/// adapter. The third-party editor state stays inside this implementation seam.
struct TextPreviewDocument {
    let text: String
    let state: TextViewState
}

enum TextPreviewLoadResult {
    case ready(TextPreviewDocument)
    case empty
    case unreadable

    /// The loaded document when this result is `.ready`; `nil` otherwise.
    var readyDocument: TextPreviewDocument? {
        if case .ready(let document) = self { return document }
        return nil
    }
}

enum TextPreviewDocumentLoader {
    /// Reads the existing local preview URL. It never downloads or replaces the
    /// file, and reports empty content separately from decoding failure.
    nonisolated static func loadResult(
        url: URL
    ) async -> TextPreviewLoadResult {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else {
                return .unreadable
            }
            guard !data.isEmpty else {
                return .empty
            }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return .unreadable
            }

            let theme = DefaultTheme()
            if let language = language(for: url.pathExtension) {
                return .ready(
                    TextPreviewDocument(
                        text: text,
                        state: TextViewState(text: text, theme: theme, language: language)
                    )
                )
            }
            return .ready(
                TextPreviewDocument(
                    text: text,
                    state: TextViewState(text: text, theme: theme)
                )
            )
        }.value
    }

    /// Maps a file extension to a Runestone tree-sitter language. Unknown
    /// extensions intentionally fall back to plain text.
    private nonisolated static func language(for fileExtension: String) -> TreeSitterLanguage? {
        switch fileExtension.lowercased() {
        case "swift": return .swift
        case "py": return .python
        case "js", "mjs", "cjs": return .javaScript
        case "ts", "tsx": return .typeScript
        case "json": return .json
        case "yml", "yaml": return .yaml
        case "html", "htm", "xml", "svg": return .html
        case "css": return .css
        case "sh", "bash", "zsh": return .bash
        case "c": return .c
        case "cpp", "cc", "cxx", "h", "hpp", "hxx": return .cpp
        case "java": return .java
        case "go": return .go
        case "rb": return .ruby
        case "php": return .php
        case "sql": return .sql
        case "md", "markdown": return .markdown
        default: return nil
        }
    }
}
