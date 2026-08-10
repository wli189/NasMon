//
//  PlayerSharedComponents.swift
//  NasMon
//
//  Created by Brian Li on 8/2/26.
//
//  Reusable UI components shared by the fullscreen video and audio players.
//  Extracts the duplicated center controls, progress section, and playback
//  state management so both players stay visually consistent.
//

import SwiftUI
import AVFoundation
import Combine

// MARK: - Playback Observer

/// Observes an `AVPlayer`'s playback time and media duration so the UI can
/// render the progress bar. Shared by both the video and audio fullscreen
/// players (`FullscreenVideoPlayerView` / `FullscreenAudioPlayerView`).
///
/// Duration is obtained through several redundant paths because none of the
/// KVO-based approaches alone is reliable for **local** media files (which is
/// how the NAS downloads are played):
/// 1. `AVPlayerItem.duration` read synchronously (often `.indefinite` early on)
/// 2. KVO on `AVPlayerItem.status` — fires when the item becomes ready
/// 3. KVO on `AVPlayerItem.duration` — fires for streaming content
/// 4. `AVAsset.load(.duration)` — the authoritative async load that reliably
///    returns the duration for local files too
@Observable
final class PlaybackObserver {
    var currentTime: Double = 0
    var duration: Double = 0

    /// Whether a seek is in flight. While true, `currentTime` is pinned to
    /// `seekTargetTime` so the progress bar stays at the user's chosen
    /// position even if the player hasn't buffered there yet (network
    /// streams). The lock is released automatically once the player's actual
    /// time catches up to the target (or after `SEEK_TIMEOUT` seconds).
    private(set) var isSeeking = false
    /// The position the user seeked to, shown while `isSeeking`.
    private(set) var seekTargetTime: Double = 0

    private static let seekCatchupTolerance: Double = 0.5
    private static let seekTimeout: Duration = .seconds(5)

    private var timeObserverToken: Any?
    private var seekTimeoutTask: Task<Void, Never>?
    private weak var player: AVPlayer?
    private var itemCancellable: AnyCancellable?
    private var durationCancellable: AnyCancellable?
    private var statusCancellable: AnyCancellable?
    private var durationLoadTask: Task<Void, Never>?

    func attach(to player: AVPlayer) {
        self.player = player

        // 0.25 s is too coarse for short clips: on a 3 s video each update
        // moves the bar by roughly 8% of its width, which looks like one-second
        // jumps. Use a 30 Hz sample rate so the bar remains smooth without
        // adding a continuous animation to normal playback.
        let interval = CMTime(value: 1, timescale: 120)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.handlePeriodicTime(time.seconds)
        }

        // Observe currentItem changes — the item may not be ready when
        // attach() is called (especially for audio), so we need to wait
        // for it to become available before reading duration.
        itemCancellable = player.publisher(for: \.currentItem)
            .sink { [weak self] item in
                guard let self, let item else { return }
                self.observeItem(item)
            }

