# Progressive Non-Media Previews with a Resumable Cache

Non-media previews (image / pdf / text) previously downloaded the whole file before showing anything. We decided to render them **progressively**: show data as it arrives (progressive-JPEG decoding, first PDF pages, appending text), backed by a **resumable on-disk cache** in `PreviewCache/` that records a metadata sidecar (expected size, downloaded bytes, completion flag) and enforces a 1 GB total quota with LRU eviction plus per-file caps (200 MB non-media / 2 GB media). QuickLook surfaces are exempt — `QLPreviewController` requires a complete local file, so they stay download-then-preview.

## Considered Options
- **Progress-bar-while-downloading** — simpler, but only changes the loading UI; it is not streaming under our `CONTEXT.md` definition. Rejected.
- **In-memory-only streaming** — no reuse across opens and no resume; rejected because the preview cache already exists and hash naming makes resumable entries cheap.
- **Progressive + resumable cache (chosen)** — matches the defined term "Streaming Preview".

## Consequences
- Byte-offset resume is only honored when the active transport supports Range (see ADR-0002); on a raw File Station stream a failed download restarts from byte 0, per the confirmed resume contract.
- Views must tolerate a growing partial file: text reloads incrementally, images use `CGImageSource` incremental decoding, PDFKit re-opens the document as bytes arrive, and QuickLook waits for completion.
- In-progress cache entries are protected from LRU eviction while being written.
