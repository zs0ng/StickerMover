# StickerMover

Export local WeChat and QQ stickers on macOS.

## What this repo contains

- `mememover_export.py`
  - Scans the local macOS WeChat `Stickers` directory.
  - Exports sticker blobs, thumbs, and metadata manifests.
- `download_wechat_favorites.py`
  - Reads parsed favorite sticker URLs from `favorites.json`.
  - Downloads recoverable stickers back into normal image files.
- `qq_sticker_export.py`
  - Scans the local macOS QQ `nt_data/Emoji` directory.
  - Exports `personal_emoji` by default.
  - Can optionally export `emoji-recv` and `marketface`.
- `macos/StickerVault`
  - A minimal macOS menu bar app MVP.
  - Auto-detects local QQ and WeChat sticker folders.
  - Shows separate QQ and WeChat tabs in a menu bar window.
  - Copies a sticker to the clipboard on click.

## What this repo does not contain

- No exported sticker blobs
- No recovered sticker images
- No WeChat favorite URLs
- No local absolute paths from the original machine

## Usage

1. Run the WeChat export:

```bash
python3 mememover_export.py /path/to/Stickers
```

2. If `favorites.json` is available and you want to recover image files:

```bash
python3 download_wechat_favorites.py test/mememover_export/favorites.json
```

3. Run the QQ export:

```bash
python3 qq_sticker_export.py /path/to/QQ/nt_data/Emoji
```

4. If you also want QQ cache folders:

```bash
python3 qq_sticker_export.py /path/to/QQ/nt_data/Emoji --include-emoji-recv --include-marketface
```

5. Run the macOS menu bar MVP:

```bash
cd macos/StickerVault
swift run
```

Then:

- Click the menu bar icon
- Wait for local QQ / WeChat folders to be scanned automatically
- Switch between the `QQ` and `WeChat` tabs
- Click a sticker to copy it to the clipboard
- Paste it into chat apps with `Cmd + V`

Current auto-detected sources:

- QQ: `~/Library/Application Support/QQ/nt_qq_*/nt_data/Emoji/personal_emoji/Ori`
- WeChat source: `~/Library/Containers/com.tencent.xinWeChat/.../Stickers`

Current behavior:

- QQ is read directly from the local QQ personal emoji folder.
- WeChat is recovered automatically from the local WeChat `Stickers` directory into `~/Library/Application Support/StickerVault/Recovered/WeChat`, then deduplicated into the app's own normalized cache for display.

By default, generated files are written under `test/`, with WeChat and QQ outputs separated into different subdirectories.

## Notes

- The raw files under WeChat `Stickers/Persistence` are often not directly viewable images.
- Recovery of normal image files may depend on URLs extracted from WeChat metadata.
- QQ export defaults to `personal_emoji`, which is the closest local folder to your own collected sticker set.
- `emoji-recv` and `marketface` are optional because they are mostly cache or downloaded pack assets.