        // The item is usually already set when the player view appears,
        // so observe it immediately to start time/duration flowing.
        if let item = player.currentItem {
            observeItem(item)
        }
    }

    private func observeItem(_ item: AVPlayerItem) {
        // Read duration synchronously if it's already known.
        if item.duration.seconds.isFinite {
            duration = item.duration.seconds
        }

        // Re-read once the item is ready to play. Observing the item's
        // status (not the player's) is more reliable — for fast-loading
        // local files the player is usually already `.readyToPlay` by the
        // time attach() runs, so a `player.status` publisher would never
        // emit a change and the duration would stay 0 forever.
        statusCancellable = item.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self, status == .readyToPlay else { return }
                self.readDuration(of: item)
            }

        // Fallback: KVO on the item's duration. This fires for remote
        // streams whose duration becomes known gradually.
        durationCancellable = item.publisher(for: \.duration)
            .sink { [weak self] newDuration in
                guard let self, newDuration.seconds.isFinite else { return }
                self.duration = newDuration.seconds
            }

        // Authoritative async load — reliably returns the duration for
        // local files too, where the duration KVO above may never fire.
        readDuration(of: item)
    }

    /// Loads the item's duration asynchronously via `AVAsset.load`.
    /// This is the reliable way to obtain duration for both local and
    /// remote media, unlike KVO on `AVPlayerItem.duration` which can
    /// silently miss the indefinite → definite transition.
    private func readDuration(of item: AVPlayerItem) {
        durationLoadTask?.cancel()
        durationLoadTask = Task { [weak self] in
            do {
                let seconds = try await item.asset.load(.duration).seconds
                guard !Task.isCancelled, seconds.isFinite, seconds > 0 else { return }
                await MainActor.run {
                    self?.duration = seconds
                }
            } catch {
                // Fall back to whatever the item reports synchronously.
                let seconds = item.duration.seconds
                guard seconds.isFinite else { return }
                await MainActor.run {
                    self?.duration = seconds
                }
            }
        }
    }

    /// Handles each periodic time observation tick.
    ///
    /// While a seek is in flight, `currentTime` stays pinned to
    /// `seekTargetTime` — the player may not have buffered there yet (network
    /// streams) and would otherwise report the pre-seek position, making the
    /// bar flash backwards. Once the actual time catches up to within the
    /// tolerance (or the timeout fires), the lock releases and normal time
    /// updates resume.
    private func handlePeriodicTime(_ seconds: Double) {
        if isSeeking {
            currentTime = seekTargetTime
            // Check whether the player has actually arrived at the target.
            if abs(seconds - seekTargetTime) <= Self.seekCatchupTolerance {
                endSeek()
            }
        } else {
            currentTime = seconds
        }
    }

    /// Begin a seek to `targetSeconds`. The progress bar is pinned at that
    /// position until the player actually reaches it (or a timeout fires).
    func beginSeek(to targetSeconds: Double) {
        seekTargetTime = targetSeconds
        isSeeking = true
        currentTime = targetSeconds

        seekTimeoutTask?.cancel()
        seekTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.seekTimeout)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.endSeek()
            }
        }
    }

    /// End the seek lock and resume normal periodic time updates.
    private func endSeek() {
        guard isSeeking else { return }
        seekTimeoutTask?.cancel()
        seekTimeoutTask = nil
        isSeeking = false
        // The next periodic tick will overwrite currentTime with the real
        // player time (which by now has arrived at the target).
    }

    func detach() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        seekTimeoutTask?.cancel()
        seekTimeoutTask = nil
        isSeeking = false
        durationLoadTask?.cancel()
        durationLoadTask = nil
        itemCancellable = nil
        durationCancellable = nil
        statusCancellable = nil
    }
}

// MARK: - Playback Progress Bar

/// A draggable Apple TV-style progress bar for video/audio scrubbing.
///
/// Usage:
/// ```
/// PlaybackProgressBar(
///     value: Binding(
///         get: { isScrubbing ? scrubTime : currentTime },
///         set: { scrubTime = $0 }
///     ),
///     duration: duration,
///     onEditingChanged: { editing in
///         isScrubbing = editing
///         if !editing {
///             seek(to: scrubTime)
///         }
///     }
/// )
/// ```
struct PlaybackProgressBar: View {
    @Binding var value: Double
    let duration: Double
    var onEditingChanged: (Bool) -> Void = { _ in }

    var draggingTrackHeight: CGFloat = 10
    // Default to .primary; the system auto-toggles between black/white based on background.
    var trackColor: Color = .primary.opacity(0.25)
    var fillColor: Color = .primary

