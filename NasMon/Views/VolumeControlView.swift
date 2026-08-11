//
//  VolumeControlView.swift
//  NasMon
//
//  Compact volume control for the video player toolbar.
//
//  Two distinct UI states:
//  - Collapsed: a single circular icon button showing the volume icon.
//  - Expanded:  icon + slider side by side.
//
//  Orientation-aware default:
//  - Portrait  (regular height): starts collapsed; tapping the icon
//    switches between the two UIs.
//  - Landscape (compact height): always shows the expanded UI.
//
// Two UI states: collapsed (circular icon) → expanded (icon + slider).
//        [🔊]
//     ▭▭▭[🔊]
//

import SwiftUI

/// Geometry shared by both the native iOS 26 toolbar transition and the
/// fixed-width iOS 18 fallback.
///
/// Keeping the toolbar item's outer width stable is important on iOS 18:
/// UINavigationBar does not reliably animate an item's intrinsic-width change,
/// so only an internal reveal mask is animated there.
struct VolumeControlLayout: Equatable {
    let barWidth: CGFloat = 90
    let barHeight: CGFloat = 10
    let controlHeight: CGFloat = 36
    let spacing: CGFloat = 8

    /// Includes the bar's leading inset, the HStack spacing, and the icon.
    var expandedWidth: CGFloat {
        spacing + barWidth + spacing + controlHeight
    }

    func revealedWidth(isExpanded: Bool) -> CGFloat {
        isExpanded ? expandedWidth : controlHeight
    }
}

struct VolumeControlView: View {
    /// Volume (0…1), bound to the player's volume.
    @Binding var volume: Double
    /// Foreground color for icon and slider; defaults to `.primary`. The video player passes white explicitly
    /// (the player uses a local dark environment, so the toolbar doesn't follow system appearance).
    var foreground: Color = .primary

    /// Whether the expanded UI (icon + slider) is shown.
    @State private var isExpanded = false

    /// `.compact` height = landscape, `.regular` = portrait.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let layout = VolumeControlLayout()

    /// Landscape (compact height) → always expanded.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        controlBody
            .onAppear {
                // Start expanded in landscape, collapsed in portrait.
                isExpanded = isLandscape
            }
            .onChange(of: verticalSizeClass) { _, newValue in
                // Expand on landscape rotation, collapse on portrait.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    isExpanded = (newValue == .compact)
                }
            }
    }

    @ViewBuilder
    private var controlBody: some View {
        if #available(iOS 26.0, *) {
            nativeToolbarTransition
        } else {
            ios18RevealTransition
        }
    }

    /// iOS 26 can animate the toolbar item's intrinsic width as its glass form
    /// changes, so retain the compact/expanded view replacement there.
    private var nativeToolbarTransition: some View {
        Group {
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .horizontalScale))
            } else {
                volumeButton
                    .transition(.opacity)
            }
        }
    }

    /// iOS 18 fallback: the toolbar always owns the final expanded width while
    /// a trailing-aligned mask reveals the slider from underneath the icon.
    /// The navigation bar therefore never has to animate its own layout.
    private var ios18RevealTransition: some View {
        expandedContent
            .frame(
                width: layout.expandedWidth,
                height: layout.controlHeight,
                alignment: .trailing
            )
            .mask(alignment: .trailing) {
                Rectangle()
                    .frame(width: layout.revealedWidth(isExpanded: isExpanded))
            }
            .frame(
                width: layout.expandedWidth,
                height: layout.controlHeight,
                alignment: .trailing
            )
            .animation(
                .spring(response: 0.35, dampingFraction: 0.9),
                value: isExpanded
            )
    }

    // MARK: - Shared Control Content

    private var expandedContent: some View {
        HStack(spacing: layout.spacing) {
            volumeBar
                .padding(.leading, layout.spacing)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)

            volumeButton
        }
    }

    private var volumeButton: some View {
        Button {
            // Landscape stays expanded; portrait toggles between both states.
            guard !isLandscape else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: volumeIcon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: layout.controlHeight, height: layout.controlHeight)
        }
        .foregroundStyle(foreground)
        .accessibilityLabel(isExpanded ? "Collapse volume control" : "Expand volume control")
        .accessibilityValue("\(Int((clamp(volume, 0, 1) * 100).rounded())) percent")
    }

    // MARK: - Volume Bar

    private var volumeBar: some View {
        let progress = clamp(volume, 0, 1)

        // Fill anchors to the leading edge, growing left→right as volume increases.
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(foreground.opacity(0.25))
                .frame(width: layout.barWidth, height: layout.barHeight)

            Rectangle()
                .fill(foreground)
                .frame(width: layout.barWidth * progress, height: layout.barHeight)
        }
        .clipShape(Capsule())
        .frame(width: layout.barWidth, height: layout.controlHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    volume = clamp(drag.location.x / layout.barWidth, 0, 1)
                }
        )
    }

    // MARK: - Icon

    private var volumeIcon: String {
        switch volume {
        case 0: return "speaker.slash.fill"
        case 0..<0.33: return "speaker.fill"
        case 0.33..<0.66: return "speaker.wave.1.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        guard value.isFinite else { return lower }
        return Swift.min(Swift.max(value, lower), upper)
    }
}

// MARK: - Custom Transition

/// Scales only the horizontal axis (x), anchored to the trailing edge,
/// so the bar appears to "grow out of" the icon rather than popping in.
private struct HorizontalScaleModifier: ViewModifier {
    let scale: CGFloat
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content.scaleEffect(x: scale, y: 1, anchor: anchor)
    }
}

private extension AnyTransition {
    static var horizontalScale: AnyTransition {
        .modifier(
            active: HorizontalScaleModifier(scale: 0, anchor: .trailing),
            identity: HorizontalScaleModifier(scale: 1, anchor: .trailing)
        )
    }
}

#Preview {
    ZStack {
        Color.black
        VolumeControlView(volume: .constant(0.6))
    }
}
