# NasMon — Streaming File Previews

NasMon is an iOS app for managing Synology NAS devices. The current version supports Dashboard monitoring, file management, video and audio playback, and file previews. This context defines the domain model and architectural decisions for preview streaming.

## Language

**Preview Category**:
A classification for how a NAS file is displayed in preview. Values include `image`, `pdf`, `text`, `video`, `audio`, `quickLook`, and `unsupported`.
_Avoid_: preview type, file category

**Preview Manager**:
The coordination layer responsible for obtaining a local copy of a previewable file. Its responsibilities are cache lookup → fetch → return local URL. It does not manage UI state or choose the Preview Surface.
_Avoid_: download manager, file fetcher

**Preview Cache**:
A local file cache stored in `Caches/PreviewCache/`, mapped through a stable hash of the file path.

**File Station Download API**:
The Synology DSM `/webapi/entry.cgi` endpoint using the `SYNO.FileStation.Download` API with `mode=download` to retrieve file content from the NAS.
_Avoid_: download endpoint

**WebDAV Server**:
A WebDAV service on the Synology NAS that supports native HTTP Range requests and can serve as a Transport Channel for retrieving file bytes.

**Transport Channel**:
A channel for retrieving file bytes. The File Station Download API is the primary channel; the WebDAV Server is an optional enhanced channel.
_Avoid_: download method, fetcher

**Preview Surface**:
The UI boundary that renders acquired preview content and owns its display, scrolling, and interaction behavior—for example, an image viewer, PDFKit, Runestone, or Quick Look. It does not acquire, transfer, or cache files.
_Avoid_: previewer, preview UI

**Preview Chrome**:
The shared navigation and action interface surrounding a Preview Surface. PDF and Code Preview enter through a full-screen cover and use an explicit back action to exit; file acquisition does not participate in presentation decisions.
_Avoid_: preview toolbar, modal preview

**Immersive Preview**:
A user can tap a Preview Surface to show or hide Preview Chrome. Toggling changes only the visibility of the interface chrome; it does not alter or jump the current reading position.
_Avoid_: scroll-triggered chrome, permanently visible chrome

**Preview Session**:
The continuous reading period from opening one file preview from the file list until returning to the file list. The reading position remains stable across Chrome toggles, viewport changes, and progressive refreshes during this period; reopening after exit does not promise position restoration.
_Avoid_: persisted reading history, cross-session resume

**Preview Interaction Priority**:
Semantic interactions in a Preview Surface take priority over toggling Preview Chrome: PDF links and annotations, text selection, zooming, dragging, and scrolling are handled first. Only taps not consumed by content toggle Chrome.
_Avoid_: global tap interception, gesture-triggered chrome toggle

**Preview Viewport**:
The visible area available for reading content on the current device and orientation after Preview Chrome and system areas are excluded. Its bounds must adapt to device and window changes rather than being defined with fixed portrait or landscape constants.
_Avoid_: fixed top inset, orientation constant

**Preview Scroll Clearance**:
A Preview Surface background may extend to the screen edges, but the beginning and end of a document must scroll beyond system-obscured areas and become fully visible. The clearance belongs to the scrollable range rather than document content, adapts to the actual Preview Viewport, and does not change the reading position when Chrome is hidden.
_Avoid_: permanent safe-area strip, fixed scroll padding, document-owned spacer

**Code Preview**:
A read-only source-code browsing experience within the Text Preview Surface. It retains VS Code-like line numbers, syntax highlighting, text selection, and copying, but does not provide editing or degrade into plain document typography.
_Avoid_: plain-text document preview, text editor

**Adaptive Preview Appearance**:
Preview Chrome and Code Preview follow the system light or dark appearance, with the code canvas, line numbers, and syntax colors switching as one theme. The PDF canvas follows the system appearance but does not rewrite the PDF page’s own colors.
_Avoid_: forced-dark code preview, preview-specific theme preference

**Accessible Preview**:
File information, transfer status, and actions in Preview Chrome have explicit accessibility semantics. Code Preview follows system text sizing, including accessibility sizes; when it reflows, it preserves the source position, and line numbers provide context instead of becoming repeated independent focus targets. With Reduce Motion enabled, Chrome state changes do not use translation or scale. PDFs retain their native document accessibility support.
_Avoid_: fixed code font size, unlabeled preview action, individually focused line number, mandatory motion

**Wrapped Code Preview**:
Source lines wider than the Preview Viewport soft-wrap for the current viewport; horizontal scrolling is not provided. All visual lines belonging to one source line share that source line number. The source position remains stable while rewrapping for viewport changes.
_Avoid_: horizontal code scrolling, fixed-width code canvas

**Continuous Document Preview**:
PDF pages are arranged in a continuous vertical, single-page-width flow with the same reading direction in portrait and landscape, and support zooming. Viewport changes should preserve the current page and in-page reading position.
_Avoid_: horizontal paging, orientation-dependent paging

**Preview Transfer Status**:
A temporary status displayed alongside the filename in Preview Chrome while preview content is still arriving. It shows determinate progress when the total is known and indeterminate progress otherwise. It hides with Preview Chrome and disappears when transfer completes.
_Avoid_: content-overlay progress bar, persistent download banner

**Preview Share**:
Exports a fully acquired local preview file through the system share sheet. It is unavailable while content is still arriving and does not start a separate fetch flow just to share.
_Avoid_: partial-file share, preview-specific download

**Preview Content State**:
Explicit feedback when a Preview Surface cannot yet render content or cannot render it at all. Initial waiting uses a centered system loading indicator; once progressive content can render, Preview Transfer Status continues the feedback. Empty files, undecodable text, and corrupted PDFs use centered explanation and an available retry action; Preview Chrome remains visible in these states.
_Avoid_: blank loading canvas, silent failure, chrome-hidden error

**Streaming Preview**:
A mechanism that displays all or part of a file without waiting for the full download, as opposed to the current “download completely, then display” model.
_Avoid_: partial download, chunk loading

**Progressive Rendering**:
A non-media rendering mode in which content displays as data arrives—for example, a PDF first page appears early, text can be browsed while downloading, or an image appears during download.
_Avoid_: incremental loading, streaming UI

**Stable Progressive Reading**:
When progressive content refreshes, the Preview Surface preserves the current source or PDF in-page position. Newly received bytes do not trigger automatic scrolling, even when the user had been at the end of received content. A preview is a document-reading experience, not a real-time log follower.
_Avoid_: tail-following preview, progress-triggered scroll, refresh-to-top

**Last Valid Preview**:
The content state used when a progressive file is temporarily unparsable. Before the first successful render it retains loading feedback; after a successful render, later temporary parsing failures retain the most recent valid content and wait for more bytes. It becomes an error only when the complete file still cannot render.
_Avoid_: transient corruption error, blank-on-refresh, partial-file failure

**Resumable Cache**:
A Preview Cache entry that persists received file bytes and can continue fetching from its previous position.
_Avoid_: partial file, chunk cache

**Byte-Offset Resume**:
The ability to continue fetching from the byte offset at which a previous transfer stopped, dependent on Range support from the Transport Channel.
_Avoid_: true resume, range resume

**Session Resume**:
The ability to pause and resume a download task within the same Preview Session. Continuation across an app restart is not guaranteed.
_Avoid_: task resume

**Fake Seek**:
A positioning mechanism for Transport Channels without Range support: it streams again from the beginning and discards prefix bytes to advance to the target byte offset.
_Avoid_: simulated seek, seek workaround
