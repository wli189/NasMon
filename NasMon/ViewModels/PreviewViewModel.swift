//  PreviewViewModel.swift
//  NasMon
//
//  Created by Brian Li on 8/3/26.
//
//  View model for the preview system. Mirrors the existing
//  `MediaPlayerViewModel` pattern: owns preview state and delegates the
//  classification to `PreviewRouter` and the streaming orchestration to
//  `PreviewManager`.
//

import Foundation
import Observation

/// View model for previewing a single NAS file.
///
/// Owns the preview state (category, streaming progress, error, local URL)
/// and calls `PreviewManager.preparePreview` to stream a local previewable
/// copy for the preview surfaces (image / pdf / text / quickLook).
/// Progressive surfaces render `streamingURL` as bytes arrive.
@Observable
final class PreviewViewModel {

    // MARK: - Data

    let file: DSMFile

    /// The preview surface this file should be routed to.
    private(set) var category: PreviewCategory?

    /// URL of the cache entry, available as soon as streaming starts so
    /// progressive surfaces can render partial data.
    private(set) var streamingURL: URL?

    /// Local URL of a complete file, ready for display.
    var localFileURL: URL?

    /// Streaming progress (0...1); `nil` when not streaming.
    var progress: Double?

    /// Whether bytes are still arriving.
    var isStreaming = false

    var isLoading = false
    var errorMessage: String?

    // MARK: - Dependencies

    var activeClient: DSMClient?

    private let sessionService = SessionService.shared
    private var previewTask: Task<Void, Never>?

    init(file: DSMFile) {
        self.file = file
    }

    // MARK: - Prepare Preview

    /// Start (or restart) the preview, cancelling any in-flight attempt first.
    func startPreview() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            await self?.preparePreview()
        }
    }

    /// Prepare the file for preview: classify it, consult the cache, and
    /// stream the file into the cache with progress reporting.
    ///
    /// Only `.image`, `.pdf`, `.text`, and `.quickLook` categories go through
    /// this pipeline. `.video`/`.audio` are routed directly to their
    /// dedicated players by the view layer and never reach `preparePreview`.
    func preparePreview() async {
        guard let client = activeClient else { return }
        let category = PreviewRouter.category(for: file)
        self.category = category

        guard category != .unsupported else {
            errorMessage = "This file type cannot be previewed."
            return
        }

        isLoading = true
        errorMessage = nil
        isStreaming = true
        progress = 0
        // The cache URL is known up front — progressive surfaces render it
        // while bytes land.
        streamingURL = PreviewCache.url(for: file, server: activeClient?.cacheScope)
        defer { isLoading = false }

        do {
            let url = try await PreviewManager.preparePreview(file: file, client: client, category: category) { [weak self] received, total in
                guard let self, !Task.isCancelled else { return }
                let fraction: Double? = total.flatMap { $0 > 0 ? Double(received) / Double($0) : nil }
                Task { @MainActor in
                    self.progress = fraction.map { min(max($0, 0), 1) }
                }
            }
            guard !Task.isCancelled else {
                handleCancellation()
                return
            }
            localFileURL = url
            isStreaming = false
            progress = nil
        } catch is CancellationError {
            handleCancellation()
        } catch {
            errorMessage = sessionService.describeError(error)
            isStreaming = false
            progress = nil
        }
    }

    /// Cancel the in-flight preview and discard the partial cache entry
    /// (confirmed cancel semantics: user-cancelled previews are cleaned up).
    func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
        if let url = streamingURL, !isComplete {
            PreviewCache.removePartial(for: file, server: activeClient?.cacheScope)
        }
        isStreaming = false
        progress = nil
    }

    /// Whether the currently streamed entry is complete.
    private var isComplete: Bool {
        localFileURL != nil || PreviewCache.isComplete(for: file, server: activeClient?.cacheScope)
    }

    private func handleCancellation() {
        isStreaming = false
        progress = nil
    }
}
