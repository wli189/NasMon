//
//  FullscreenLoadingView.swift
//  NasMon
//
//  Created by Brian Li on 8/4/26.
//
//  Shared loading/error surface for the fullscreen video and audio players.
//  Renders the player UI frame (title bar + bottom progress bar) so tapping
//  a video/audio file lands on an immediately recognizable player surface,
//  then swaps seamlessly to the real player once the AVPlayer is ready.
//

import SwiftUI

// MARK: - Loading View

/// Shown as the pushed route content until the fullscreen player is ready
/// (media still downloading). Unlike a bare spinner screen, this renders the
/// **player UI frame** — title bar and bottom progress bar — so tapping a
/// video/audio file lands on an immediately recognizable player surface.
/// The center shows the loading spinner (or error + retry) in the exact spot
/// where the video and transport controls will appear, so the transition to
/// the real player is seamless. The bottom progress bar stays visible but
/// non-interactive (`allowsHitTesting false`) until the AVPlayer is created.
///
/// `isAudio` switches the theming: video keeps the immersive black backdrop
/// (dark color scheme → `.primary` resolves white), audio uses the light
/// gradient background to match `FullscreenAudioPlayerView`'s no-artwork
/// default (light color scheme → `.primary` resolves black).
struct FullscreenLoadingView: View {
    let title: String
    let isLoading: Bool
    var errorMessage: String = "Couldn't load media"
    var showsRetry = true
    var onRetry: () -> Void = {}
    /// Whether this is an audio player loading state.
    var isAudio = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer()

                // Center: spinner while loading, error + retry on failure.
                // The spinner occupies the exact spot where transport controls will appear, so the transition is seamless.
                if isLoading {
                    ProgressView()
                        .tint(.primary)
                        .scaleEffect(1.3)
                } else {
                    errorContent
                }

                Spacer()

                // Bottom progress bar matches the real player (glass container + same padding).
                // Video title is also placed here (left above the bar), matching playback position. Non-interactive, semi-transparent during loading.
                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        // Video: title left above the progress bar (matches playback position). Audio keeps its title in the nav bar.
                        if !isAudio {
                            Text(title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }

                        PlayerProgressSection(
                            value: .constant(0),
                            duration: 0,
                            showsRemainingTime: !isAudio
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .allowsHitTesting(false)
                .opacity(0.6)
            }
        }
        .toolbar {
            // Back button: always shown so the user can navigate away at any time.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("Close")
                // Toolbar doesn't follow local color scheme — color explicitly by player type (audio: light, video: dark).
                .foregroundStyle(isAudio ? Color.black : Color.white)
            }

            // Audio title centered in the nav bar (matches audio playback). Video title is placed above the bottom progress bar.
            if isAudio {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        // Lock toolbar colors: dark for video, light for audio — independent of app appearance.
        .toolbarColorScheme(isAudio ? .light : .dark, for: .navigationBar)
        // Hide the system back button; keep only our custom close button.
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        // Video: status bar visible in portrait, hidden in fullscreen landscape. Audio: always shown.
        .statusBarHidden(!isAudio && verticalSizeClass == .compact)
        // Presented as a fullScreenCover: preferredColorScheme affects only the cover, not the app.
        .preferredColorScheme(isAudio ? .light : .dark)
    }

    // MARK: - Background

    private var background: some View {
        Group {
            if isAudio {
                // Matches FullscreenAudioPlayerView's no-artwork default background.
                LinearGradient(
                    colors: [
                        Color(red: 0.9, green: 0.9, blue: 0.9),
                        Color(red: 0.9, green: 0.9, blue: 0.9),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Error Content

    private var errorContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.primary.opacity(0.7))
            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if showsRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.glass)
                    // Foreground uses .primary; tint uses system accentColor.
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
            }
        }
    }
}
