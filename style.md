# NasMon Visual & UI Architecture Design Specification

> **Design Philosophy: Hybrid structure, unified visuals.**
>
> The outer shell uses native iOS skeletons for stability, familiarity, and ease of use; the Dashboard incorporates "Deep Sea Console" elements to emphasize NAS monitoring identity; file previews and media players follow a content-first immersive experience.

---

## 1. Design Goals

NasMon's UI consists of four distinct surface types:

1. **Connection Flow**: Server selection, adding servers, login, and connection status.
2. **Main Functional Interfaces**: File management, system Dashboard, Tabs, and navigation.
3. **Content Previews**: Images, PDFs, text, code, and Quick Look.
4. **Immersive Media**: Video and audio players.

These surfaces don't need to look visually identical, but they must share a common foundational language:

- Semantic colors
- Typography hierarchy
- Spacing system
- Corner radius & container rules
- State feedback
- Toolbar & button hierarchy
- Animation principles
- Accessibility guidelines

The goal of the design system is not to turn every page into cards, but to make different pages feel like they belong to the same product.

---

## 2. Style Architecture

### 2.1 Native Professional Base

Applies to:

- Server selection & editing
- Login forms
- File manager
- Settings
- Alerts, Sheets, Menus, and Context Menus

Design principles:

- Retain `NavigationStack`, `List`, `Form`, system Sheets, and system menus.
- Prefer SF Symbols.
- Maintain high information density.
- Use system semantic text colors and dynamic type.
- Use cards only for content with clear boundaries; don't cardify everything.
- Use color to express hierarchy without making color the sole status cue.

### 2.2 Deep Sea Console Elements

Applies to:

- NAS system overview
- CPU, memory, temperature, and storage metrics
- Real-time network traffic
- Online status & health indicators
- Server uptime

Design principles:

- Dark mode uses deep blue-black pages with blue-gray cards instead of pure-black stacking.
- Light mode uses light-gray pages with white cards; don't force all cards to be dark.
- Dynamic numbers use tabular numerals; titles and descriptions keep the system default font.
- Primary data uses brand blue, health uses green, warnings use orange, critical errors use red.
- Chart colors stay restrained; avoid using different decorative colors for every metric.

### 2.3 Content-First Preview

Applies to:

- Image previews
- PDF reading
- Text & code previews
- Quick Look

Design principles:

- Content occupies the primary visual space.
- Preview Chrome stays minimal: only back, file info, transfer status, and essential actions.
- Chrome visibility changes must not shift the阅读 position.
- PDFs, code, and text prioritize readability over Dashboard decorative styling.
- Errors, empty states, and loading states need explicit feedback; no blank canvases without indication.

### 2.4 Immersive Media

Applies to:

- Video player
- Audio player

Design principles:

- Video uses a pure-black immersive background.
- Video controls auto-hide on inactivity.
- Audio player uses dynamic dominant color gradients extracted from album art.
- Material blur applies only to local buttons or overlays, not forced as real-time full-cover blur.
- Controls must maintain sufficient contrast against complex backgrounds.
- Media surfaces can have their own atmosphere, but back, share, error, and loading semantics must remain globally consistent.

---

## 3. Semantic Colors

Business views must not scatter hex colors everywhere. Colors must be provided through Asset Catalog or Design System semantic tokens.

### 3.1 Global Colors

| Token | Light Mode | Dark Mode | Purpose |
| --- | --- | --- | --- |
| `accent` | `#007AFF` | `#409CFF` | Primary buttons, selected state, interactive elements, folders |
| `pageBackground` | `#F2F4F8` | `#080D16` | Dashboard & grouped page backgrounds |
| `surface` | `#FFFFFF` | `#121824` | Cards, blocks, overlays |
| `surfaceSecondary` | `#F7F8FA` | `#192131` | Secondary cards, input areas, auxiliary containers |
| `online` | `#28A745` | `#34C759` | Online, healthy, normal |
| `warning` | `#D97706` | `#FF9F0A` | High utilization, temperature warnings, non-critical anomalies |
| `critical` | `#D9363E` | `#FF453A` | Offline, failure, dangerous actions |
| `contentBackground` | System background | System background | PDFs, text, content canvases |
| `immersiveBackground` | `#000000` | `#000000` | Video & immersive media |

Body text should prefer system semantic colors:

```swift
.foregroundStyle(.primary)
.foregroundStyle(.secondary)
.foregroundStyle(.tertiary)
```

### 3.2 SwiftUI Naming Convention

