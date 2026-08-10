//
//  MediaPlayerViewModel.swift
//  NasMon
//
//  Created by Brian Li on 8/3/26.
//

import Foundation
import Observation
import UIKit
import AVFoundation

/// View model for media playback (video/audio) in the fullscreen players.
///
/// Streams media from the NAS through `AVAssetResourceLoader` (custom
/// `nasstream://` scheme) so playback starts before the whole file arrives
/// (see ADR-0002). A fully cached copy — from a previous preview/download —
/// is played directly for offline support.
@MainActor
@Observable
final class MediaPlayerViewModel {

    // MARK: - Data

    let file: DSMFile

    /// Album artwork extracted from the local or streaming audio asset.
    var albumArtworkImage: UIImage?
    /// Artist name extracted from the local or streaming audio asset.
    var audioArtist: String?
    /// Song title extracted from the local or streaming audio asset.
    var audioTitle: String?

    var errorMessage: String?

    // MARK: - Dependencies

    var activeClient: DSMClient?

    /// Retains the resource-loader data source while the player is alive.
    private var streamingDataSource: StreamingMediaDataSource?
    /// Serial queue on which AVFoundation calls the resource-loader delegate.
    private let mediaLoaderQueue = DispatchQueue(label: "com.nasmon.media-loader")
    /// Keeps the metadata request cancellable when the route is dismissed.
    private var metadataTask: Task<Void, Never>?

    private let sessionService = SessionService.shared

    init(file: DSMFile) {
        self.file = file
    }

    // MARK: - Load Media

    /// Read audio metadata (artwork / artist name) for the audio player.
    ///
    /// A complete cache entry is the fastest source. When playback streams,
    /// `makeStreamingPlayer` reads this same asset's metadata asynchronously;
    /// it does not wait for a whole-file cache entry first.
    func loadPreview() async {
        guard file.previewType == .audio else { return }
        errorMessage = nil
        let scope = activeClient?.cacheScope
        guard PreviewCache.isComplete(for: file, server: scope) else { return }
        let url = PreviewCache.url(for: file, server: scope)
        let metadata = await AudioMetadataReader.read(from: url)
        albumArtworkImage = metadata.artwork
        audioArtist = metadata.artist
        audioTitle = metadata.title
    }

    /// Build an `AVPlayer` ready for playback.
    ///
    /// Prefers a complete local cache entry (offline). Otherwise creates a
    /// streaming asset backed by `StreamingMediaDataSource`, verifies iOS can
    /// decode it, and configures the audio session. Returns `nil` with
    /// `errorMessage` set when playback can't start — callers surface
    /// `errorMessage` as the user-facing message.
    func makePlayer() async -> AVPlayer? {
        guard let client = activeClient else {
            errorMessage = "No active session."
            return nil
        }

        // Complete cache hit → play locally, no streaming needed.
        if PreviewCache.isComplete(for: file, server: client.cacheScope) {
            let url = PreviewCache.url(for: file, server: client.cacheScope)
            guard await Self.isMediaPlayable(at: url) else {
                errorMessage = Self.unsupportedMediaMessage
                return nil
            }
            Self.configureAudioSessionForPlayback()
            return AVPlayer(url: url)
        }

        // Streaming path: route a custom-scheme URL through the loader.
        guard let streamURL = StreamingMediaDataSource.streamingURL(for: file) else {
            errorMessage = "Couldn't build a streaming URL for this file."
            return nil
        }

        let channel = await client.streamingChannel(for: file)
        if let player = await makeStreamingPlayer(client: client, streamURL: streamURL, channel: channel) {
            return player
        }

        // The WebDAV channel was chosen but couldn't stream this file. Drop
        // WebDAV for the rest of the session and retry once over File Station
        // (see StreamingProbe.disableWebDAV).
        if channel == .webDAV {
            client.streamingProbe.disableWebDAV()
            let fallbackChannel = await client.streamingChannel(for: file)
            if fallbackChannel != .webDAV,
               let player = await makeStreamingPlayer(client: client, streamURL: streamURL, channel: fallbackChannel) {
                return player
            }
        }

        errorMessage = Self.streamingUnavailableMessage
        return nil
    }

    /// Build an `AVPlayer` backed by `StreamingMediaDataSource` over `channel`.
    /// Returns `nil` (without setting `errorMessage`) when the asset can't be
    /// decoded or the stream can't be loaded, so the caller can try a fallback.
    private func makeStreamingPlayer(
        client: DSMClient,
        streamURL: URL,
        channel: StreamingChannel
    ) async -> AVPlayer? {
        let dataSource = StreamingMediaDataSource(file: file, client: client, channel: channel)
        streamingDataSource = dataSource

        let asset = AVURLAsset(url: streamURL, options: [AVURLAssetAllowsCellularAccessKey: true])
        asset.resourceLoader.setDelegate(dataSource, queue: mediaLoaderQueue)

        guard await Self.isMediaPlayable(asset: asset) else {
            return nil
        }
        Self.configureAudioSessionForPlayback()
        if file.previewType == .audio {
            loadStreamingAudioMetadata(from: asset)
        }
        return AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }

