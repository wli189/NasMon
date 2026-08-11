//
//  NasMonGlass.swift
//  NasMon
//
//  Compatibility wrappers for the iOS 26 glass APIs used by the player UI.
//  iOS 18 gets a material/bordered fallback instead of failing to compile.
//

import SwiftUI

/// Groups glass controls on iOS 26 and keeps the same layout on older systems.
///
/// `GlassEffectContainer` is an iOS 26 API, so it must not appear directly in
/// an iOS 18 view hierarchy without an availability check.
struct NasMonGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: () -> Content

    init(spacing: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    /// Uses the iOS 26 glass button style when available and a bordered button
    /// style on iOS 18, preserving the control's affordance and contrast.
    @ViewBuilder
    func nasMonGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Transparent fallback for immersive player controls. The bordered
    /// fallback is appropriate for normal actions such as Retry, but it adds
    /// a visible fill behind transport controls on iOS 18.
    @ViewBuilder
    func nasMonPlayerButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.plain)
        }
    }
}
