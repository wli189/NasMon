# NasMon

A lightweight iOS client for monitoring a Synology DiskStation NAS.

## Features

- **Dashboard** — live CPU, memory, temperature, and disk utilization
- **File Manager** — browse shares, stream previews of images, PDFs, and text
- **Media Player** — audio and video playback from the NAS

## Getting Started

1. Configure your NAS address in Settings.
2. Log in with your DSM account.
3. Browse to **File Manager** and tap any previewable file.

## Sample Markdown

This block exercises code highlighting:

```swift
struct NasMonApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Inline code like `PreviewCache.url(for: file)` and `streamingChannel` renders
inside normal sentences. Here is a short list of supported preview types:

- Images (JPEG, PNG, HEIC)
- PDF documents
- Plain text and source code (YAML, JSON, Swift, Python, ...)
- Office documents via Quick Look

> Tip: pull down to refresh the dashboard for the latest utilization values.