    /// Load artwork and artist from the streaming asset after playback has
    /// become viable. This is independent of the playback start and removes
    /// the former requirement for a completed cache entry.
    private func loadStreamingAudioMetadata(from asset: AVURLAsset) {
        metadataTask?.cancel()
        metadataTask = Task { [weak self] in
            let metadata = await AudioMetadataReader.read(from: asset)
            guard !Task.isCancelled else { return }
            self?.albumArtworkImage = metadata.artwork
            self?.audioArtist = metadata.artist
            self?.audioTitle = metadata.title
        }
    }

    // MARK: - Playback Helpers

    /// Configure the audio session so video/audio playback works even
    /// when the device is in silent mode.
    private static func configureAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    /// Check whether AVPlayer can decode a local media file.
    ///
    /// AVFoundation has no decoder for WMA, OGG, OPUS, and several other
    /// legacy formats — `AVPlayer` will fail with a `FigFilePlayer` error
    /// (-12864) and never produce sound or a readable duration. Detecting
    /// this up front lets us show a clear message instead of silently
    /// opening a broken player.
    private static func isMediaPlayable(at url: URL) async -> Bool {
        await isMediaPlayable(asset: AVURLAsset(url: url))
    }

    /// Check whether AVPlayer can decode a (possibly streaming) asset.
    private static func isMediaPlayable(asset: AVURLAsset) async -> Bool {
        do {
            return try await asset.load(.isPlayable)
        } catch {
            // If we can't even ask AVFoundation (unreadable/unsupported
            // container or unreachable stream), treat it as unplayable
            // rather than guessing.
            return false
        }
    }

    /// Shared message for media formats iOS cannot decode.
    private static let unsupportedMediaMessage =
        "This media format is not supported on iOS (WMA, OGG, and OPUS cannot be played)."

    /// Message when a streaming asset can't be loaded (unsupported format or
    /// NAS connection failure).
    private static let streamingUnavailableMessage =
        "This media could not be loaded for streaming. The format may not be supported on iOS, or the NAS connection failed."

    // MARK: - Cleanup

    /// Release the streaming data source and remove playback buffer files.
    func cleanup() {
        metadataTask?.cancel()
        metadataTask = nil
        streamingDataSource = nil
        Self.clearMediaStreamDirectory()
    }

    /// Remove any leftover media playback buffer files.
    private static func clearMediaStreamDirectory() {
        let fm = FileManager.default
        let dir = PreviewCache.mediaStreamDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }
}

// MARK: - Audio Metadata Reader (file-level)

/// Extracts embedded metadata (album artwork, artist name) from audio files
/// (MP3, M4A, MP4, WAV, FLAC, etc.).
///
/// Uses raw string key comparisons rather than the `AVMetadataKey` enum
/// constants, which changed across iOS SDK versions, so this stays compatible
/// with both old and new AVFoundation APIs.
struct AudioMetadataReader {
    /// Metadata extracted from an audio file.
    struct Result {
        var artwork: UIImage?
        var artist: String?
        var title: String?
    }

    /// Read metadata from the audio file at `url`.
    static func read(from url: URL) async -> Result {
        await read(from: AVURLAsset(url: url))
    }

    /// Read metadata from a local or custom-scheme streaming asset.
    static func read(from asset: AVAsset) async -> Result {
        var result = Result()

        do {
            let items = try await asset.load(.commonMetadata)

            for item in items {
                let key = item.commonKey?.rawValue ?? ""
                let identifier = item.identifier?.rawValue ?? ""

                if key == "artwork" || identifier.contains("artwork") {
                    // Album cover (ID3 APIC / MP4 covr).
                    if let data = try? await item.load(.dataValue), data.count > 100 {
                        result.artwork = UIImage(data: data)
                    }
                } else if key == "artist" || identifier.contains("artist") {
                    // Artist / author name.
                    if let artist = try? await item.load(.stringValue), !artist.isEmpty {
                        result.artist = artist
                    }
                } else if key == "title" || identifier.contains("title") {
                    // Song title (ID3 TIT2 / MP4 ©nam).
                    if let title = try? await item.load(.stringValue), !title.isEmpty {
                        result.title = title
                    }
                }
            }
        } catch {
            // Metadata read failure is not critical — just leave result empty.
        }

        return result
    }
}
