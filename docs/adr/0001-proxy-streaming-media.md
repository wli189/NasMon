# Proxy Streaming Media Playback via AVAssetResourceLoader

## Context
Media files on the NAS (video/audio) can be tens of GB in size. The previous approach—downloading the entire file to a temporary local URL before playback—was causing massive storage footprint and long wait times for the user. Additionally, the Synology File Station Download API (`SYNO.FileStation.Download`) does not natively support HTTP Range requests (it outputs a complete raw stream), meaning `AVPlayer` cannot simply be pointed at the NAS URL to achieve native streaming.

## Decision
We will implement **Proxy Streaming** using iOS's `AVAssetResourceLoader`. Instead of downloading full files, we will intercept the `AVPlayer`'s data requests and proxy them through a custom `StreamingDataSource` that fetches small chunks (HTTP Range) from the NAS API on-demand.

## Consequences
- **Storage:** No longer fills up user storage; only a fixed-size in-memory buffer is maintained.
- **Latency:** Playback begins immediately upon initialization, rather than waiting for a download progress indicator.
- **Complexity:** Increases complexity in `MediaPlayerViewModel` and networking layer (`DSMClient`) significantly. We must introduce new state management (`StreamingSession`) to handle reconnection, error reporting, and buffer limits.
