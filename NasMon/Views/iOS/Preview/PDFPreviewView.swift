//  PDFPreviewView.swift
//  NasMon
//
//  PDFKit-backed document surface. PDFs are opened only once the local file is
//  complete: PDFKit returns nil for truncated documents, so re-opening during
//  streaming would never render a partial page. The route waits for the full
//  download and then presents this view with a finished file.

import PDFKit
import SwiftUI

struct PDFPreviewView: View {
    let url: URL
    var onUnconsumedTap: () -> Void = {}
    var retry: (() -> Void)? = nil

    @State private var document: PDFDocument?
    @State private var didFail = false

    var body: some View {
        Group {
            if let document {
                PDFKitView(
                    document: document,
                    onUnconsumedTap: onUnconsumedTap
                )
            } else if didFail {
                DocumentPreviewStatusView(
                    title: "Cannot Open PDF",
                    message: "The completed file is not a valid PDF document.",
                    systemImage: "doc.richtext",
                    retry: retry
                )
            } else {
                DocumentPreviewStatusView(
                    title: "Preparing PDF…",
                    showsProgress: true
                )
            }
        }
        .task(id: url) {
            await reload()
        }
    }

    private func reload() async {
        let opened = await Task.detached(priority: .userInitiated) {
            PDFDocument(url: url)
        }.value
        guard !Task.isCancelled else { return }

        if let opened {
            document = opened
            didFail = false
        } else {
            didFail = true
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let onUnconsumedTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PreviewPDFView {
        let pdfView = PreviewPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .systemBackground
        pdfView.preservesSuperviewLayoutMargins = true
        pdfView.document = document
        pdfView.onUnconsumedTap = onUnconsumedTap

        context.coordinator.connect(pdfView: pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PreviewPDFView, context: Context) {
        pdfView.onUnconsumedTap = onUnconsumedTap
        context.coordinator.connect(pdfView: pdfView)

        guard pdfView.document !== document else { return }
        // Do not preserve a reading anchor across document swaps. While a file
        // streams, each re-open yields a truncated document whose layout and
        // page count differ from the finished one; an anchor captured from that
        // partial state restores a viewport that doesn't match the final
        // document, leaving the pages mispositioned after the download
        // completes. Fresh documents lay out from the top via `autoScales`.
        // Anchor preservation still applies to *same-document* relayouts
        // (rotation / resize) in `PreviewPDFView.layoutSubviews`.
        pdfView.document = document
    }

    static func dismantleUIView(_ pdfView: PreviewPDFView, coordinator: Coordinator) {
        coordinator.disconnect()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var pdfView: PreviewPDFView?
        private var tapRecognizer: UITapGestureRecognizer?

        func connect(pdfView: PreviewPDFView) {
            self.pdfView = pdfView

            if tapRecognizer == nil {
                let recognizer = UITapGestureRecognizer(target: self, action: #selector(didTapSurface))
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                pdfView.addGestureRecognizer(recognizer)
                tapRecognizer = recognizer
            }

        }

        func disconnect() {
            pdfView = nil
        }

        @objc private func didTapSurface() {
            pdfView?.onUnconsumedTap?()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pdfView,
                  let tapRecognizer = gestureRecognizer as? UITapGestureRecognizer else {
                return true
            }

            if let scrollView = pdfView.descendantScrollView,
               scrollView.isDragging || scrollView.isDecelerating || scrollView.isZooming {
                return false
            }

            let point = tapRecognizer.location(in: pdfView)
            if let page = pdfView.page(for: point, nearest: false) {
                let pagePoint = pdfView.convert(point, to: page)
                if page.annotation(at: pagePoint) != nil {
                    return false
                }
            }
            return true
        }
    }
}

fileprivate struct PDFReadingAnchor {
    let pageIndex: Int
    let pagePoint: CGPoint
    let zoomRatio: CGFloat
}

final class PreviewPDFView: PDFView {
    var onUnconsumedTap: (() -> Void)?

    private var previousBoundsSize: CGSize = .zero
    private var isRestoringAnchor = false
    private var systemPageBreakMargins: UIEdgeInsets?

    var descendantScrollView: UIScrollView? {
        firstDescendant(of: UIScrollView.self, in: self)
    }

    override func layoutSubviews() {
        let changedSize = previousBoundsSize != .zero && previousBoundsSize != bounds.size
        let anchor = changedSize && !isRestoringAnchor ? captureReadingAnchor() : nil

        super.layoutSubviews()
        updateAdaptivePageBreakMargins()
        descendantScrollView?.contentInsetAdjustmentBehavior = .automatic
        descendantScrollView?.automaticallyAdjustsScrollIndicatorInsets = true
        previousBoundsSize = bounds.size

        if let anchor {
            restoreReadingAnchorAfterLayout(anchor)
        }
    }

    private func updateAdaptivePageBreakMargins() {
        // Preserve PDFKit's own vertical page spacing. Navigation chrome
        // changes layoutMargins.top/bottom, and copying those values into
        // pageBreakMargins creates a large safe-area-sized gap between every
        // page. Only the horizontal document gutter should adapt to the view.
        if systemPageBreakMargins == nil {
            systemPageBreakMargins = pageBreakMargins
        }
        guard let systemPageBreakMargins else { return }

        let adaptiveMargins = UIEdgeInsets(
            top: systemPageBreakMargins.top,
            left: layoutMargins.left,
            bottom: systemPageBreakMargins.bottom,
            right: layoutMargins.right
        )
        if pageBreakMargins != adaptiveMargins {
            pageBreakMargins = adaptiveMargins
        }
    }

    fileprivate func captureReadingAnchor() -> PDFReadingAnchor? {
        guard let document,
              let page = page(for: CGPoint(x: bounds.midX, y: bounds.midY), nearest: true) else {
            return nil
        }

        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let pagePoint = convert(center, to: page)
        let fitScale = scaleFactorForSizeToFit
        let zoomRatio = fitScale > 0 ? scaleFactor / fitScale : 1
        return PDFReadingAnchor(pageIndex: pageIndex, pagePoint: pagePoint, zoomRatio: zoomRatio)
    }

    fileprivate func restoreReadingAnchorAfterLayout(_ anchor: PDFReadingAnchor?) {
        guard let anchor else { return }
        isRestoringAnchor = true
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let document,
                  let page = document.page(at: anchor.pageIndex) else {
                self?.isRestoringAnchor = false
                return
            }

            let fitScale = scaleFactorForSizeToFit
            if fitScale > 0 {
                scaleFactor = min(max(fitScale * anchor.zoomRatio, minScaleFactor), maxScaleFactor)
            }
            go(to: PDFDestination(page: page, at: anchor.pagePoint))
            isRestoringAnchor = false
        }
    }

    private func firstDescendant<ViewType: UIView>(
        of type: ViewType.Type,
        in view: UIView
    ) -> ViewType? {
        if let match = view as? ViewType, match !== self { return match }
        for subview in view.subviews {
            if let match = firstDescendant(of: type, in: subview) {
                return match
            }
        }
        return nil
    }
}

#Preview {
    NavigationStack {
        PDFPreviewView(url: PreviewContent.pdfURL)
    }
}
