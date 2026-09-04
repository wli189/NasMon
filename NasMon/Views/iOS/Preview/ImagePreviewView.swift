//
//  ImagePreviewView.swift
//  NasMon
//
//  Custom image canvas — deliberately NOT QuickLook. It supports progressive
//  decoding while the file streams and keeps image presentation content-first.
//

import SwiftUI
import UIKit

/// Displays a local image file with progressive decoding and pinch-to-zoom.
/// The surrounding `DocumentPreviewContainer` owns file information, sharing,
/// and the lightweight preview chrome.
enum ImagePreviewZoom {
    static let doubleTapScale: CGFloat = 2
    static let maximumScale: CGFloat = 4

    static func toggledScale(from currentScale: CGFloat) -> CGFloat {
        currentScale > 1 ? 1 : doubleTapScale
    }
}

struct ImagePreviewView: View {
    let url: URL
    /// Streaming progress (0...1); each 5% bucket triggers a re-decode.
    var refreshToken: Double? = nil
    /// Whether the file is fully downloaded.
    var isComplete: Bool = true
    var onUnconsumedTap: () -> Void = {}
    var retry: (() -> Void)? = nil

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Throttles re-decodes to ~20 per download (5% buckets).
    private var progressBucket: Int? {
        guard let refreshToken else { return nil }
        return Int(refreshToken * 20)
    }

    var body: some View {
        ZStack {
            Color.nasMonImmersiveBackground.ignoresSafeArea()

            if let image {
                imageView(image)
            } else if didFail {
                DocumentPreviewStatusView(
                    title: "Cannot Open Image",
                    message: "The completed file is not a supported image.",
                    systemImage: "photo.badge.exclamationmark",
                    retry: retry
                )
            } else {
                DocumentPreviewStatusView(
                    title: "Preparing Image…",
                    message: isComplete ? nil : "Downloading a preview as data arrives.",
                    showsProgress: true,
                    progress: refreshToken
                )
            }
        }
        .task(id: progressBucket) {
            await load()
        }
        .onChange(of: isComplete) { _, done in
            // Finalize the incremental source when the last bytes land.
            // Baseline JPEGs only decode at this point.
            guard done else { return }
            Task { await load() }
        }
    }

    /// (Re-)decode the current file contents off the main thread.
    private func load() async {
        let final = isComplete
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ImagePreviewDecoder.decode(data: data, isFinal: final)
        }.value
        guard !Task.isCancelled else { return }

        if let decoded {
            image = decoded
            didFail = false
        } else if final, image == nil {
            didFail = true
        }
    }

    private func imageView(_ image: UIImage) -> some View {
        GeometryReader { geo in
            let fitScale = min(
                geo.size.width / max(image.size.width, 1),
                geo.size.height / max(image.size.height, 1)
            )

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(
                    width: image.size.width * fitScale,
                    height: image.size.height * fitScale
                )
                .scaleEffect(scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(
                                max(lastScale * value, 1),
                                ImagePreviewZoom.maximumScale
                            )
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                // A double tap is an image action, not an unconsumed tap.
                // Keeping the two tap counts exclusive prevents a double tap
                // from also toggling the preview chrome.
                .gesture(
                    TapGesture(count: 2)
                        .onEnded(toggleZoom)
                        .exclusively(before:
                            TapGesture(count: 1)
                                .onEnded(onUnconsumedTap)
                        )
                )
                .accessibilityLabel("Image preview")
                .accessibilityHint("Tap to show or hide preview controls")
        }
    }

    private func toggleZoom() {
        let nextScale = ImagePreviewZoom.toggledScale(from: scale)
        if reduceMotion {
            scale = nextScale
            lastScale = nextScale
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                scale = nextScale
                lastScale = nextScale
            }
        }
    }
}

#Preview {
    ImagePreviewView(url: PreviewContent.imageURL)
}
