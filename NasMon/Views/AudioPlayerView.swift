//
//  AudioPlayerView.swift
//  NasMon
//
//  Created by Brian Li on 8/2/26.
//
//  Apple Music-style fullscreen audio player.
//  Controls are always visible and do not auto-hide.
//  `FileManagerView` presents this (via `AudioPlayerRouteView`) in a
//  dedicated `.fullScreenCover` as soon as the AVPlayer is ready.
//  Shared UI components live in PlayerSharedComponents.swift.
//
//  Dynamic theming: the background gradient is derived from the album
//  artwork's dominant color, keeping the near-black immersive backdrop.
//

import SwiftUI
import AVFoundation
import CoreImage

// MARK: - Artwork Palette Extraction

/// Extract dominant hue from album artwork to generate a dynamic background
/// that harmonizes with the cover art.
///
/// Uses `CIAreaAverage` to compute the average color of the cover, then
/// builds a gradient with that hue but kept at low brightness so white text
/// and glass buttons remain legible on dark backgrounds.
struct ArtworkPalette {
    /// Gradient endpoints for the background (kept dark to preserve text legibility).
    let backgroundGradient: [Color]

    /// Shared CIContext — thread-safe, reusable across threads.
    private static let sharedContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// Extract dominant color from artwork. Returns nil when the cover is
    /// near grayscale (very low saturation), in which case callers should fall
    /// back to the default dark background.
    static func palette(from image: UIImage) -> ArtworkPalette? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        // CIAreaAverage: compute the average color across the entire cover.
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter?.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        sharedContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let color = UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Cover lacks enough saturation (gray/black/white) — fall back.
        guard saturation > 0.12 else { return nil }

        return ArtworkPalette(
            backgroundGradient: [
                // Top: cover hue + mid-low brightness, keeping the dark atmosphere.
                Color(UIColor(
                    hue: hue,
                    saturation: min(saturation * 0.9, 0.7),
                    brightness: 0.30,
                    alpha: 1
                )),
                // Bottom: deeper hue for a more immersive gradient.
                Color(UIColor(
                    hue: hue,
                    saturation: min(saturation * 0.85, 0.6),
                    brightness: 0.12,
                    alpha: 1
                ))
            ]
        )
    }
}

// MARK: - Fullscreen Audio Player

/// Apple Music-style fullscreen audio player.
/// Layout: top bar → large album art → title → progress bar → bottom controls.
/// Controls are always visible and do not auto-hide.
struct AudioPlayerLayout: Equatable {
    let usesHorizontalLayout: Bool
    let artworkSide: CGFloat
    let horizontalPadding: CGFloat

    init(container: CGSize, usesCompactHeight: Bool) {
        usesHorizontalLayout = usesCompactHeight && container.width > container.height
        horizontalPadding = usesHorizontalLayout ? 32 : 24

        if usesHorizontalLayout {
            // Leave enough room for the title, progress, and transport controls
            // on the trailing side of an iPhone in landscape.
            artworkSide = min(300, max(144, min(container.height - 80, container.width * 0.38)))
        } else {
            artworkSide = min(350, max(144, min(container.width - 48, container.height * 0.46)))
        }
    }
}

struct FullscreenAudioPlayerView: View {
    let player: AVPlayer
    let title: String
    let artistName: String?
    let albumArtwork: UIImage?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var observer = PlaybackObserver()
    @State private var controls = PlayerControlsState()

    /// Dynamic color palette extracted from the album artwork; nil means fall back to the default light gray background.
    @State private var palette: ArtworkPalette?

    /// Default background when no artwork (or colorless cover): light gray, matching the black controls in light mode.
    private static let defaultBackgroundColors: [Color] = [
        Color(red: 0.9, green: 0.9, blue: 0.9),
        Color(red: 0.9, green: 0.9, blue: 0.9),
    ]

    /// Whether the current UI uses a dark theme (colorful cover → gradient; no cover → light gray).
    /// Toolbar buttons use this directly (they don't follow local environment overrides).
    private var isDarkUI: Bool { palette != nil }