    // Interaction state. `isDragging` means the finger is down; `didDrag`
    // means it has moved far enough (5 pt) to count as a scrub rather than a
    // plain tap.
    @State private var isDragging = false
    @State private var didDrag = false
    /// Progress (0…1) at the moment the touch began. Used as the tap
    /// animation's start point so the bar flows from the current position
    /// instead of snapping back. Captured before `onEditingChanged(true)`
    /// switches the binding to scrubTime (which would otherwise be stale).
    @State private var touchDownProgress: Double = 0
    /// Animated progress (0…1) played back by a tap; non-nil only while the
    /// tap easing animation is running.
    @State private var tapAnimateProgress: Double?
    @State private var tapCommitTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // Display priority: tap animation > pre-drag pinned position >
            // external value (live time while playing, scrubTime while
            // scrubbing). `dragProgress`/`startDragLocation` are unnecessary:
            // once a scrub starts the value is written straight to the
            // binding, and a plain tap never touches it.
            // Only divide once the duration is known — `value / 0` produces
            // NaN when both are 0 (before the asset's duration loads), and
            // `width * NaN` crashes with "Invalid frame dimension".
            let progress = duration > 0 ? value / duration : 0
            let clamped = clamp((tapAnimateProgress
                ?? (isDragging && !didDrag ? touchDownProgress : progress)), 0, 1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(trackColor)

                Rectangle()
                    .fill(fillColor)
                    .frame(width: width * clamped)
                    // Progress updates stay live during playback; only tap-to-seek plays the easing animation.
            }
            .clipShape(Capsule())
            .frame(height: draggingTrackHeight)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            didDrag = false
                            // Capture the currently displayed position before
                            // onEditingChanged(true) switches the binding to
                            // scrubTime. A new touch also supersedes any
                            // in-flight tap animation / pending seek commit.
                            touchDownProgress = tapAnimateProgress
                                ?? (duration > 0 ? clamp(value / duration, 0, 1) : 0)
                            tapCommitTask?.cancel()
                            tapCommitTask = nil
                            tapAnimateProgress = nil
                            onEditingChanged(true)
                        }

                        // 5 pt of movement turns a tap into a scrub. Once a
                        // scrub starts, write the position straight to the
                        // binding so the fill follows the finger.
                        if hypot(drag.translation.width, drag.translation.height) > 5 {
                            didDrag = true
                        }
                        if didDrag {
                            value = clamp(drag.location.x / width, 0, 1) * duration
                        }
                    }
                    .onEnded { drag in
                        let endProgress = clamp(drag.location.x / width, 0, 1)

                        if didDrag {
                            // Scrub: the finger is already at the target.
                            endGesture(at: endProgress)
                        } else {
                            // Tap: flow once from the pre-touch position to
                            // the target, then commit. Using an internal
                            // animation (not the external value) keeps the
                            // easing smooth without a second jump from the
                            // parent's beginSeek.
                            tapCommitTask?.cancel()
                            tapAnimateProgress = touchDownProgress
                            withAnimation(tapAnimation) {
                                tapAnimateProgress = endProgress
                            }

                            tapCommitTask = Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(420))
                                guard !Task.isCancelled else { return }
                                endGesture(at: endProgress)
                            }
                        }
                    }
            )
        }
        .frame(height: draggingTrackHeight)
    }

    /// Non-linear easing for tap-to-seek. Normal playback has no implicit animation,
    /// so only taps produce a slide; scrubbing and live playback stay instant.
    private var tapAnimation: Animation {
        .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.42)
    }

    /// Ends the gesture: clears interaction/animation state and forwards the
    /// final position to the parent, which performs the actual seek.
    private func endGesture(at progress: Double) {
        isDragging = false
        didDrag = false
        tapCommitTask?.cancel()
        tapCommitTask = nil
        tapAnimateProgress = nil
        touchDownProgress = 0
        value = progress * duration
        onEditingChanged(false)
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        // NaN/±Infinity can slip through when the media duration is unknown
        // (0) — pin them to the lower bound instead of propagating a
        // non-finite pixel value into `.frame(width:)`.
        guard value.isFinite else { return lower }
        return Swift.min(Swift.max(value, lower), upper)
    }
}

