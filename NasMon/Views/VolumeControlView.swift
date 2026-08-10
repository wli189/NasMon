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

    /// Width of the volume slider track once expanded.
    private let barWidth: CGFloat = 90
    /// Height of the capsule slider track (matches progress bar's 10pt).
    private let barHeight: CGFloat = 10
    /// Shared height for the control / icon button diameter.
    private let controlHeight: CGFloat = 36
    /// Distance between icon and slider.
    private let spacing: CGFloat = 8

    /// Landscape (compact height) → always expanded.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            if isExpanded {
                expandedUI
                    .transition(.opacity.combined(with: .horizontalScale))
            } else {
                collapsedUI
                    .transition(.opacity)
            }
        }
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

    // MARK: - Collapsed UI (icon only)

    private var collapsedUI: some View {
        Button {
            // Landscape is always expanded; tapping in portrait switches to the expanded UI.
            guard !isLandscape else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                isExpanded = true
            }
        } label: {
            Image(systemName: volumeIcon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: controlHeight, height: controlHeight)
        }
        .foregroundStyle(foreground)
    }

    // MARK: - Expanded UI (icon + slider)

    private var expandedUI: some View {
        HStack(spacing: spacing) {
            volumeBar
                .padding(.leading, spacing)

            Button {
                // Landscape is always expanded; tapping in portrait switches back to collapsed.
                guard !isLandscape else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    isExpanded = false
                }
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: controlHeight, height: controlHeight)
            }
            .foregroundStyle(foreground)
        }
    }

    // MARK: - Volume Bar

    private var volumeBar: some View {
        let progress = clamp(volume, 0, 1)

        // Fill anchors to the leading edge, growing left→right as volume increases.
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(foreground.opacity(0.25))
                .frame(width: barWidth, height: barHeight)

            Rectangle()
                .fill(foreground)
                .frame(width: barWidth * progress, height: barHeight)
        }
        .clipShape(Capsule())
        .frame(width: barWidth, height: controlHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    volume = clamp(drag.location.x / barWidth, 0, 1)
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
