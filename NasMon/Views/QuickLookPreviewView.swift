//
//  QuickLookPreviewView.swift
//  NasMon
//
//  Created by Brian Li on 8/3/26.
//
//  SwiftUI bridge to Apple's native QLPreviewController (QuickLook).
//  UIViewControllerRepresentable is required because QLPreviewController is
//  a UIKit view controller — SwiftUI has no native equivalent.
//

import SwiftUI
import QuickLook

/// A SwiftUI wrapper around `QLPreviewController` for previewing a local file.
///
/// `QLPreviewController` is a UIKit view controller, so `UIViewControllerRepresentable`
/// is the standard bridge that lets SwiftUI host it inside the existing
/// `NavigationStack`. It presents the file at `url` using QuickLook's native
/// preview UI (images, PDFs, text, office docs, archives, etc.).
struct QuickLookPreviewView: UIViewControllerRepresentable {
    /// Local URL of the file to preview.
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // The URL is fixed for the lifetime of this view; nothing to update.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    /// Supplies the preview item to `QLPreviewController`.
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}