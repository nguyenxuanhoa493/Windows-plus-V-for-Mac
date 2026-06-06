# CursorKit

[English](README.md) · [Tiếng Việt](README.vi.md) · [Changelog](CHANGELOG.md)

**CursorKit** is a macOS menu-bar utility that keeps your most-used tools within cursor reach: clipboard history, copied files/images, JSON/Excel conversion, and 2FA OTP codes.

![CursorKit UI](demo/main.png)

## Highlights

- **Opens at your cursor**: use the hotkey and the popup appears where you are working.
- **Fast paste**: select an item to paste, or use `⌘1` to `⌘9` for quick paste.
- **Multi-format history**: text, RTF/HTML, images, files, folders, URLs, and spreadsheet-like data.
- **Smart search**: matches content, filenames, and source apps; diacritic-insensitive.
- **Filters**: All, Text, Images, Files, Bookmarks, and OTP.
- **Item management**: pin, bookmark, delete, clear by type, drag files/images into other apps.
- **Data tools**: inspect JSON, convert JSON to table, export `.xlsx`, convert tables back to JSON.
- **Built-in OTP manager**: PIN/Touch ID unlock, encrypted import/export, and automatic backups.
- **Custom UI**: themes, fonts, font size, visual effects, native list mode, popup position.
- **Auto-update**: checks GitHub Releases and installs verified updates.

## Requirements

- macOS 12.0 Monterey or later
- Apple Silicon or Intel Mac
- Accessibility permission for auto-paste and cursor-positioned popup behavior

## Install

1. Download `CursorKit-4.0.dmg` from [Releases](https://github.com/nguyenxuanhoa493/Windows-plus-V-for-Mac/releases).
2. Open the DMG and drag **CursorKit** into **Applications**.
3. If macOS blocks the unsigned app, remove quarantine once:

   ```bash
   xattr -cr /Applications/CursorKit.app
   ```

4. Launch CursorKit.
5. Grant Accessibility permission:

   `System Settings → Privacy & Security → Accessibility → CursorKit`

6. Restart the app if macOS asks.

![Accessibility permission](demo/image_2.png)

## Quick Use

| Action | Shortcut / gesture |
| --- | --- |
| Open popup | `⌃V` |
| Move selection | `↑` / `↓` |
| Paste selected item | `Enter` |
| Quick paste by number | `⌘1` to `⌘9` |
| Close popup | `Esc` |
| Search | Type while the popup is open |
| Item menu | Right-click an item |
| Drag out file/image | Drag an item into Finder or another app |

The main hotkey can be changed in **Settings → General**.

## Privacy

- Clipboard history is stored locally on your Mac.
- Clipboard images are stored in a local cache instead of being kept in memory.
- Clipboard history is not encrypted, so avoid keeping passwords or sensitive secrets in history.
- OTP data is stored locally and gated by the app lock; OTP backup files are encrypted with your chosen PIN/password.

## Build

```bash
swift build
```

Create the universal ad-hoc signed app bundle:

```bash
./create_app.sh
```

Create release artifacts:

```bash
./build_all.sh
```

Main outputs:

- `CursorKit.app`
- `CursorKit-4.0.dmg`
- `CursorKit-binary.zip`

## Screenshots To Add

Useful README screenshots:

- `demo/main.png`: CursorKit popup near the cursor
- `demo/settings.png`: Settings with popup position/theme controls
- `demo/otp.png`: unlocked OTP tab
- `demo/json-excel.png`: JSON/table/Excel conversion flow
- `demo/permission.png`: Accessibility permission guide

## Contact

- GitHub: [nguyenxuanhoa493/Windows-plus-V-for-Mac](https://github.com/nguyenxuanhoa493/Windows-plus-V-for-Mac)
- Telegram: [@xuanhoa493](https://t.me/xuanhoa493)
- Email: nguyenxuanhoa493@gmail.com

If CursorKit helps you, consider [buying me a coffee](Sources/Resources/cafe.jpg).
