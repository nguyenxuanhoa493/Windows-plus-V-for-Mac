# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A macOS menu-bar clipboard history manager ("Windows + V For Mac"), written in Swift / SwiftUI / AppKit, distributed as an unsigned `.app` bundle via GitHub releases. Bundle id: `com.xuanhoa.cursorkit`. Minimum macOS 12.

Two third-party SwiftPM deps (see `Package.swift`):
- `HotKey` — global hotkey (default `⌃V`)
- `libxlsxwriter` — native XLSX export (linked via SwiftPM, not Homebrew)

The README (in Vietnamese) is the user-facing doc; comments and `print("DEBUG: …")` logs throughout the source are also Vietnamese — keep that style when editing.

## Build & run

`version.sh` defines `VERSION` and `BUILD_NUMBER`; bump both before cutting a release. All build scripts `source` it.

| Task | Command |
|---|---|
| Dev run (no bundle, no signing, no permissions reset) | `./run_debug.sh` |
| Clean rebuild + run debug binary | `./run.sh` |
| Fast iterate on an already-built `CursorKit.app` (binary swap, **does not re-sign**) | `./build_fast.sh` |
| Full Universal app bundle (arm64 + x86_64, ad-hoc signed) | `./create_app.sh` |
| Bundle + zip for GitHub release asset (`CursorKit-binary.zip`) | `./build_release.sh` |
| Build DMG installer (`CursorKit-${VERSION}.dmg`) | `./build_dmg.sh` |
| Single-arch swift build | `swift build` / `swift build -c release --arch arm64` |

There is **no test target** — `swift test` will do nothing useful.

### Signing & TCC gotcha

`create_app.sh` ad-hoc signs (`codesign --force --deep --sign - --entitlements Clipboard.entitlements`). This is required so macOS TCC tracks the app by `BundleIdentifier` instead of CDHash — without it, every rebuild invalidates Accessibility permission and the user has to re-grant.

`build_fast.sh` swaps just the binary inside the existing bundle and **deliberately does not re-sign**, preserving granted permissions. If you change resources, `Info.plist`, or entitlements, you must use `create_app.sh` instead.

When debugging permission-related issues, prefer `run_debug.sh` — it runs from `.build/debug/` with no signing involved.

## Architecture

Single SwiftPM target at `Sources/`. `LSUIElement` is true: no Dock icon, only a status-bar item.

### Singletons

State lives in three globals; treat them as the source of truth and don't introduce parallel stores.

- **`ClipboardManager.shared`** — polls `NSPasteboard.general` every 0.5s via `Timer` on the main runloop. On change, classifies the new content (file URLs first, then text+RTF/HTML, then image last) and prepends a `ClipboardItem`. Persists the full array as JSON in `UserDefaults` under key `clipboardHistory`, with a 0.3s debounced `DispatchWorkItem` (`saveHistory`). Image bytes are written to `~/Library/Caches/ClipboardImages/<UUID>.tiff` and only the filename is stored in the item — keep RAM small. `getHistory()` is sorted-cached; any mutation must call `invalidateSortCache()` (already wired through `saveHistory`). `ignoreNextChange()` is the standard way to suppress the round-trip when the app pastes its own item.
- **`Settings.shared`** — `ObservableObject` mirroring all prefs to `UserDefaults` via `didSet`. Posts `.shortcutChanged` / `.languageChanged` so `AppDelegate` re-binds the `HotKey` and rebuilds the status menu without a restart.
- **`UpdateManager.shared`** — checks `https://api.github.com/repos/nguyenxuanhoa493/Windown-plus-V-for-Mac/releases/latest` (note the legacy typo `Windown` in the repo URL — must match the actual GitHub repo, do not "correct" it). Auto-update replaces the entire `.app` bundle (via `mv` swap, NOT a partial in-place file swap) so the ad-hoc signature from the new bundle stays intact and TCC keeps tracking via `BundleIdentifier` — granted Accessibility permission survives the update. **Never `rm -rf _CodeSignature`** during update: an unsigned bundle falls back to CDHash tracking, which changes every build and revokes permission. Reads `CFBundleShortVersionString` from the live `Info.plist` rather than `Bundle.main.infoDictionary` so an updated bundle reports the new version without restart.

### App lifecycle

`ClipboardApp` (`@main`) immediately hides its `WindowGroup` window and switches to `.accessory` activation policy. `AppDelegate.applicationDidFinishLaunching`:
1. Checks `AXIsProcessTrusted()` — if false, shows `AccessibilityPermissionWindow`. Auto-paste needs this; without it the app still records history but can't synthesize ⌘V.
2. Starts `ClipboardManager` polling, builds the status-bar `NSMenu`, registers the `HotKey`.
3. After 3s, kicks off a silent `UpdateManager.checkForUpdates(silent: true)` if `autoCheckForUpdates`.

The history popup is an `NSPanel` (`.popUpMenu` level, `.nonactivatingPanel`, `isFloatingPanel`) anchored at the cursor. It's recreated on each open; a global `NSEvent` mouse monitor closes it when the user clicks elsewhere. Item selection in the popup performs paste in two stages: close panel → `asyncAfter 0.15s` → `ignoreNextChange()` + `item.paste()` → `asyncAfter 0.3s` → `moveToTop`. The delays let the previously-active app regain focus before the synthesized keystroke fires; tweaking them risks pasting into the wrong window.

### `ClipboardItem`

Codable struct, three variants distinguished by `type` (`.text` / `.image` / `.file`). Caches `cachedIsJSON` and `cachedIsExcelData` at insert time so list rendering doesn't re-parse on every redraw. `paste()` lives on `ClipboardItem` and is what actually pushes to pasteboard + synthesizes ⌘V via `CGEvent`.

History size cap (`Settings.maxHistoryItems`, default 50) is enforced by `removeOldestNonBookmarkedIfNeeded`: pinned and bookmarked items are protected and never auto-evicted, even if total exceeds the cap.

### Localization

`Localization.shared` is a custom dictionary-based system (Vietnamese / English) — not `Localizable.strings`. Strings are looked up via `Localization.shared.localizedString("key")`. Switching language posts `.languageChanged`.

## Conventions

- All build scripts `source version.sh`. Bumping a release means editing that file once.
- The `.gitignore` excludes `*.sh` — scripts are tracked individually with `git add -f` only when intentional. Don't blanket-add new shell scripts.
- Universal binary is mandatory for releases: build both `--arch arm64` and `--arch x86_64`, then `lipo -create`. Single-arch builds are dev-only.
- Don't add a Dock icon, don't change `LSUIElement`, don't switch off `.accessory` activation — the menu-bar-only behavior is core UX.
- Vietnamese debug logs (`print("DEBUG: …")`) are intentional. Don't translate them or strip them in cleanup passes.