// MARK: - Player Control State

/// Shared playback state and control logic for fullscreen players.
/// Both `FullscreenVideoPlayerView` and `FullscreenAudioPlayerView` use this
/// to avoid duplicating the same state properties and helper methods.
@Observable
final class PlayerControlsState {
    var isPlaying = true
    var controlsVisible = true
    var isScrubbing = false
    var scrubTime: Double = 0
    var hideTask: Task<Void, Never>?

    private weak var player: AVPlayer?
    private var endObserver: AnyCancellable?
    private var hasFinished = false

    func attach(to player: AVPlayer) {
        self.player = player
        hasFinished = false
        endObserver?.cancel()
        endObserver = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let item = notification.object as? AVPlayerItem,
                      item === self.player?.currentItem else { return }
                self.hasFinished = true
                self.isPlaying = false
            }
    }

    func togglePlayback() {
        guard let player else { return }

        if hasFinished || isAtEnd {
            hasFinished = false
            isPlaying = true
            player.seek(
                to: .zero,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { [weak self] _ in
                guard let self, let player = self.player else { return }
                player.play()
                self.scheduleAutoHide()
            }
            scheduleAutoHide()
            return
        }

        isPlaying.toggle()
        isPlaying ? player.play() : player.pause()
        scheduleAutoHide()
    }

    func seek(by seconds: Double) {
        guard let player else { return }
        hasFinished = false
        let target = CMTimeAdd(player.currentTime(), CMTime(seconds: seconds, preferredTimescale: 600))
        player.seek(to: target)
        scheduleAutoHide()
    }

    /// Commit a scrub/seek to `targetSeconds`. Pins the progress bar at the
    /// target until the player actually arrives there (handles network
    /// streams that need to buffer before jumping) — `PlaybackObserver.beginSeek`
    /// manages the lock internally and releases it once the real time
    /// catches up (or after a 5 s timeout). `isScrubbing` is cleared when the
    /// seek completes.
    func commitScrub(to targetSeconds: Double, using observer: PlaybackObserver) {
        guard let player else { return }
        hasFinished = false
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        observer.beginSeek(to: target.seconds)
        player.seek(to: target) { [weak self] _ in
            self?.isScrubbing = false
        }
    }

    func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleAutoHide()
        } else {
            hideTask?.cancel()
        }
    }

    func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    controlsVisible = false
                }
            }
        }
    }

    func cancelAutoHide() {
        hideTask?.cancel()
    }

    private var isAtEnd: Bool {
        guard let item = player?.currentItem else { return false }
        let duration = item.duration.seconds
        let currentTime = item.currentTime().seconds
        guard duration.isFinite, duration > 0, currentTime.isFinite else { return false }
        return currentTime >= duration - 0.25
    }
}

// MARK: - Player Control Button

/// A circular glass button used for player controls (rewind, forward, etc.).
struct PlayerControlButton: View {
    let systemImage: String
    var size: CGFloat = 54
    var fontSize: CGFloat = 22
    var usesGlassEffect = true
    var action: () -> Void

    @State private var animationTrigger = 0

