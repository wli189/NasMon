//  RunestoneTextPreview.swift
//  NasMon
//
//  UIKit adapter for the third-party Runestone editor. File acquisition and
//  progressive refresh decisions deliberately remain outside this layer.

import Runestone
import SwiftUI
import UIKit

struct RunestoneTextPreview: UIViewRepresentable {
    let document: TextPreviewDocument
    var onUnconsumedTap: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TextPreviewTextView {
        let textView = TextPreviewTextView()
        textView.backgroundColor = .systemBackground
        textView.isEditable = false
        textView.isSelectable = true
        textView.showLineNumbers = true
        textView.isLineWrappingEnabled = true
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.contentInsetAdjustmentBehavior = .automatic
        textView.automaticallyAdjustsScrollIndicatorInsets = true
        textView.preservesSuperviewLayoutMargins = true
        textView.editorDelegate = context.coordinator.readOnlyDelegate
        textView.onUnconsumedTap = onUnconsumedTap
        textView.render(state: document.state)
        context.coordinator.connect(textView: textView)
        return textView
    }

    func updateUIView(_ textView: TextPreviewTextView, context: Context) {
        textView.backgroundColor = .systemBackground
        textView.onUnconsumedTap = onUnconsumedTap
        textView.render(state: document.state)
        context.coordinator.connect(textView: textView)
    }

    static func dismantleUIView(_ textView: TextPreviewTextView, coordinator: Coordinator) {
        coordinator.disconnect()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        fileprivate let readOnlyDelegate = ReadOnlyEditorDelegate()

        private weak var textView: TextPreviewTextView?
        private var tapRecognizer: UITapGestureRecognizer?

        func connect(textView: TextPreviewTextView) {
            self.textView = textView

            if tapRecognizer == nil {
                let recognizer = UITapGestureRecognizer(target: self, action: #selector(didTapSurface))
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                textView.addGestureRecognizer(recognizer)
                tapRecognizer = recognizer
            }
        }

        func disconnect() {
            textView = nil
        }

        @objc private func didTapSurface() {
            textView?.onUnconsumedTap?()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let textView else { return true }
            if textView.isDragging || textView.isDecelerating || textView.isTracking {
                return false
            }
            // An active selection/copy interaction owns the tap. Chrome can be
            // toggled after the user dismisses the selection.
            return textView.selectedRange.length == 0
        }
    }
}

private struct TextReadingAnchor {
    let sourceOffset: Int
    let visualOffset: CGFloat
}

/// Runestone state application must wait until the UIKit view is attached and
/// sized. This subclass also owns source-position preservation across reflow.
final class TextPreviewTextView: TextView {
    var onUnconsumedTap: (() -> Void)?

    private var pendingState: TextViewState?
    private var appliedState: TextViewState?
    private var stateApplicationScheduled = false
    private var hasPositionedInitialContent = false
    private var previousBoundsSize: CGSize = .zero
    private var isRestoringReadingAnchor = false
    private var restorationGeneration = 0

    func render(state: TextViewState) {
        guard appliedState !== state, pendingState !== state else { return }
        pendingState = state
        schedulePendingStateApplication()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        schedulePendingStateApplication()
        applyAdaptiveTheme()
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        updateAdaptiveTextInsets()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        positionInitialContentIfNeeded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        let anchor = captureReadingAnchor()
        super.traitCollectionDidChange(previousTraitCollection)
        applyAdaptiveTheme()
        restoreReadingAnchorAfterLayout(anchor)
    }

    override func layoutSubviews() {
        let sizeChanged = previousBoundsSize != .zero && previousBoundsSize != bounds.size
        let anchor = sizeChanged && !isRestoringReadingAnchor ? captureReadingAnchor() : nil

        updateAdaptiveTextInsets()
        super.layoutSubviews()
        previousBoundsSize = bounds.size
        schedulePendingStateApplication()
        positionInitialContentIfNeeded()
        pinHorizontalOffsetIfNeeded()

        if let anchor {
            restoreReadingAnchorAfterLayout(anchor)
        }
    }

    private func schedulePendingStateApplication() {
        guard pendingState != nil, !stateApplicationScheduled else { return }
        stateApplicationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            stateApplicationScheduled = false
            applyPendingStateIfPossible()
        }
    }

    private func applyPendingStateIfPossible() {
        guard let state = pendingState,
              window != nil,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        pendingState = nil
        guard appliedState !== state else { return }
        let anchor = appliedState == nil ? nil : captureReadingAnchor()
        appliedState = state
        setState(state)
        applyAdaptiveTheme()
        setNeedsLayout()
        layoutIfNeeded()

        if let anchor {
            restoreReadingAnchorAfterLayout(anchor)
        } else {
            positionInitialContentIfNeeded()
        }
    }

    private func updateAdaptiveTextInsets() {
        // `adjustedContentInset` already contributes the navigation-bar and
        // home-indicator clearance to this scroll view. `layoutMargins.top`
        // includes that same safe-area value, so copying it here applies the
        // toolbar clearance twice and leaves a large blank region before line
        // one. Keep only the editor's own typographic padding in the document.
        //
        // Runestone widens the line-number gutter by `safeAreaInsets.left` but
        // starts text at `gutterWidth`. On a notched phone in landscape that
        // leaves the numbers covering the first characters, so shift the text
        // container over by the same amount to keep them clear.
        let desired = UIEdgeInsets(
            top: 8,
            left: 16 + safeAreaInsets.left,
            bottom: 8,
            right: 16
        )
        if textContainerInset != desired {
            textContainerInset = desired
        }
    }

