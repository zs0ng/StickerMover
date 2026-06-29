# StickerMover

Export and recover WeChat favorite stickers on macOS.

## What this repo contains

- `mememover_export.py`
  - Scans the local macOS WeChat `Stickers` directory.
  - Exports sticker blobs, thumbs, and metadata manifests.
- `download_wechat_favorites.py`
  - Reads parsed favorite sticker URLs from `favorites.json`.
  - Downloads recoverable stickers back into normal image files.

## What this repo does not contain

- No exported sticker blobs
- No recovered sticker images
- No WeChat favorite URLs
- No local absolute paths from the original machine

## Usage

1. Update the WeChat source paths in the scripts for your machine.
2. Run:

```bash
python3 mememover_export.py
```

3. If `favorites.json` is available and you want to recover image files:

```bash
python3 download_wechat_favorites.py
```

## Notes

- The raw files under WeChat `Stickers/Persistence` are often not directly viewable images.
- Recovery of normal image files may depend on URLs extracted from WeChat metadata.