```swift
extension Color {
    static let nasMonAccent = Color("NasMonAccent")
    static let nasMonPageBackground = Color("NasMonPageBackground")
    static let nasMonSurface = Color("NasMonSurface")
    static let nasMonSurfaceSecondary = Color("NasMonSurfaceSecondary")
    static let nasMonOnline = Color("NasMonOnline")
    static let nasMonWarning = Color("NasMonWarning")
    static let nasMonCritical = Color("NasMonCritical")
}
```

Pages use semantic names, never raw `Color.blue` or RGB values:

```swift
.tint(.nasMonAccent)
.foregroundStyle(.nasMonOnline)
.background(.nasMonSurface)
```

### 3.3 File Type Colors

File type colors are for quick scanning only; don't assign a unique color to every extension.

| File Type | Suggested Color |
| --- | --- |
| Folder | Brand blue |
| Image | Purple |
| Video | Red-purple or pink |
| Audio | Orange |
| PDF | Red |
| Text & Code | Cyan or secondary |
| Other files | `.secondary` |

---

## 4. Typography & Data Layout

### 4.1 Typography Hierarchy

| Level | SwiftUI Convention | Purpose |
| --- | --- | --- |
| Page titles | `.title2.weight(.bold)` | Dashboard & main page titles |
| Card primary data | `.system(size: 34, weight: .semibold, design: .rounded)` | CPU, memory, temperature, key metrics |
| Card titles | `.headline` | Server cards, metric card titles |
| Body | `.body` | Filenames, primary info |
| Auxiliary text | `.subheadline` | Addresses, paths, descriptions |
| Metadata | `.caption` | File size, modification date, update time |
| Status Badge | `.caption.weight(.semibold)` | Online, warning, offline states |

### 4.2 Data Metrics

Dynamic numbers use tabular numerals to avoid horizontal jumping during updates:

```swift
Text("61%")
    .font(.system(size: 34, weight: .semibold, design: .rounded))
    .monospacedDigit()
```

Suitable for tabular numerals:

- CPU & memory percentages
- Temperature
- Upload & download speeds
- Storage capacity
- Uptime

Titles, server names, buttons, and error descriptions must not force monospaced fonts.

### 4.3 Dynamic Type

- Body and auxiliary text must not use fixed font sizes.
- Metric numbers can have explicit visual sizing, but must allow line-wrapping or layout degradation under accessibility font sizes.
- When fonts are enlarged, Dashboard two-column layout should automatically degrade to single-column.
- File rows must not clip text via fixed heights.

---

## 5. Spacing System

| Token | Value | Purpose |
| --- | --- | --- |
| `xxSmall` | `2pt` | Tight text within a group |
| `xSmall` | `4pt` | Title-to-description, filename-to-metadata |
| `small` | `8pt` | Within icons, tight controls |
| `medium` | `12pt` | Row content & standard components |
| `large` | `16pt` | Page margins & card padding |
| `xLarge` | `24pt` | Large page sections |
| `xxLarge` | `32pt` | Strong grouping & top whitespace |

Suggested implementation:

```swift
enum NasMonSpacing {
    static let xxSmall: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
    static let xxLarge: CGFloat = 32
}
```

---

## 6. Corner Radius, Borders & Shadows

| Token | Value | Purpose |
| --- | --- | --- |
| `control` | `10pt` | Input areas & small controls |
| `card` | `16pt` | Dashboard & server cards |
| `largeCard` | `20pt` | Primary server overview card |
| `capsule` | `Capsule()` | Status badges & short labels |

Rules:

- Establish hierarchy through background layers and dividers first.
- Light mode allows very subtle shadows.
- Dark mode avoids black shadows; use borders or background luminance differences instead.
- File list rows don't use independent heavy shadows.
- Don't mix multiple similar corner radii on the same page.

Modern SwiftUI approach:

```swift
.background(.nasMonSurface)
.clipShape(.rect(cornerRadius: 16))
```

---

## 7. Page Container Rules

Different pages choose containers based on their task; don't force everything to use `.insetGrouped`.

| Page | Recommended Container |
| --- | --- |
| Server selection | `.insetGrouped` or server card list |
| Add & edit server | `Form` |
| File manager | `.plain` List |
| Dashboard | `ScrollView + LazyVGrid` |
| Settings | `.insetGrouped` List or Form |
| PDF, text, images | Content-specific canvas |
| Video & audio | Full-screen immersive container |

---

## 8. Navigation & Toolbar

### 8.1 Navigation Hierarchy

- The navigation bar keeps only the most important actions for the current context.
- Standard back uses system back behavior.
- "Back to server," "back to parent directory," and "go to root" must not all compete for the same Toolbar area.
- Secondary actions go into `Menu`.
- File paths should be displayed as independent navigation info, not crammed entirely into the title.

### 8.2 File Management Guidelines

