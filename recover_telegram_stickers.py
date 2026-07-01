#!/usr/bin/env python3
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import shutil
from pathlib import Path


PREVIEW_PREFIX = "telegram-cloud-document-size-2-"
DOCUMENT_PREFIX = "telegram-cloud-document-2-"
PREVIEW_SUFFIX = "-m"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("telegram_media_dir", type=Path, help="Path to Telegram postbox/media directory")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("test/telegram_recovered"),
        help="Directory where recovered Telegram stickers are written",
    )
    return parser.parse_args()


def collect_preview_map(media_dir: Path) -> dict[str, Path]:
    previews: dict[str, Path] = {}
    for path in media_dir.iterdir():
        if not path.is_file():
            continue
        name = path.name
        if not name.startswith(PREVIEW_PREFIX) or not name.endswith(PREVIEW_SUFFIX):
            continue
        if name.endswith(("_partial", ".meta")):
            continue
        sticker_id = name.removeprefix(PREVIEW_PREFIX).removesuffix(PREVIEW_SUFFIX)
        previews[sticker_id] = path
    return previews


def recover_document(path: Path) -> bytes | None:
    try:
        payload = gzip.decompress(path.read_bytes())
    except OSError:
        return None
    try:
        parsed = json.loads(payload)
    except json.JSONDecodeError:
        return None
    return payload if parsed.get("tgs") == 1 else None


def main() -> None:
    args = parse_args()
    media_dir = args.telegram_media_dir
    output_dir = args.output_dir
    previews_dir = output_dir / "previews"
    stickers_dir = output_dir / "stickers"

    if output_dir.exists():
        shutil.rmtree(output_dir)
    previews_dir.mkdir(parents=True, exist_ok=True)
    stickers_dir.mkdir(parents=True, exist_ok=True)

    preview_map = collect_preview_map(media_dir)
    results: list[dict[str, object]] = []
    seen_hashes: set[str] = set()

    for path in sorted(media_dir.iterdir()):
        if not path.is_file():
            continue
        name = path.name
        if not name.startswith(DOCUMENT_PREFIX):
            continue
        if name.endswith(("_partial", ".meta")):
            continue

        sticker_id = name.removeprefix(DOCUMENT_PREFIX)
        payload = recover_document(path)
        if payload is None:
            continue

        digest = sha256_bytes(payload)
        if digest in seen_hashes:
            continue
        seen_hashes.add(digest)

        sticker_target = stickers_dir / f"{digest}.tgs"
        sticker_target.write_bytes(payload)

        preview_source = preview_map.get(sticker_id)
        preview_target: Path | None = None
        if preview_source is not None:
            preview_target = previews_dir / f"{digest}.webp"
            shutil.copy2(preview_source, preview_target)

        results.append(
            {
                "sticker_id": sticker_id,
                "sha256": digest,
                "source": str(path),
                "preview_source": str(preview_source) if preview_source else None,
                "sticker_output": str(sticker_target),
                "preview_output": str(preview_target) if preview_target else None,
                "size": len(payload),
            }
        )

    manifest = {
        "telegram_media_dir": str(media_dir),
        "output_dir": str(output_dir),
        "recovered_count": len(results),
        "items": results,
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
