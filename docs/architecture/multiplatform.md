# NasMon Multiplatform Architecture

## Current target model

NasMon currently has one application target: `NasMon`. It is an iOS target that serves both iPhone and iPadOS. There must not be separate iPhone and iPad source trees or targets.

The UI selects an appropriate layout from the available width:

- Compact width uses the existing `TabView` navigation.
- Regular width uses `NavigationSplitView` with a sidebar.
- Feature screens and state remain shared between both layouts.

The current iPad/iPhone implementation is in `NasMon/Views/iOS/`. The `iOS` directory means the Apple iOS platform family here, including iPhone and iPadOS.

## Current directory structure

```text
NasMon/
├── App/
│   └── NasMonApp.swift
├── Models/
│   ├── DSMClientError.swift
│   ├── DSMFileStationModels.swift
│   ├── DSMLoginResponse.swift
│   ├── DSMSystemInfoData.swift
│   ├── DSMUtilizationData.swift
│   └── SavedServer.swift
├── Presentation/
│   └── DashboardPresentation.swift
├── Services/
│   └── Core/
│       ├── DSMClient.swift
│       ├── DSMAuthService.swift
│       ├── DSMErrorCodeFormatter.swift
│       ├── DSMFileStationService.swift
│       ├── DSMSystemService.swift
│       ├── KeychainHelper.swift
│       ├── NASConnectionParser.swift
│       ├── PreviewCache.swift
│       ├── PreviewManager.swift
│       ├── PreviewRouter.swift
│       ├── ServerStore.swift
│       ├── SessionService.swift
│       ├── SessionStorage.swift
│       └── Streaming/
├── ViewModels/
│   ├── Shared/
│   │   ├── DashboardViewModel.swift
│   │   ├── FileManagerViewModel.swift
│   │   ├── PreviewViewModel.swift
│   │   └── SessionViewModel.swift
│   └── iOS/
│       └── MediaPlayerViewModel.swift
├── Views/
│   └── iOS/
│       ├── Navigation/
│       ├── Dashboard/
│       ├── Files/
│       ├── Servers/
│       ├── Settings/
│       ├── Preview/
│       └── Media/
├── DesignSystem/
└── PreviewContent/

NasMonTests/
├── Shared/
└── iOS/

NasMonUITests/
└── iOS/
```

## Ownership rules

### Models

`Models/` contains DSM response models and application data types. Models may use Foundation, but must not import SwiftUI, UIKit, or AppKit. Presentation-only properties such as theme colors belong in a View-layer extension.

### Services/Core

`Services/Core/` is the current shared-core seam. It owns the NAS protocol implementation, networking, authentication flow, session state, file caching, preview classification, and streaming transport. New code in this directory should expose a small interface and keep platform details inside its implementation.

Do not add a protocol only to rename one implementation. Add a real seam when there are two meaningful adapters, such as an iOS and macOS implementation or a production and test implementation.

### ViewModels/Shared

ViewModels in `ViewModels/Shared/` may coordinate Core modules and expose observable state to SwiftUI. They should not hold `UIImage`, `UIView`, `AVAudioSession`, or other platform-specific types.

### ViewModels/iOS

This directory contains iOS-family-specific presentation logic. `MediaPlayerViewModel` currently belongs here because it uses `UIImage`, `AVFoundation`, and iOS audio-session behavior.

### Views/iOS

All iPhone and iPadOS views live under the same directory. Group files by feature rather than device:

- `Navigation/`: feature selection and adaptive navigation shell.
- `Dashboard/`: NAS system dashboard.
- `Files/`: shared-folder and file browsing.
- `Servers/`: saved-server selection.
- `Settings/`: login, settings, and about screens.
- `Preview/`: iOS preview routes and UIKit-backed document/image surfaces.
- `Media/`: iOS video/audio players and controls.

Use width and size-class adaptation inside these views. Do not create `Views/iPhone/` or `Views/iPad/`.

### DesignSystem

`DesignSystem/` is shared by iPhone and iPadOS at the current stage. It is not part of Core because its job is visual styling. Before reusing it in macOS, remove or isolate UIKit-backed color and platform availability assumptions.

### Tests

`NasMonTests/Shared/` contains tests that can run against the shared Models, Presentation, and Core behavior. `NasMonTests/iOS/` contains UIKit, PDFKit, media, and iOS layout tests. UI tests remain under `NasMonUITests/iOS/` until a macOS UI test target exists.

## macOS migration

When macOS work begins, add a native macOS target rather than changing the existing iOS target into a platform-conditional monolith:

```text
NasMon/
├── App/
│   ├── iOS/NasMonApp.swift
│   └── macOS/NasMonMacApp.swift
├── Models/
├── Services/
│   ├── Core/
│   ├── iOS/
│   └── macOS/
├── ViewModels/
│   ├── Shared/
│   ├── iOS/
│   └── macOS/
└── Views/
    ├── iOS/
    └── macOS/
```

The macOS shell should provide its own sidebar, menu commands, window behavior, Settings scene, preview adapters, and media surface. Reuse Core and genuinely platform-neutral ViewModels; do not force iOS navigation or UIKit wrappers into macOS.

Before extracting a package, compile both application targets against the same shared source. Then move `Models/` and `Services/Core/` into:

```text
NasMonCore/
├── Package.swift
├── Sources/NasMonCore/
└── Tests/NasMonCoreTests/
```

Runestone and TreeSitter packages must be audited for macOS support before moving any text-preview code into the shared package. UIKit-backed previews and media surfaces stay in their platform directories.

## Storage and synchronization

Platform support does not imply cross-device synchronization. Keep UserDefaults and Keychain storage local to each platform until a separate sync design is approved. If synchronization is added later, each device must independently rebuild its local preview cache and media state from the shared configuration.
