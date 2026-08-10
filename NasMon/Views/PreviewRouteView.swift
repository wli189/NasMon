//  PreviewRouteView.swift
//  NasMon
//
//  Destination for previewing a NAS file. File acquisition remains in
//  PreviewViewModel; this view only routes the resulting local URL to the
//  appropriate preview surface. All preview categories are presented from a
//  full-screen cover owned by FileManagerView.

import SwiftUI

struct PreviewRouteView: View {
    let file: DSMFile
    var client: DSMClient?

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PreviewViewModel

    init(file: DSMFile, client: DSMClient?) {
        self.file = file
        self.client = client
        _viewModel = State(initialValue: PreviewViewModel(file: file))
    }

    var body: some View {
        content
            // Image, PDF, and text previews supply their own lightweight,
            // content-first chrome. Quick Look retains its native title bar.
            .navigationTitle(usesStandaloneNavigationChrome ? file.name : "")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(usesStandaloneNavigationChrome)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                if usesStandaloneNavigationChrome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Label("Close", systemImage: "xmark")
                        }
                        .accessibilityLabel("Close preview")
                    }
                }
            }
            .task {
                viewModel.activeClient = client
                viewModel.startPreview()
            }
            .onDisappear {
                viewModel.cancelPreview()
            }
    }

    /// Quick Look owns the content surface but not NasMon's shared preview
    /// chrome, so the full-screen route supplies the close action itself.
    private var usesStandaloneNavigationChrome: Bool {
        if case .quickLook = PreviewRouter.category(for: file) {
            return true
        }
        return false
    }

    // MARK: - Routing

    @ViewBuilder
    private var content: some View {
        if let category = viewModel.category {
            switch category {
            case .image, .pdf, .text:
                contentPreview(category: category)
            default:
                legacyPreview(category: category)
            }
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else {
            loadingView
        }
    }

    /// Images, PDFs, and text files use the same restrained Preview Chrome
    /// while retaining their content-specific canvas and reading behavior.
    private func contentPreview(category: PreviewCategory) -> some View {
        DocumentPreviewContainer(
            filename: file.name,
            style: previewStyle(for: category),
            isStreaming: viewModel.isStreaming,
            progress: viewModel.progress,
            completedURL: viewModel.localFileURL,
            onDismiss: { dismiss() }
        ) { context in
            contentSurface(category: category, context: context)
        }
    }

    private func previewStyle(for category: PreviewCategory) -> PreviewPresentationStyle {
        if case .image = category {
            return .image
        }
        return .document
    }

    @ViewBuilder
    private func contentSurface(
        category: PreviewCategory,
        context: DocumentPreviewSurfaceContext
    ) -> some View {
        if let error = viewModel.errorMessage, viewModel.localFileURL == nil {
            DocumentPreviewStatusView(
                title: "Preview Unavailable",
                message: error,
                systemImage: "eye.slash",
                retry: viewModel.startPreview
            )
        } else if let url = viewModel.localFileURL ?? viewModel.streamingURL {
            switch category {
            case .image:
                ImagePreviewView(
                    url: url,
                    refreshToken: viewModel.progress,
                    isComplete: viewModel.localFileURL != nil,
                    onUnconsumedTap: context.toggleChrome,
                    retry: viewModel.startPreview
                )
            case .pdf:
                // PDFKit returns nil for truncated documents, so the PDF
                // surface can only open a complete file. Never hand it the
                // streaming (partial) URL — wait for the download, then present
                // the reading surface once with the finished file.
                if let url = viewModel.localFileURL {
                    PDFPreviewView(
                        url: url,
                        onUnconsumedTap: context.toggleChrome,
                        retry: viewModel.startPreview
                    )
                } else {
                    DocumentPreviewStatusView(
                        title: "Preparing PDF…",
                        showsProgress: true,
                        progress: viewModel.progress
                    )
                }
            case .text:
                // Text previews open the finished file only. Small text files
                // download in a moment; re-opening a partial file to show
                // progressive content buys nothing (see the PDF comment above).
                if let url = viewModel.localFileURL {
                    TextPreviewView(
                        url: url,
                        onUnconsumedTap: context.toggleChrome,
                        retry: viewModel.startPreview
                    )
                } else {
                    DocumentPreviewStatusView(
                        title: "Preparing Text…",
                        showsProgress: true,
                        progress: viewModel.progress
                    )
                }
            default:
                EmptyView()
            }
        } else {
            DocumentPreviewStatusView(
                title: "Preparing Preview…",
                showsProgress: true
            )
        }
    }

    @ViewBuilder
    private func legacyPreview(category: PreviewCategory) -> some View {
        if let url = viewModel.localFileURL {
            applySafeArea(previewSurface(for: category, url: url))
        } else if let url = viewModel.streamingURL, category.isProgressive {
            applySafeArea(progressiveSurface(for: category, url: url))
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else {
            loadingView
        }
    }

    // MARK: - Non-document surfaces

    @ViewBuilder
    private func progressiveSurface(for category: PreviewCategory, url: URL) -> some View {
        switch category {
        case .image:
            // Image files are routed through `contentPreview`; retain a clear
            // fallback in case a future router marks an image as legacy.
            ImagePreviewView(
                url: url,
                refreshToken: viewModel.progress,
                isComplete: !viewModel.isStreaming
            )
        default:
            loadingView
        }
    }

    @ViewBuilder
    private func previewSurface(for category: PreviewCategory, url: URL) -> some View {
        switch category {
        case .quickLook:
            QuickLookPreviewView(url: url)
        case .image:
            ImagePreviewView(url: url)
        case .pdf, .text, .video, .audio:
            EmptyView()
        case .unsupported:
            ContentUnavailableView(
                "Preview Unavailable",
                systemImage: "eye.slash",
                description: Text("This file type cannot be previewed.")
            )
        }
    }

    private var loadingView: some View {
        DocumentPreviewStatusView(
            title: "Preparing Preview…",
            showsProgress: true
        )
    }

    private func errorView(_ error: String) -> some View {
        DocumentPreviewStatusView(
            title: "Preview Unavailable",
            message: error,
            systemImage: "eye.slash",
            retry: viewModel.startPreview
        )
    }

    private func applySafeArea<Content: View>(_ content: Content) -> some View {
        content.ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        PreviewRouteView(
            file: PreviewContent.seedImagePreviewFile(),
            client: DSMClient(host: "192.168.1.10")
        )
    }
}
