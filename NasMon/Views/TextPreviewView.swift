//  TextPreviewView.swift
//  NasMon
//
//  SwiftUI state machine for the read-only Runestone document surface. Text
//  files are small, so the surface is only presented once the local file is
//  complete — the route waits for the full download and then opens the file.
//  The source URL remains owned by PreviewViewModel.

import SwiftUI

struct TextPreviewView: View {
    let url: URL
    var onUnconsumedTap: () -> Void = {}
    var retry: (() -> Void)? = nil

    @State private var loadState: LoadState = .loading

    var body: some View {
        content
            .task(id: url) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            DocumentPreviewStatusView(
                title: "Preparing Text…",
                showsProgress: true
            )
        case .ready(let document):
            RunestoneTextPreview(
                document: document,
                onUnconsumedTap: onUnconsumedTap
            )
        case .empty:
            DocumentPreviewStatusView(
                title: "Empty File",
                message: "This text file has no content.",
                systemImage: "doc"
            )
        case .failed:
            DocumentPreviewStatusView(
                title: "Cannot Read File",
                message: "The completed file cannot be decoded as text.",
                systemImage: "doc.plaintext",
                retry: retry
            )
        }
    }

    private func load() async {
        let result = await TextPreviewDocumentLoader.loadResult(url: url)
        guard !Task.isCancelled else { return }

        switch result {
        case .ready(let document):
            loadState = .ready(document)
        case .empty:
            loadState = .empty
        case .unreadable:
            loadState = .failed
        }
    }

    private enum LoadState {
        case loading
        case ready(TextPreviewDocument)
        case empty
        case failed
    }
}

#Preview {
    NavigationStack {
        TextPreviewView(url: PreviewContent.textURL)
    }
}