- Show current server and path at the top.
- Retain "back to parent directory" within each directory.
- Return to shared folder root can go into the path bar or More menu.
- Pull-to-refresh is primary; Toolbar refresh as an optional quick action.
- Long-press file menus can offer preview, share, and file info.

### 8.3 Destructive Actions

- Restart and shutdown must not sit at the same visual level as routine refresh.
- Destructive actions should live in a dedicated "Server Actions" section.
- Confirmation dialogs are mandatory.
- Don't rely on red alone to convey danger; include text and icon descriptions.

---

## 9. Common Components

Suggested directory:

```text
NasMon/DesignSystem/
├── NasMonColors.swift
├── NasMonSpacing.swift
├── NasMonTypography.swift
├── NasMonMetrics.swift
└── Components/
    ├── AppCard.swift
    ├── MetricCard.swift
    ├── StatusBadge.swift
    ├── ServerCard.swift
    ├── FileRow.swift
    ├── PrimaryButton.swift
    └── AppContentState.swift
```

Components are responsible for consistent visuals and basic interaction only; they should not directly own network requests or business state machines.

### 9.1 Dashboard Card

```swift
struct ConsoleCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NasMonSpacing.medium) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NasMonSpacing.large)
        .background(.nasMonSurface)
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}
```

### 9.2 File List Row

File rows should accept a file domain model or dedicated display model, not just `isFolder`.

```swift
struct FileRowView: View {
    let file: DSMFile

    var body: some View {
        HStack(spacing: NasMonSpacing.medium) {
            Image(systemName: file.iconName)
                .font(.title3)
                .foregroundStyle(file.iconColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NasMonSpacing.xSmall) {
                Text(file.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(fileDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: NasMonSpacing.small)

            if file.isdir {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, NasMonSpacing.xSmall)
    }

    private var fileDetail: String {
        file.isdir
            ? "Folder"
            : "\(file.formattedSize) · \(file.formattedModifiedDate)"
    }
}
```

### 9.3 Status Badge

Status badges must combine:

- Icon or shape
- Text label
- Semantic color

Example:

```text
● Online
! Warning
× Offline
```

Never show just a colored dot without an accessibility label.

---

## 10. Dashboard Specification

Dashboard information order:

1. Server identity & connection status
2. Overall server health
3. CPU, memory, & temperature
4. Storage or network metrics
5. Last update time & refresh state
6. Server destructive actions

### 10.1 Recommended Layout

```text
Server Overview Main Card

CPU Metric Card      Memory Metric Card
Temperature Card     Uptime Card

Network or Storage Trend Chart

Last Updated Time

Server Actions
```

Rules:

- Prefer two-column metric cards at regular widths.
- Automatically degrade to single-column on compact widths & accessibility font sizes.
- Charts must not be the sole way to read current values.
- Current values must have textual expressions.
- High-utilization states should also display status labels like "High."

---

## 11. Server Selection & Login

### 11.1 Server Card Contents

Server cards can display:

- Server name
- NAS model
- Address
- Current account
- Online, offline, or connecting status
- Last connection info (when reliable data is available)
- Edit menu

The primary tap action should connect to the server; secondary actions like edit and delete go into menus or swipe actions.

### 11.2 Login Form

- Continue using `Form`; don't build inputs from scratch.
- Can add a top brand icon & short description.
- Input errors display near their relevant fields.
- Disable duplicate submissions during login.
- Password, host, and account fields should have correct keyboards & autofill semantics.
- Primary action uses an explicit confirm button; dismiss follows system behavior.

---

## 12. File Manager

Design goal: high information density, quick scanning, clear hierarchy.

Each file row contains:

- File type icon
- Filename
- File size & modification time, or "Folder" indicator
- Folder navigation chevron

Rules:

- Filenames are the primary visual element.
- Metadata uses `.caption` and `.secondary`.
- Files that can't be previewed must show a reason; no silent unresponsiveness.
- Directories and files use consistent tap areas.
- Tap areas must be at least 44pt.
- In large-file scenarios, don't turn every file into an independent card.

---

## 13. Previews & Players

### 13.1 Preview Chrome

Shared Chrome can include:

- Back
- Filename
- Temporary transfer status
- Share
- Other necessary actions

Rules:

- Chrome visibility changes only affect the chrome frame, not the阅读 position.
- Sharing is unavailable while content is still transferring.
- Distinguish clearly between initial load, progressive content, complete content, and error states.
- Chrome stays visible in error or empty states.

### 13.2 PDF & Text

- PDFs use continuous vertical scrolling.
- Text & code follow system light or dark appearance.
- Text font size responds to dynamic type.
- Current reading position is preserved on content updates & device rotation.
- Line numbers are contextual info, not independent repeated accessibility targets.

### 13.3 Audio Player

