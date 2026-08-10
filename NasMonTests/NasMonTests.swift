//
//  NasMonTests.swift
//  NasMonTests
//
//  Created by Brian Li on 7/30/26.
//

import Foundation
import PDFKit
import Runestone
import SwiftUI
import Testing
import UIKit
@testable import NasMon

@Suite(.serialized)
struct NasMonTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    /// The refactor must keep the existing file-loading seam: the preview
    /// reads the local URL prepared by PreviewManager and builds Runestone's
    /// editor state from those bytes.
    @Test @MainActor func textPreviewLoadsRunestoneDocumentFromLocalURL() async throws {
        let text = "struct PreviewFixture {\n    let value = 42\n}\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try Data(text.utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await TextPreviewDocumentLoader.loadResult(url: url)
        let document = try #require(result.readyDocument)
        let textView = TextView()
        textView.setState(document.state)

        #expect(textView.text == text)
    }

    /// Regression test for #16: SwiftUI can supply the Runestone state before
    /// the representable has joined a window or received its final bounds.
    /// The preview must apply that pending state during the first sized layout,
    /// rather than waiting for a scroll gesture to provoke another pass.
    @Test @MainActor func textPreviewRendersOnFirstSizedLayout() async {
        let text = (1...80).map { "Line \($0)" }.joined(separator: "\n")
        let state = TextViewState(text: text, theme: DefaultTheme())
        let textView = TextPreviewTextView(frame: .zero)

        textView.render(state: state)
        #expect(textView.text.isEmpty)

        let viewController = UIViewController()
        viewController.view.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
        ])

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.layoutIfNeeded()

        // Let the deferred state application run without manually forcing a
        // second TextView layout. This models SwiftUI's first presentation
        // and catches the blank-until-scroll regression.
        for _ in 0..<3 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }

        #expect(textView.text == text)
        #expect(textView.contentInset.top == 0)
        #expect(textView.contentSize.height > textView.bounds.height)
        #expect(hasRenderedLineFragment(in: textView))

        window.isHidden = true
    }

    @MainActor
    private func hasRenderedLineFragment(in view: UIView) -> Bool {
        let typeName = String(describing: type(of: view))
        if typeName == "LineFragmentView", !view.isHidden, view.bounds.width > 0, view.bounds.height > 0 {
            return true
        }
        return view.subviews.contains { hasRenderedLineFragment(in: $0) }
    }

    /// Short text cannot be pulled down to reveal a first line hidden behind
    /// the navigation bar, so its initial rendered position must already be
    /// below the toolbar in the real shared preview container. Both compact
    /// portrait and landscape layouts derive their clearance from UIKit.
    @Test @MainActor func shortTextPreviewStartsBelowNavigationBar() async throws {
        for size in [
            CGSize(width: 390, height: 844),
            CGSize(width: 844, height: 390)
        ] {
            try await assertShortTextPreviewStartsBelowNavigationBar(windowSize: size)
        }
    }

    /// Regression test: in landscape the Runestone gutter must reserve its
    /// horizontal space. Its visible line numbers must never cover source text.
    @Test @MainActor func landscapeTextPreviewLineNumbersDoNotOverlapSource() async throws {
        let text = #"{"command":"pid","pid":0,"state":0}"#
        let state = TextViewState(text: text, theme: DefaultTheme())
        let preview = NavigationStack {
            DocumentPreviewContainer(
                filename: "status.json",
                isStreaming: false,
                progress: nil,
                completedURL: URL(fileURLWithPath: "/tmp/status.json")
            ) { context in
                RunestoneTextPreview(
                    document: TextPreviewDocument(text: text, state: state),
                    onUnconsumedTap: context.toggleChrome
                )
            }
        }
        let hostingController = UIHostingController(rootView: preview)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.isHidden = false
        defer { window.isHidden = true }

        let textView = try await waitForRenderedTextView(
            hostingController: hostingController,
            window: window
        )

        // The reported defect occurs after rotating an already-rendered preview.
        // Exercise the same reflow path rather than only creating a landscape view.
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        // A notched phone's landscape leading safe area is the condition that
        // previously made the gutter cover the first source characters.
        hostingController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 59,
            bottom: 0,
            right: 0
        )
        for _ in 0..<3 {
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        let lineNumbers = lineNumberViews(in: textView)
        #expect(!lineNumbers.isEmpty)

        let sourceFrames = renderedLineFragments(in: textView).map {
            $0.convert($0.bounds, to: window)
        }
        let lineNumberFrames = lineNumbers.map { $0.convert($0.bounds, to: window) }
        #expect(textView.contentOffset.x == -textView.adjustedContentInset.left)
        #expect(lineNumberFrames.allSatisfy { lineNumberFrame in
            sourceFrames.allSatisfy { !lineNumberFrame.intersects($0) }
        })
    }

    @MainActor
    private func assertShortTextPreviewStartsBelowNavigationBar(
        windowSize: CGSize
    ) async throws {
        let text = "First line\nSecond line\n"
        let state = TextViewState(text: text, theme: DefaultTheme())
        let preview = NavigationStack {
            DocumentPreviewContainer(
                filename: "short.txt",
                isStreaming: false,
                progress: nil,
                completedURL: URL(fileURLWithPath: "/tmp/short.txt")
            ) { context in
                RunestoneTextPreview(
                    document: TextPreviewDocument(text: text, state: state),
                    onUnconsumedTap: context.toggleChrome
                )
            }
        }
        let hostingController = UIHostingController(rootView: preview)
        let window = UIWindow(frame: CGRect(origin: .zero, size: windowSize))
        window.rootViewController = hostingController
        window.isHidden = false
        defer { window.isHidden = true }

        let textView = try await waitForRenderedTextView(
            hostingController: hostingController,
            window: window
        )
        let navigationBar = try #require(firstSubview(of: UINavigationBar.self, in: window))
        let firstLine = try #require(renderedLineFragments(in: textView).min {
            $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
        })

        let navigationBarBottom = navigationBar.convert(navigationBar.bounds, to: window).maxY
        let textViewTop = textView.convert(textView.bounds, to: window).minY
        let firstLineTop = firstLine.convert(firstLine.bounds, to: window).minY
        #expect(textViewTop < navigationBarBottom)
        #expect(firstLineTop >= navigationBarBottom)
        #expect(firstLineTop - navigationBarBottom < textView.bounds.height * 0.1)
        #expect(textView.adjustedContentInset.top > 0)
        #expect(textView.contentInset == .zero)
        #expect(textView.contentOffset.y == -textView.adjustedContentInset.top)
        #expect(textView.textContainerInset.top == textView.textContainerInset.bottom)
        #expect(textView.textContainerInset.left == textView.textContainerInset.right)
        #expect(textView.textContainerInset.top < textView.adjustedContentInset.top)
    }

    /// The toolbar clearance belongs to Runestone's UIScrollView so that it
    /// disappears together with the first line when a long document scrolls.
    @Test @MainActor func textPreviewTopBoundaryScrollsWithLongText() async throws {
        let text = (1...200).map { "Line \($0)" }.joined(separator: "\n")
        let state = TextViewState(text: text, theme: DefaultTheme())
        let preview = NavigationStack {
            DocumentPreviewContainer(
                filename: "long.txt",
                isStreaming: false,
                progress: nil,
                completedURL: URL(fileURLWithPath: "/tmp/long.txt")
            ) { context in
                RunestoneTextPreview(
                    document: TextPreviewDocument(text: text, state: state),
                    onUnconsumedTap: context.toggleChrome
                )
            }
        }
        let hostingController = UIHostingController(rootView: preview)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.isHidden = false
        defer { window.isHidden = true }

        let textView = try await waitForRenderedTextView(
            hostingController: hostingController,
            window: window
        )
        let initialOffsetY = textView.contentOffset.y
        #expect(initialOffsetY == -textView.adjustedContentInset.top)

        textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: 0), animated: false)
        textView.layoutIfNeeded()

        #expect(textView.contentOffset.y == 0)
        #expect(textView.contentOffset.y - initialOffsetY == textView.adjustedContentInset.top)
    }

    @Test @MainActor func pdfPreviewUsesContinuousAdaptiveScrollSurface() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 612, height: 792)
        )
        let data = renderer.pdfData { context in
            context.beginPage()
            "Preview".draw(at: CGPoint(x: 72, y: 72), withAttributes: nil)
        }
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = NavigationStack {
            DocumentPreviewContainer(
                filename: url.lastPathComponent,
                isStreaming: false,
                progress: nil,
                completedURL: url
            ) { context in
                PDFPreviewView(
                    url: url,
                    onUnconsumedTap: context.toggleChrome
                )
            }
        }
        let hostingController = UIHostingController(rootView: preview)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.isHidden = false
        defer { window.isHidden = true }

        var loadedPDFView: PDFView?
        for _ in 0..<100 {
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            if let pdfView = firstSubview(of: PDFView.self, in: window),
               pdfView.document?.pageCount == 1 {
                loadedPDFView = pdfView
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let pdfView = try #require(loadedPDFView)
        let scrollView = try #require(firstSubview(of: UIScrollView.self, in: pdfView))
        #expect(pdfView.displayMode == .singlePageContinuous)
        #expect(pdfView.displayDirection == .vertical)
        #expect(pdfView.displaysPageBreaks)
        #expect(scrollView.contentInsetAdjustmentBehavior == .automatic)
        #expect(scrollView.automaticallyAdjustsScrollIndicatorInsets)
    }

    /// Safe-area changes from the navigation chrome may influence
    /// horizontal page margins, but must never become vertical gaps between
    /// every pair of PDF pages.
    @Test @MainActor func pdfPageBreakMarginsKeepSystemVerticalSpacing() {
        let pdfView = PreviewPDFView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let systemMargins = pdfView.pageBreakMargins
        pdfView.layoutMargins = UIEdgeInsets(top: 180, left: 24, bottom: 120, right: 24)
        pdfView.setNeedsLayout()
        pdfView.layoutIfNeeded()

        #expect(pdfView.pageBreakMargins.top == systemMargins.top)
        #expect(pdfView.pageBreakMargins.bottom == systemMargins.bottom)
        #expect(pdfView.pageBreakMargins.left == pdfView.layoutMargins.left)
        #expect(pdfView.pageBreakMargins.right == pdfView.layoutMargins.right)
    }

    @MainActor
    private func waitForRenderedTextView(
        hostingController: UIViewController,
        window: UIWindow
    ) async throws -> TextPreviewTextView {
        for _ in 0..<100 {
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            if let textView = firstSubview(of: TextPreviewTextView.self, in: window),
               !renderedLineFragments(in: textView).isEmpty {
                return textView
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Text preview did not render in time")
        throw CancellationError()
    }

    @MainActor
    private func firstSubview<ViewType: UIView>(
        of type: ViewType.Type,
        in view: UIView
    ) -> ViewType? {
        if let match = view as? ViewType { return match }
        return view.subviews.lazy.compactMap { firstSubview(of: type, in: $0) }.first
    }

    @MainActor
    private func lineNumberViews(in view: UIView) -> [UIView] {
        var matches: [UIView] = []
        if String(describing: type(of: view)) == "LineNumberView",
           !view.isHidden,
           view.bounds.width > 0,
           view.bounds.height > 0 {
            matches.append(view)
        }
        for subview in view.subviews {
            matches.append(contentsOf: lineNumberViews(in: subview))
        }
        return matches
    }

    @MainActor
    private func renderedLineFragments(in view: UIView) -> [UIView] {
        var matches: [UIView] = []
        let typeName = String(describing: type(of: view))
        if typeName == "LineFragmentView", !view.isHidden, view.bounds.width > 0, view.bounds.height > 0 {
            matches.append(view)
        }
        for subview in view.subviews {
            matches.append(contentsOf: renderedLineFragments(in: subview))
        }
        return matches
    }

    /// Regression test for #12: uninstalling the app wipes UserDefaults (the
    /// saved server list) but Keychain entries survive, so a reinstall must
    /// detect the fresh install (empty server list) and clear the leftover
    /// credentials instead of silently auto-logging-in.
    @Test func freshInstallWithEmptyServerListClearsLeftoverKeychain() {
        let keychain = KeychainHelper.shared

        // Simulate a previous install's leftovers: server list (UserDefaults)
        // is gone, but Keychain still holds the global session, host/port
        // pointers, and a per-server password.
        UserDefaults.standard.removeObject(forKey: "saved_servers")
        keychain.save(string: "leftover-sid", key: "dsm_session_sid")
        keychain.save(string: "leftover-token", key: "dsm_session_synotoken")
        keychain.save(string: "192.168.1.10", key: "dsm_host")
        keychain.save(string: "5001", key: "dsm_port")
        keychain.save(string: "secret", key: "password_192.168.1.10_5001")

        // Without the fix, restoreSession() would return a client (auto-login).
        // With the fix, the empty server list triggers a Keychain wipe.
        let client = SessionService.shared.restoreSession()

        #expect(client == nil)
        #expect(keychain.loadString(key: "dsm_host") == nil)
        #expect(keychain.loadString(key: "dsm_port") == nil)
        #expect(keychain.loadString(key: "dsm_session_sid") == nil)
        #expect(keychain.loadString(key: "dsm_session_synotoken") == nil)
        #expect(keychain.loadString(key: "password_192.168.1.10_5001") == nil)
    }

    /// Sanity check for #12: a normal launch with a non-empty server list must
    /// NOT wipe saved credentials (the fresh-install guard is off).
    @Test func nonEmptyServerListKeepsKeychainIntact() {
        let keychain = KeychainHelper.shared

        // Seed a server list so the fresh-install guard does not trigger.
        let server = SavedServer(host: "192.168.1.10", port: 5001, name: "NAS")
        ServerStore.shared.saveServers([server])
        keychain.save(string: "keep-me", key: "dsm_session_sid")
        keychain.save(string: "192.168.1.10", key: "dsm_host")

        _ = SessionService.shared.restoreSession()

        #expect(keychain.loadString(key: "dsm_session_sid") == "keep-me")
        #expect(keychain.loadString(key: "dsm_host") == "192.168.1.10")

        // Restore clean state.
        UserDefaults.standard.removeObject(forKey: "saved_servers")
        keychain.deleteAll()
    }

}
