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
    static let nasMonAccent = Color.nasMonDynamic(
        light: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        dark: UIColor(red: 0.25, green: 0.612, blue: 1.0, alpha: 1.0)
    )

    /// Background for grouped pages such as Dashboard and server selection.
    static let nasMonPageBackground = Color.nasMonDynamic(
        light: UIColor(red: 0.949, green: 0.957, blue: 0.973, alpha: 1.0),
        dark: UIColor(red: 0.031, green: 0.051, blue: 0.086, alpha: 1.0)
    )

    /// Primary surface for cards and bounded content.
    static let nasMonSurface = Color.nasMonDynamic(
        light: .white,
        dark: UIColor(red: 0.071, green: 0.094, blue: 0.141, alpha: 1.0)
    )

    /// Secondary surface for nested content and supporting controls.
    static let nasMonSurfaceSecondary = Color.nasMonDynamic(
        light: UIColor(red: 0.973, green: 0.976, blue: 0.984, alpha: 1.0),
        dark: UIColor(red: 0.098, green: 0.129, blue: 0.192, alpha: 1.0)
    )

    static let nasMonOnline = Color.nasMonDynamic(
        light: UIColor(red: 0.157, green: 0.655, blue: 0.278, alpha: 1.0),
        dark: UIColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 1.0)
    )

    static let nasMonWarning = Color.nasMonDynamic(
        light: UIColor(red: 0.78, green: 0.40, blue: 0.02, alpha: 1.0),
        dark: UIColor(red: 1.0, green: 0.624, blue: 0.039, alpha: 1.0)
    )

    static let nasMonCritical = Color.nasMonDynamic(
        light: UIColor(red: 0.85, green: 0.15, blue: 0.18, alpha: 1.0),
        dark: UIColor(red: 1.0, green: 0.271, blue: 0.227, alpha: 1.0)
    )

    /// File type accents used for quick scanning in the native file list.
    static let nasMonFileImage = Color.nasMonDynamic(
        light: UIColor(red: 0.58, green: 0.23, blue: 0.78, alpha: 1.0),
        dark: UIColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1.0)
    )

    static let nasMonFileVideo = Color.nasMonDynamic(
        light: UIColor(red: 0.86, green: 0.12, blue: 0.35, alpha: 1.0),
        dark: UIColor(red: 1.0, green: 0.22, blue: 0.40, alpha: 1.0)
    )

    static let nasMonFileAudio = Color.nasMonDynamic(
        light: UIColor(red: 0.78, green: 0.40, blue: 0.02, alpha: 1.0),
        dark: UIColor(red: 1.0, green: 0.624, blue: 0.039, alpha: 1.0)
    )

    static let nasMonFileText = Color.nasMonDynamic(
        light: UIColor(red: 0.0, green: 0.48, blue: 0.62, alpha: 1.0),
        dark: UIColor(red: 0.20, green: 0.68, blue: 0.86, alpha: 1.0)
    )

    /// System-adaptive canvas used by PDF and text reading surfaces.
    static let nasMonContentBackground = Color(uiColor: .systemBackground)

    /// Used only by fully immersive media surfaces.
    static let nasMonImmersiveBackground = Color.black

    private static func nasMonDynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
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
