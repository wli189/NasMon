//
//  DocumentPreviewContainer.swift
//  NasMon
//
//  Shared content-first chrome for image, PDF, and text previews. This layer
//  owns presentation state only; file acquisition remains in PreviewViewModel.
//

import SwiftUI

/// The canvas treatment appropriate for a preview's content type.
enum PreviewPresentationStyle: Equatable {
    /// Images retain a neutral black canvas so the asset, not the app chrome,
    /// determines the visual focus.
    case image
    /// PDF and text use the system content background for reading comfort.
    case document

    var canvasColor: Color {
        switch self {
        case .image:
            .nasMonImmersiveBackground
        case .document:
            .nasMonContentBackground
        }
    }

    var chromeBackground: Color {
        switch self {
        case .image:
            .nasMonImmersiveBackground
        case .document:
            .nasMonContentBackground
        }
    }

    var toolbarColorScheme: ColorScheme? {
        switch self {
        case .image:
            .dark
        case .document:
            nil
        }
    }

    /// Document readers keep their navigation chrome fixed so content can
    /// scroll beneath it without a tap changing the reading viewport.
    var allowsChromeHiding: Bool {
        self == .image
    }

    /// Preview content remains visible beneath the toolbar while the chrome
    /// stays edge-to-edge. This matches the PDF and text treatment.
    var usesTransparentChromeBackground: Bool {
        true
    }
}

struct DocumentPreviewSurfaceContext {
    let toggleChrome: () -> Void
}

/// Shared, minimal navigation chrome around content-first preview surfaces.
///
/// Image chrome may be toggled without replacing its child surface. PDF and
/// text readers keep the chrome visible while their content scrolls beneath it.
struct DocumentPreviewContainer<Content: View>: View {
    let filename: String
    var style: PreviewPresentationStyle = .document
    let isStreaming: Bool
    let progress: Double?
    let completedURL: URL?
    var onDismiss: () -> Void = {}
    @ViewBuilder let content: (DocumentPreviewSurfaceContext) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isChromeVisible = true

    var body: some View {
        content(
            DocumentPreviewSurfaceContext(
                toggleChrome: toggleChrome
            )
        )
        // UIKit-backed readers own their scrolling safe-area behavior. Keeping
        // the surface edge-to-edge lets navigation chrome appear and disappear
        // without changing the content's own coordinate system.
        .ignoresSafeArea()
        .background(style.canvasColor.ignoresSafeArea())
        .preferredColorScheme(style.toolbarColorScheme)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(toolbarBackgroundVisibility, for: .navigationBar)
        .toolbarBackground(style.chromeBackground, for: .navigationBar)
        .toolbarColorScheme(style.toolbarColorScheme, for: .navigationBar)
        .toolbar {
            if isChromeVisible {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Label("Close", systemImage: "xmark")
                    }
                    .accessibilityLabel("Close preview")
                }

                ToolbarItem(placement: .principal) {
                    titleView
                }

                ToolbarItem(placement: .topBarTrailing) {
                    shareControl
                }
            }
        }
    }

    private var titleView: some View {
        Text(filename)
            .font(NasMonTypography.supporting.weight(.semibold))
            .lineLimit(1)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var shareControl: some View {
        if let completedURL {
            ShareLink(item: completedURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share \(filename)")
        } else {
            Button(action: {}) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(true)
            .accessibilityLabel("Share unavailable while downloading")
        }
    }

    private var toolbarBackgroundVisibility: Visibility {
        if style.usesTransparentChromeBackground {
            return .hidden
        }
        return isChromeVisible ? .visible : .hidden
    }

    private func toggleChrome() {
        guard style.allowsChromeHiding else { return }
        setChromeVisible(!isChromeVisible)
    }

    private func setChromeVisible(_ visible: Bool) {
        if reduceMotion {
            isChromeVisible = visible
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isChromeVisible = visible
            }
        }
    }
}

/// Clear loading, empty, and recoverable-error feedback for a preview canvas.
/// Chrome remains visible because these states do not forward tap-to-hide
/// events to the shared container.
struct DocumentPreviewStatusView: View {
    let title: String
    var message: String?
    var systemImage: String?
    var showsProgress = false
    /// Download progress (0...1). When non-nil, `showsProgress` renders a
    /// determinate horizontal progress bar.
    var progress: Double? = nil
    var receivedBytes: Int64? = nil
    var totalBytes: Int64? = nil
    var retry: (() -> Void)?

    var body: some View {
        Group {
            if showsProgress {
                VStack(spacing: NasMonSpacing.medium) {
                    Text(title)
                        .font(NasMonTypography.supporting)
                        .foregroundStyle(.secondary)

                    if let totalBytes, totalBytes > 0 {
                        Text("\(formattedBytes(receivedBytes ?? 0)) / \(formattedBytes(totalBytes))")
                            .font(NasMonTypography.metadata)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(formattedBytes(receivedBytes ?? 0)) downloaded of \(formattedBytes(totalBytes))")
                    }

                    if let progress {
                        ProgressView(value: min(max(progress, 0), 1))
                            .tint(.nasMonAccent)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.nasMonAccent)
                    }

                    if let message {
                        Text(message)
                            .font(NasMonTypography.metadata)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                ContentUnavailableView {
                    if let systemImage {
                        Label(title, systemImage: systemImage)
                    } else {
                        Text(title)
                    }
                } description: {
                    if let message {
                        Text(message)
                    }
                } actions: {
                    if let retry {
                        Button("Retry", action: retry)
                            .buttonStyle(.borderedProminent)
                            .tint(.nasMonAccent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(NasMonSpacing.xLarge)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview("Real Preview Transfer — 42%") {
    NavigationStack {
        DocumentPreviewContainer(
            filename: "sample.yaml",
            style: .document,
            isStreaming: true,
            progress: 0.42,
            completedURL: nil,
            onDismiss: {}
        ) { context in
            DocumentPreviewStatusView(
                title: "Preparing Text…",
                showsProgress: true,
                progress: 0.42
            )
        }
    }
}

#Preview("Real Preview Transfer — Indeterminate") {
    NavigationStack {
        DocumentPreviewContainer(
            filename: "sample.yaml",
            style: .document,
            isStreaming: true,
            progress: nil,
            completedURL: nil,
            onDismiss: {}
        ) { context in
            DocumentPreviewStatusView(
                title: "Preparing Text…",
                showsProgress: true
            )
        }
    }
}