- Dynamic gradient as the primary background strategy.
- Use a clear default background when no valid cover color can be extracted.
- Dark controls on lighter backgrounds; light controls on darker backgrounds.
- Material blur only for local Chrome or buttons.
- Progress bar, playback state, and volume controls must have explicit accessibility labels.

### 13.4 Video Player

- Uses a pure-black immersive background.
- Controls auto-hide on inactivity.
- Playback failures, buffering, and loading states need explicit feedback.
- When reduced motion is enabled, controls use fade-in/fade-out only.

---

## 14. Content State Specification

Main pages must account for the following states:

1. Initial
2. Loading
3. Content
4. Empty
5. Error
6. Offline
7. Refreshing
8. Destructive action in progress

### 14.1 Loading

- Use a centered system `ProgressView` for first-time waits.
- Don't overlay full-screen loading on existing content during refreshes.
- Show definite progress when calculable; otherwise use indeterminate progress.

### 14.2 Empty

Empty states should include:

- Icon
- Short title
- Reason description
- Next-step action when meaningful

### 14.3 Error

- Use user-understandable descriptions.
- Offer retry for recoverable errors.
- Don't present raw error codes as the only cue.
- Error colors are emphasis only; meaning must be conveyed by text.

### 14.4 Offline

Offline states should communicate:

- Which server is currently inaccessible
- Whether existing content is still viewable
- What actions the user can take
- Whether reconnection is possible

---

## 15. Animation & Haptic Feedback

- Standard state transitions: `0.2–0.3` second animations.
- Navigation relies on system animations.
- Don't use large scale or bounce animations for data refreshes.
- Lightweight haptic feedback is appropriate for successful connections, important confirmations, etc.
- Destructive action confirmations must not rely on animation for conveyance.

Reduced motion:

```swift
@Environment(\.accessibilityReduceMotion)
private var reduceMotion
```

When reduced motion is enabled:

- Avoid large translations and scales.
- Chrome visibility changes use fade-in/fade-out only.
- Metric updates don't use spring animations.
- Retain necessary loading & progress feedback.

---

## 16. Accessibility

All new UI must be checked for:

- Dynamic Type
- VoiceOver
- Reduce Motion
- Increase Contrast
- Dark mode
- Landscape orientation
- Small devices
- Accessibility font sizes

Rules:

- Tap areas at least `44×44pt`.
- States conveyed through more than color alone.
- Decorative icons use `.accessibilityHidden(true)`.
- Icon buttons must have understandable labels.
- A group of data cards should have a clear accessibility reading order.
- Metrics read out name, value, unit, and state together.
- Contextual elements like line numbers don't create unnecessary repeated focus targets.

---

## 17. Discouraged Design Patterns

- Don't scatter hex colors directly in business Views.
- Don't mix brand color tokens with arbitrary `Color.blue`.
- Don't assign different corner radii and spacing to every page.
- Don't cardify everything.
- Don't force all previews into Dashboard style or dark mode.
- Don't use color as the sole status indicator.
- Don't use heavy shadows in file lists.
- Don't use persistent animations or neon glow for decoration.
- Don't place destructive actions at the same level as routine ones.
- Don't override `preferredColorScheme` arbitrarily inside widgets.
- Don't blank pages with full-screen loading on content refreshes.
- Don't reset PDF or text reading positions for progressive content updates.

---

## 18. Recommended Implementation Order

### Sprint 1: Design Foundation

- Create the Design System directory.
- Establish semantic color Assets.
- Establish spacing, typography, and corner radius tokens.
- Create cards, status badges, and content state components.
- Don't modify business logic yet.

### Sprint 2: Main Framework & File Management

- Unify Tab names & icons.
- Refactor file rows.
- Organize paths & Toolbars.
- Add long-press menus.
- Unify Loading, Empty, and Error states.

### Sprint 3: Dashboard

- Convert setting-style `LabeledContent` to metric cards.
- Add visual expressions for CPU, memory, and temperature.
- Establish server health status.
- Dedicated destructive actions section.

### Sprint 4: Connection Flow

- Build server cards.
- Unify online, offline, and logging-in states.
- Improve login form hierarchy & error feedback.

### Sprint 5: Previews & Media

- Unify Preview Chrome.
- Unify back, share, loading, and error states.
- Retain distinct immersive character per content type.
- Check landscape, dark mode, and accessibility.

---

## 19. Final Style Proportions

NasMon should adopt:

- **70% Native Professional**: Navigation, file management, server management, and login.
- **20% Deep Sea Console**: Dashboard data, server status, and monitoring elements.
- **10% Immersive Dynamic**: Video, audio, and content previews.

Final principle:

> **Unified outer shell, adaptive content surfaces; data clarity over decoration, state feedback over visual flair.**