    private func applyAdaptiveTheme() {
        guard appliedState != nil else { return }
        theme = AdaptiveRunestoneTheme(traitCollection: traitCollection)
        redisplayVisibleLines()
    }

    private func positionInitialContentIfNeeded() {
        guard !hasPositionedInitialContent,
              appliedState != nil,
              window != nil,
              bounds.height > 0 else {
            return
        }
        hasPositionedInitialContent = true
        setContentOffset(
            CGPoint(
                x: -adjustedContentInset.left,
                y: -adjustedContentInset.top
            ),
            animated: false
        )
    }

    /// Runestone positions line numbers in a fixed gutter that stretches across
    /// the leading safe-area inset but starts text at `gutterWidth`. After a
    /// landscape rotation the left inset becomes non-zero and the scroll view
    /// keeps its portrait x offset, so the gutter overlaps the first characters.
    /// Line wrapping makes `contentSize.width == bounds.width`, which leaves
    /// exactly one valid horizontal offset; pin it to the adjusted inset.
    private func pinHorizontalOffsetIfNeeded() {
        guard window != nil,
              appliedState != nil,
              bounds.width > 0 else {
            return
        }
        let pinnedX = -adjustedContentInset.left
        if contentOffset.x != pinnedX {
            setContentOffset(
                CGPoint(x: pinnedX, y: contentOffset.y),
                animated: false
            )
        }
    }

    private func captureReadingAnchor() -> TextReadingAnchor? {
        guard appliedState != nil, !text.isEmpty else { return nil }
        let point = CGPoint(
            x: contentOffset.x + adjustedContentInset.left + gutterWidth + textContainerInset.left,
            y: contentOffset.y + adjustedContentInset.top + textContainerInset.top
        )
        guard let position = closestPosition(to: point) else { return nil }
        let sourceOffset = offset(from: beginningOfDocument, to: position)
        guard let range = textRange(from: position, to: position) else { return nil }
        let rect = firstRect(for: range)
        let visualOffset = rect.minY - contentOffset.y - adjustedContentInset.top
        return TextReadingAnchor(sourceOffset: sourceOffset, visualOffset: visualOffset)
    }

    private func restoreReadingAnchorAfterLayout(_ anchor: TextReadingAnchor?) {
        guard let anchor else { return }
        restorationGeneration += 1
        let generation = restorationGeneration
        isRestoringReadingAnchor = true

        DispatchQueue.main.async { [weak self] in
            guard let self, generation == restorationGeneration else { return }
            layoutIfNeeded()
            guard let position = position(from: beginningOfDocument, offset: anchor.sourceOffset),
                  let range = textRange(from: position, to: position) else {
                isRestoringReadingAnchor = false
                return
            }

            let rect = firstRect(for: range)
            let minimumY = -adjustedContentInset.top
            let maximumY = max(
                minimumY,
                contentSize.height - bounds.height + adjustedContentInset.bottom
            )
            let targetY = rect.minY - adjustedContentInset.top - anchor.visualOffset
            // Line wrapping means the preview has no user-controlled horizontal
            // reading position. Restore to the leading edge after reflow so a
            // newly introduced landscape safe area stays behind Runestone's
            // gutter instead of shifting the gutter over the first characters.
            setContentOffset(
                CGPoint(
                    x: -adjustedContentInset.left,
                    y: min(max(targetY, minimumY), maximumY)
                ),
                animated: false
            )
            isRestoringReadingAnchor = false
        }
    }
}

private final class AdaptiveRunestoneTheme: Theme {
    private let base = DefaultTheme()

    let font: UIFont
    let textColor: UIColor
    let gutterBackgroundColor: UIColor
    let gutterHairlineColor: UIColor
    let lineNumberColor: UIColor
    let lineNumberFont: UIFont
    let selectedLineBackgroundColor: UIColor
    let selectedLinesLineNumberColor: UIColor
    let selectedLinesGutterBackgroundColor: UIColor
    let invisibleCharactersColor: UIColor
    let pageGuideHairlineColor: UIColor
    let pageGuideBackgroundColor: UIColor
    let markedTextBackgroundColor: UIColor

    init(traitCollection: UITraitCollection) {
        let bodyFont = UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: traitCollection
        )
        let monospacedDescriptor = bodyFont.fontDescriptor.withDesign(.monospaced)
            ?? bodyFont.fontDescriptor
        let monospacedBodyFont = UIFont(descriptor: monospacedDescriptor, size: 0)

        font = monospacedBodyFont
        lineNumberFont = monospacedBodyFont
        textColor = .label
        gutterBackgroundColor = .secondarySystemBackground
        gutterHairlineColor = .separator
        lineNumberColor = .secondaryLabel
        selectedLineBackgroundColor = .tertiarySystemFill
        selectedLinesLineNumberColor = .label
        selectedLinesGutterBackgroundColor = .secondarySystemBackground
        invisibleCharactersColor = .tertiaryLabel
        pageGuideHairlineColor = .separator
        pageGuideBackgroundColor = .clear
        markedTextBackgroundColor = .tertiarySystemFill
    }

    func textColor(for highlightName: String) -> UIColor? {
        base.textColor(for: highlightName)
    }

    func fontTraits(for highlightName: String) -> FontTraits {
        base.fontTraits(for: highlightName)
    }
}

private final class ReadOnlyEditorDelegate: NSObject, TextViewDelegate {
    func textView(
        _ textView: TextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        false
    }

    func textView(
        _ textView: TextView,
        shouldInsert characterPair: CharacterPair,
        in range: NSRange
    ) -> Bool {
        false
    }
}
