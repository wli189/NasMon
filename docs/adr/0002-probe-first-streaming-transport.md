# Probe-First Streaming Transport (File Station primary, WebDAV enhancement)

File Station's `SYNO.FileStation.Download` API does not reliably support HTTP Range requests (it outputs a complete raw stream), which blocks true byte-offset streaming and seeking for both media and progressive previews. We decided to **probe capabilities at runtime** and pick the best available transport per session: **WebDAV Server** (native Range, when the NAS has it enabled and the saved DSM password is available in Keychain) > **File Station with Range** (when the NAS happens to honor it) > **File Station raw stream** (append-only, no byte-offset resume).

## Considered Options
- **File Station API only** — works everywhere the app already works, but no native Range; media seeking degrades to "fake seek" (re-stream from byte 0 and discard the prefix) and cross-restart resume is impossible.
- **WebDAV required** — true Range and native seeking, but depends on the user enabling the WebDAV Server package and on the app holding the DSM password (HTTP Basic auth). Rejected as a hard dependency.
- **Probe-first (chosen)** — File Station stays the primary, zero-config channel; WebDAV is used automatically when detected. Runtime probing keeps the app working on every NAS while unlocking the best experience where possible.

## Consequences
- The app stores the DSM password in Keychain (already done at login via `SessionStorage`) and uses it only to authenticate the WebDAV channel; no new credential UI.
- Streaming code must handle three channel modes; the media data source and resumable cache both branch on the probe result.
- A probe result is cached per login session to avoid probing on every file open.
