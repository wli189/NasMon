# NasMon

NasMon is an iOS/iPadOS app for connecting to Synology NAS devices, browsing and previewing files, and monitoring system status.

## Features

- Save multiple NAS servers and sign in to DSM
- Browse shared folders, preview documents, and play audio and video
- View system information and resource usage

## Run

Requires Xcode and a device or simulator running iOS 18.5 or later.

1. Open `NasMon.xcodeproj` in Xcode.
2. Select the `NasMon` scheme and a target device, then click Run.
3. Add your NAS address in the app and sign in. The default DSM HTTPS port is `5001`.

Dependencies are managed with Swift Package Manager and are resolved by Xcode when the project is first opened. The current HTTPS implementation trusts certificates for the NAS host; connect only to NAS devices you trust.
