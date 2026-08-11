//
//  VideoPlayerView.swift
//  NasMon
//
//  Created by Brian Li on 8/2/26.
//
//  Fullscreen-only video player. There is no inline/embedded playback
//  surface anymore — `FileManagerView` presents `FullscreenVideoPlayerView`
//  in a dedicated `.fullScreenCover` (via `VideoPlayerRouteView`) as soon as
//  the AVPlayer is ready.
//  (Merged from the former VideoPlayerView.swift + FullScreenPlayerView.swift)
//
//  Shared UI components (center controls, progress section, control state)
//  live in PlayerSharedComponents.swift and are reused by the audio player
//  (AudioPlayerView.swift) so both stay visually consistent.
//

import SwiftUI
import AVKit
import AVFoundation
import UIKit

// MARK: - AVPlayerLayer UIView Wrapper

/// Container view whose backing layer is an AVPlayerLayer.
final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// A UIViewRepresentable that renders video via AVPlayerLayer.
struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = videoGravity
    }
}

// MARK: - Full Screen Video Player

/// The single video playback surface in the app — always fullscreen.
/// `FileManagerView` pushes this (via `VideoPlayerRouteView`) as soon as the
/// video is downloaded and the AVPlayer is ready; there's no inline/embedded
/// step. It runs inside the app's main `NavigationStack`, so the back button
/// is `dismiss()` and the tab bar is hidden for an immersive experience.
struct FullscreenVideoPlayerView: View {
    let player: AVPlayer
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var observer = PlaybackObserver()
    @State private var controls = PlayerControlsState()
    /// Volume (0…1), drives the expandable volume slider. Written back to AVPlayer on drag.
    @State private var volume: Double = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoLayerView(player: player)
                .ignoresSafeArea()
                .onTapGesture { controls.toggleControls() }

            if controls.controlsVisible {
                ZStack {
                    // Keep transport controls at the viewport's true center.
                    // Putting them in the same VStack as the bottom bar makes
                    // the bottom bar consume layout space and pushes them up.
                    centerControls
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .center
                        )
                        // Apply separate optical corrections for each
                        // orientation: portrait needs a little more lift
                        // because the bottom controls carry more visual weight.
                        .offset(y: verticalSizeClass == .compact ? -18 : -24)

                    VStack(spacing: 0) {
                        Spacer()
                        bottomBar
                    }
                }
                .transition(.opacity)
            }
        }
        .toolbar {
            // Back button + ToolbarSpacer + AirPlay are all ToolbarContent; they must be separate toolbar items
            // (ToolbarItemGroup only accepts View). All hide/show together with the control bar.
            if controls.controlsVisible {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                    // Local dark color scheme: toolbar doesn't follow page appearance, buttons explicitly white.
                    .foregroundStyle(.white)
                }

                // ToolbarSpacer was introduced in iOS 26. On iOS 18 the
                // AirPlay button remains adjacent to the close button.
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarLeading)
                }

                ToolbarItemGroup(placement: .topBarLeading) {
                    AirPlayButton()
                        .frame(width: 36, height: 36)
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Volume control: icon only by default; tapping expands a pill-shaped slider to the icon's left.
                    VolumeControlView(volume: $volume, foreground: .white)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        // Force dark: video player always black background + white controls, independent of app appearance.
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Hide the system back button; keep only our custom close button.
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        // Top nav bar always visible; status bar follows. Portrait → white text on black; fullscreen landscape → hidden for immersion.
        .statusBarHidden(verticalSizeClass == .compact)
        // Presented as an independent fullScreenCover: preferredColorScheme affects only the cover (black bg, white controls), not the app.
        .preferredColorScheme(.dark)
        .onAppear {
            observer.attach(to: player)
            controls.attach(to: player)
            player.play()
            controls.scheduleAutoHide()
            // Sync with the current player volume.
            volume = Double(player.volume)
        }
        .onChange(of: volume) { _, newValue in
            player.volume = Float(newValue)
        }
        .onDisappear {
            observer.detach()
            controls.cancelAutoHide()
            player.pause()
        }
    }

    // MARK: - Center Controls

    private var centerControls: some View {
        PlayerCenterControls(
            isPlaying: controls.isPlaying,
            onTogglePlayback: { controls.togglePlayback() },
            onSeek: { controls.seek(by: $0) },
            onTap: { controls.scheduleAutoHide() }
        )
    }

    // MARK: - Progress Bar

    private var bottomBar: some View {
        NasMonGlassContainer {
            VStack(alignment: .leading, spacing: 12) {
                // Title: left-aligned above the progress bar.
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                PlayerProgressSection(
                    value: Binding(
                        get: { controls.isScrubbing ? controls.scrubTime : observer.currentTime },
                        set: { controls.scrubTime = $0 }
                    ),
                    duration: observer.duration,
                    showsRemainingTime: true,
                    onEditingChanged: { editing in
                        controls.isScrubbing = editing
                        if !editing {
                            controls.commitScrub(to: controls.scrubTime, using: observer)
                        } else {
                            controls.cancelAutoHide()
                        }
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}

// MARK: - Video Player Route

/// Self-contained pushed destination for video playback. `FileManagerView`
/// pushes this directly (no intermediate preview page), so tapping a video
/// file lands straight here with a loading state; once the download finishes
/// the AVPlayer is created and the fullscreen player appears in place.
///
/// The route owns its download/player state — returning to the folder list
/// is a simple pop, and this view never re-triggers playback by itself.
struct VideoPlayerRouteView: View {
    let file: DSMFile
    var client: DSMClient?

    @State private var viewModel: MediaPlayerViewModel
    @State private var player: AVPlayer?
    @State private var mediaErrorMessage: String?
    @State private var isLoading = false

    private var title: String {
        (file.path as NSString).lastPathComponent
            .replacingOccurrences(of: ".\(file.fileExtension)", with: "")
    }

    init(file: DSMFile, client: DSMClient?) {
        self.file = file
        self.client = client
        _viewModel = State(initialValue: MediaPlayerViewModel(file: file))
    }

    var body: some View {
        Group {
            if let player = player {
                FullscreenVideoPlayerView(player: player, title: title)
            } else {
                FullscreenLoadingView(
                    title: title,
                    isLoading: isLoading,
                    errorMessage: mediaErrorMessage ?? "Couldn't load video",
                    showsRetry: mediaErrorMessage == nil,
                    onRetry: { Task { await loadVideo() } }
                )
            }
        }
        .task {
            viewModel.activeClient = client
            isLoading = true
            defer { isLoading = false }
            await loadVideo()
        }
        .onDisappear {
            // Returned to the folder list — release the player & temp files.
            player?.replaceCurrentItem(with: nil)
            player = nil
            viewModel.cleanup()
        }
    }

    /// Download the video and set up the AVPlayer.
    private func loadVideo() async {
        guard player == nil else { return }
        if let newPlayer = await viewModel.makePlayer() {
            mediaErrorMessage = nil
            player = newPlayer
            newPlayer.play()
        } else {
            // makePlayer set errorMessage (download failure / unsupported format).
            mediaErrorMessage = viewModel.errorMessage ?? "Couldn't load video"
        }
    }
}

// MARK: - AirPlay

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        // Explicitly white under the player's local dark scheme, matching other buttons.
        view.tintColor = .white
        view.activeTintColor = .white
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Preview

#Preview("Fullscreen Player") {
    NavigationStack {
        FullscreenVideoPlayerView(
            player: AVPlayer(url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!),
            title: "Big Buck Bunny"
        )
    }
}