    var body: some View {
        if usesGlassEffect {
            Button {
                animationTrigger &+= 1
                action()
            } label: {
                Image(systemName: systemImage)
                    .font(.system(size: fontSize, weight: .medium))
                    .frame(width: size, height: size)
                    .symbolEffect(.rotate.byLayer, value: animationTrigger)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            // Icon explicitly uses .primary; the system auto-toggles black/white by background brightness.
            .foregroundStyle(.primary)
        } else {
            Button {
                animationTrigger &+= 1
                action()
            } label: {
                Image(systemName: systemImage)
                    .font(.system(size: fontSize, weight: .medium))
                    .frame(width: size, height: size)
                    .contentShape(Circle())
                    .symbolEffect(.rotate.byLayer, value: animationTrigger)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Player Center Controls

/// Shared center control cluster: rewind, play/pause, forward.
/// The play button style is configurable so video uses the glass style and
/// audio uses a gradient circle.
struct PlayerCenterControls: View {
    let isPlaying: Bool
    var spacing: CGFloat = 28
    var playButtonSize: CGFloat = 72
    var playButtonFontSize: CGFloat = 28
    /// Size of the rewind/forward buttons flanking the play button.
    var sideButtonSize: CGFloat = 54
    var sideButtonFontSize: CGFloat = 22
    var playButtonStyle: PlayerPlayButtonStyle = .glass
    var usesGlassEffect = true
    var onTogglePlayback: () -> Void
    var onSeek: (Double) -> Void
    var onTap: () -> Void = {}

    @State private var playAnimationTrigger = 0

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            HStack(spacing: spacing) {
                PlayerControlButton(
                    systemImage: "gobackward.10",
                    size: sideButtonSize,
                    fontSize: sideButtonFontSize,
                    usesGlassEffect: usesGlassEffect
                ) {
                    onSeek(-10)
                }

                playButton

                PlayerControlButton(
                    systemImage: "goforward.10",
                    size: sideButtonSize,
                    fontSize: sideButtonFontSize,
                    usesGlassEffect: usesGlassEffect
                ) {
                    onSeek(10)
                }
            }
        }
        // All control buttons use .primary foreground (auto black/white by background); tint uses system accentColor.
        .tint(.accentColor)
        .onTapGesture { onTap() }
    }

    @ViewBuilder
    private var playButton: some View {
        switch playButtonStyle {
        case .glass:
            Button {
                playAnimationTrigger &+= 1
                onTogglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: playButtonFontSize, weight: .semibold))
                    .frame(width: playButtonSize, height: playButtonSize)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: playAnimationTrigger)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .foregroundStyle(.primary)

        case .plain:
            Button {
                playAnimationTrigger &+= 1
                onTogglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: playButtonFontSize, weight: .semibold))
                    .frame(width: playButtonSize, height: playButtonSize)
                    .contentShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: playAnimationTrigger)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

        case .gradient(let colors):
            Button {
                playAnimationTrigger &+= 1
                onTogglePlayback()
            } label: {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: playButtonSize, height: playButtonSize)
                    .overlay {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: playButtonFontSize, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: playAnimationTrigger)
                            // Gradient background provides contrast; icon uses .primary auto black/white.
                            .foregroundStyle(.primary)
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

/// Style options for the play/pause button in `PlayerCenterControls`.
enum PlayerPlayButtonStyle {
    case glass
    case plain
    case gradient([Color])
}

// MARK: - Player Progress Section

/// Shared progress bar + time labels section for fullscreen players.
/// `showsRemainingTime` controls whether the trailing label shows remaining
/// time (video) or total duration (audio).
struct PlayerProgressSection: View {
    @Binding var value: Double
    let duration: Double
    var showsRemainingTime = false
    /// Time label opacity; nil falls back to defaults (remaining 0.85 / total 0.7).
    var timeLabelOpacity: Double?
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 8) {
            PlaybackProgressBar(
                value: $value,
                duration: duration,
                onEditingChanged: onEditingChanged
            )

            HStack {
                Text(formatPlaybackTime(value))
                Spacer()
                Text(remainingTimeText)
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary.opacity(timeLabelOpacity ?? (showsRemainingTime ? 0.85 : 0.7)))
        }
    }

    /// Trailing time: remaining time gets a "-" prefix; total duration (audio) does not.
    private var remainingTimeText: String {
        let text = formatPlaybackTime(showsRemainingTime ? max(duration - value, 0) : duration)
        return showsRemainingTime ? "-" + text : text
    }
}

// MARK: - Shared formatting helper

/// Format playback seconds as "m:ss" or "h:mm:ss". Unavailable/live durations (non-finite) display "0:00".
func formatPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
