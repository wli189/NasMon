//
//  NasMonTheme.swift
//  NasMon
//
//  Shared visual language for the application. Feature views should use
//  these semantic values instead of defining page-specific colors or sizes.
//

import SwiftUI
import UIKit

// MARK: - Semantic Colors

extension Color {
    /// Brand accent used for primary actions, selected navigation and folders.
    /// The asset catalog is the single source of truth for light and dark values.
    static let nasMonAccent = Color.accentColor

    /// Background for grouped pages such as Dashboard and server selection.
    static let nasMonPageBackground = Color("NasMonPageBackground")

    /// Primary surface for cards and bounded content.
    static let nasMonSurface = Color("NasMonSurface")

    /// Secondary surface for nested content and supporting controls.
    static let nasMonSurfaceSecondary = Color("NasMonSurfaceSecondary")

    static let nasMonOnline = Color("NasMonOnline")

    static let nasMonWarning = Color("NasMonWarning")

    static let nasMonCritical = Color("NasMonCritical")

    /// File type accents used for quick scanning in the native file list.
    static let nasMonFileImage = Color("NasMonFileImage")

    static let nasMonFileVideo = Color("NasMonFileVideo")

    static let nasMonFileAudio = Color("NasMonFileAudio")

    static let nasMonFileText = Color("NasMonFileText")

    /// Default light background for audio playback without album artwork.
    static let nasMonPlayerFallbackBackground = Color("NasMonPlayerFallbackBackground")

    /// System-adaptive canvas used by PDF and text reading surfaces.
    static let nasMonContentBackground = Color(uiColor: .systemBackground)

    /// Used only by fully immersive media surfaces.
    static let nasMonImmersiveBackground = Color.black

}
// MARK: - Layout Tokens

enum NasMonSpacing {
    static let xxSmall: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
    static let xxLarge: CGFloat = 32

    static let pageHorizontal: CGFloat = 16
    static let minimumTapTarget: CGFloat = 44
}

enum NasMonCornerRadius {
    static let control: CGFloat = 10
    static let card: CGFloat = 16
    static let largeCard: CGFloat = 20
}

// MARK: - Typography Tokens

enum NasMonTypography {
    static let pageTitle = Font.title2.weight(.bold)
    static let cardTitle = Font.headline
    static let body = Font.body
    static let supporting = Font.subheadline
    static let metadata = Font.caption
    static let status = Font.caption.weight(.semibold)

    static let metric = Font.system(
        size: 34,
        weight: .semibold,
        design: .rounded
    )

    /// Metric value size for the dedicated two-column Dashboard card.
    static let metricCompact = Font.system(
        size: 28,
        weight: .semibold,
        design: .rounded
    )
}

// MARK: - Shared Shape Style

struct NasMonSurfaceModifier: ViewModifier {
    let fill: Color
    let cornerRadius: CGFloat
    let border: Color?

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(border, lineWidth: 0.5)
                }
            }
    }
}

extension View {
    func nasMonSurface(
        _ fill: Color = .nasMonSurface,
        cornerRadius: CGFloat = NasMonCornerRadius.card,
        border: Color? = nil
    ) -> some View {
        modifier(
            NasMonSurfaceModifier(
                fill: fill,
                cornerRadius: cornerRadius,
                border: border
            )
        )
    }
}