    var body: some View {
        GeometryReader { proxy in
            let layout = AudioPlayerLayout(
                container: proxy.size,
                usesCompactHeight: verticalSizeClass == .compact
            )

            ZStack {
                // Dynamic background — derived from the album artwork's
                // dominant hue, keeping the near-black immersive backdrop.
                LinearGradient(
                    colors: palette?.backgroundGradient ?? Self.defaultBackgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).ignoresSafeArea()

                if layout.usesHorizontalLayout {
                    HStack(spacing: 28) {
                        albumArt(
                            side: layout.artworkSide,
                            usesCompactLandscapeScale: true
                        )

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            titleSection(alignment: .center)
                            progressSection
                                .padding(.top, 24)
                            bottomControls
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: 460, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.vertical, 36)
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 16)
                        albumArt(
                            side: layout.artworkSide,
                            usesCompactLandscapeScale: false
                        )
                        .offset(y: -14)
                        Spacer(minLength: 24)
                        titleSection(alignment: .center)
                        progressSection
                            .padding(.top, 24)
                        bottomControls
                            .padding(.top, 32)
                            .padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, layout.horizontalPadding)
                }
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
                // Toolbar doesn't follow local color scheme — color explicitly by cover depth.
                .foregroundStyle(isDarkUI ? Color.white : Color.black)
            }

        }
        .toolbarBackground(.hidden, for: .navigationBar)
        // Hide the system back button added by NavigationStack; keep only our custom close button.
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(false)
        // Presented as an independent fullScreenCover: preferredColorScheme affects
        // only the cover (colorful → dark UI; no artwork → light UI), not the app.
        .preferredColorScheme(isDarkUI ? .dark : .light)
        .onAppear {
            observer.attach(to: player)
            controls.attach(to: player)
            player.play()
        }
        .onDisappear {
            observer.detach()
            controls.cancelAutoHide()
            player.pause()
        }
        // Extract dominant color from artwork on a background task to avoid blocking the main thread.
        .task(id: albumArtwork) {
            guard let artwork = albumArtwork else {
                palette = nil
                return
            }
            let extracted = await Task.detached(priority: .userInitiated) {
                ArtworkPalette.palette(from: artwork)
            }.value
            palette = extracted
        }
    }

    // MARK: - Album Art

    private func albumArt(
        side: CGFloat,
        usesCompactLandscapeScale: Bool
    ) -> some View {
        ZStack {
            if let artwork = albumArtwork {
                // Real album artwork — rounded rectangle
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            } else {
                // Fallback — rounded rectangle with gradient + icon
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: side, height: side)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 64))
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
        }
        // Cover shrinks when paused, returns to full size when playing — visual feedback for playback state.
        // Playing: 300pt (large); paused: ~300×0.92 ≈ 276pt.
        // Animation style:
        // - Restore (playing) → low-damping spring with overshoot (bounce)
        // - Shrink (paused) → near-critical damping, fast and clean without bounce
        // Shadow follows playback state: heavier when playing (0.4/20/10), lighter when paused (0.15/10/4).
        .shadow(
            color: (albumArtwork != nil ? Color.black : Color.pink)
                .opacity(controls.isPlaying ? 0.4 : 0.15),
            radius: controls.isPlaying ? 20 : 10,
            y: controls.isPlaying ? 10 : 4
        )
        .scaleEffect(
            controls.isPlaying
                ? 1.0
                : (usesCompactLandscapeScale ? 0.9 : 0.75)
        )
        .animation(
            .spring(
                response: 0.4,
                dampingFraction: controls.isPlaying ? 0.45 : 0.85
            ),
            value: controls.isPlaying
        )
    }

    // MARK: - Title Section

    private func titleSection(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)

            Text(artistName ?? "NasMon")
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        PlayerProgressSection(
            value: Binding(
                get: { controls.isScrubbing ? controls.scrubTime : observer.currentTime },
                set: { controls.scrubTime = $0 }
            ),
            duration: observer.duration,
            showsRemainingTime: false,
            timeLabelOpacity: 0.6,
            onEditingChanged: { editing in
                controls.isScrubbing = editing
                if !editing {
                    controls.commitScrub(to: controls.scrubTime, using: observer)
                } else {
                    controls.cancelAutoHide()
                }
            }
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        PlayerCenterControls(
            isPlaying: controls.isPlaying,
            spacing: 32,
            playButtonSize: 84,
            playButtonFontSize: 32,
            sideButtonSize: 64,
            sideButtonFontSize: 26,
            playButtonStyle: .plain,
            usesGlassEffect: false,
            onTogglePlayback: { controls.togglePlayback() },
            onSeek: { controls.seek(by: $0) }
        )
        // Audio controls use plain semi-transparent circular buttons (no glass effect); icons still toggle between black/white with the page's light/dark scheme.
    }
}

