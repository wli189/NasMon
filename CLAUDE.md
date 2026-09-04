# NasMon - iOS App

## Agent skills

### Issue tracker

Issues are tracked on a self-hosted **Gitea** instance (`http://10.0.0.84:3001/brian/NasMon`).
See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical labels used in Gitea: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: root `CONTEXT.md` + `docs/adr/`.
See `docs/agents/domain.md`.

## Multiplatform structure

- iPhone and iPadOS use the same `NasMon` iOS target and the same source tree.
- Use `horizontalSizeClass` and adaptive SwiftUI containers for iPhone/iPad layout differences; do not create separate iPhone and iPad code trees.
- Keep all current software code under `NasMon/`.
- `NasMon/Models/` contains platform-neutral DSM and application data models.
- `NasMon/Services/Core/` contains platform-neutral networking, DSM operations, caching, preview routing, streaming transport, and session logic. New core code should avoid `UIKit` and `AppKit`.
- `NasMon/ViewModels/Shared/` contains ViewModels that use only Foundation, Observation, and the Core modules.
- `NasMon/ViewModels/iOS/` contains ViewModels coupled to iOS media or UIKit APIs.
- `NasMon/Views/iOS/` contains the single shared iPhone/iPadOS UI, grouped by feature. It is not split into `iPhone/` and `iPad/` directories.
- Keep platform-specific adapters under `NasMon/Services/iOS/` or `NasMon/Services/macOS/` when those targets are added.
- When a native macOS target is added, add a separate `App/macOS/` and `Views/macOS/` shell. Extract `Models/` and `Services/Core/` into a local `NasMonCore` Swift Package after both targets compile against the same interface.
- The complete directory contract and migration sequence is documented in `docs/architecture/multiplatform.md`.
