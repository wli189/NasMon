//
//  PreviewContent.swift
//  NasMon
//
//  Bundled sample files used by SwiftUI `#Preview` surfaces. Xcode's
//  synchronized folder (`PBXFileSystemSynchronizedRootGroup`) copies the
//  `PreviewContent/` directory into the app bundle root, so these helpers
//  resolve real files that each preview surface can render.
//
//  Only referenced from `#Preview` blocks; never shipped logic.
//

import Foundation

enum PreviewContent {
    /// URL of a bundled sample file by base name (e.g. "sample.yaml").
    static func url(_ name: String) -> URL {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        return Bundle.main.url(forResource: base, withExtension: ext)
            ?? Bundle.main.bundleURL.appendingPathComponent(name)
    }

    /// Image preview sample.
    static var imageURL: URL { url("sample.jpg") }
    /// PDF preview sample.
    static var pdfURL: URL { url("sample.pdf") }
    /// Text preview sample.
    static var textURL: URL { url("sample.yaml") }

    /// A `DSMFile` whose preview-cache entry is seeded with the bundled image,
    /// so `PreviewRouteView` renders through its cache-hit path without network.
    static func seedImagePreviewFile() -> DSMFile {
        let file = DSMFile(
            path: "/home/sample.jpg",
            name: "sample.jpg",
            isdir: false,
            additional: DSMFileAdditional(
                size: nil, type: "jpg", mtime: nil, atime: nil,
                ctime: nil, crtime: nil, owner: nil, time: nil, perm: nil,
                mountPointType: nil, realPath: nil, volumeStatus: nil
            )
        )
        let cacheURL = PreviewCache.url(for: file, server: nil)
        if !PreviewCache.isComplete(for: file, server: nil) {
            try? FileManager.default.removeItem(at: cacheURL)
            try? FileManager.default.copyItem(at: imageURL, to: cacheURL)
            PreviewCache.markComplete(for: file, server: nil)
        }
        return file
    }
}