// MARK: - Audio Player Route

/// Self-contained pushed destination for audio playback. `FileManagerView`
/// pushes this directly (no intermediate preview page), so tapping an audio
/// file lands straight here with a loading state; once the download finishes
/// the AVPlayer is created and the fullscreen player appears in place.
///
/// The route owns its download/player state — returning to the folder list
/// is a simple pop, and this view never re-triggers playback by itself.
struct AudioPlayerRouteView: View {
    let file: DSMFile
    var client: DSMClient?

    @State private var viewModel: MediaPlayerViewModel
    @State private var player: AVPlayer?
    @State private var mediaErrorMessage: String?
    @State private var isLoading = false

    /// Song title from the file's metadata, falling back to the filename
    /// (without extension) when the audio carries no title tag.
    private var title: String {
        if let audioTitle = viewModel.audioTitle, !audioTitle.isEmpty {
            return audioTitle
        }
        return (file.path as NSString).lastPathComponent
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
                FullscreenAudioPlayerView(
                    player: player,
                    title: title,
                    artistName: viewModel.audioArtist,
                    albumArtwork: viewModel.albumArtworkImage
                )
            } else {
                FullscreenLoadingView(
                    title: title,
                    isLoading: isLoading,
                    errorMessage: mediaErrorMessage ?? "Couldn't load audio",
                    showsRetry: mediaErrorMessage == nil,
                    onRetry: { Task { await loadAudio() } },
                    // Audio: use light background matching FullscreenAudioPlayerView's no-artwork default (black controls).
                    isAudio: true
                )
            }
        }
        .task {
            viewModel.activeClient = client
            // A local cache yields metadata immediately. For a stream,
            // `makePlayer()` requests metadata from the same streaming asset
            // without making playback wait for a completed cache entry.
            await viewModel.loadPreview()

            isLoading = true
            defer { isLoading = false }
            await loadAudio()
        }
        .onDisappear {
            // Returned to the folder list — release the player & buffers.
            player?.replaceCurrentItem(with: nil)
            player = nil
            viewModel.cleanup()
        }
    }

    /// Stream the audio and set up the AVPlayer.
    private func loadAudio() async {
        guard player == nil else { return }
        if let newPlayer = await viewModel.makePlayer() {
            mediaErrorMessage = nil
            player = newPlayer
            newPlayer.play()
        } else {
            // makePlayer set errorMessage (download failure / unsupported format).
            mediaErrorMessage = viewModel.errorMessage ?? "Couldn't load audio"
        }
    }
}

// MARK: - Preview

#Preview("Fullscreen Audio Player — HTTP URL (metadata unavailable)") {
    FullscreenAudioPlayerView(
        player: AVPlayer(url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!),
        title: "SoundHelix Song 1",
        artistName: nil,     // HTTP streaming URLs can't extract metadata
        albumArtwork: nil,   // Falls back to the default gradient cover
    )
}

// To test local file metadata extraction:
// Drag a real MP3/M4A into Xcode project, then uncomment:
// #Preview("Fullscreen Audio Player — Local file") {
//     @Previewable @State var isPresented = true
//     if let localURL = Bundle.main.url(forResource: "test-song", withExtension: "mp3") {
//         let vm = MediaPlayerViewModel(file: DSMFile(path: "/test.mp3", name: "test.mp3", isdir: false, additional: nil))
//         vm.audioArtist = "Test Artist"  // Simulated artist name from metadata
//         vm.albumArtworkImage = UIImage(systemName: "music.note")  // Simulated artwork
//         return FullscreenAudioPlayerView(
//             player: AVPlayer(url: localURL), title: "Test Song",
//             artistName: vm.audioArtist, albumArtwork: vm.albumArtworkImage,
//             isPresented: $isPresented)
//     }
//     fatalError("No test audio file found")
// }
