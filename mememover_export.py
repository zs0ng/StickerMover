#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import shutil
from pathlib import Path


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def guess_kind(path: Path) -> str:
    with path.open("rb") as handle:
        head = handle.read(32)
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if head.startswith(b"GIF87a") or head.startswith(b"GIF89a"):
        return "gif"
    if head.startswith(b"RIFF") and head[8:12] == b"WEBP":
        return "webp"
    if head.startswith(b"\xff\xd8\xff"):
        return "jpg"
    return "blob"


def collect_strings(value: object, bucket: list[str]) -> None:
    if isinstance(value, str):
        bucket.append(value)
    elif isinstance(value, bytes):
        try:
            bucket.append(value.decode("utf-8"))
        except UnicodeDecodeError:
            pass
    elif isinstance(value, dict):
        for key, item in value.items():
            collect_strings(key, bucket)
            collect_strings(item, bucket)
    elif isinstance(value, list):
        for item in value:
            collect_strings(item, bucket)


def export_files(source_dir: Path, target_dir: Path) -> list[dict[str, object]]:
    target_dir.mkdir(parents=True, exist_ok=True)
    exported: list[dict[str, object]] = []
    for path in sorted(p for p in source_dir.iterdir() if p.is_file()):
        kind = guess_kind(path)
        suffix = "" if kind == "blob" else f".{kind}"
        target = target_dir / f"{path.name}{suffix}"
        shutil.copy2(path, target)
        exported.append(
            {
                "name": path.name,
                "exported_name": target.name,
                "size": path.stat().st_size,
                "kind": kind,
                "sha256": file_sha256(path),
            }
        )
    return exported


def parse_favorites(path: Path) -> dict[str, object]:
    raw = plistlib.load(path.open("rb"))
    strings: list[str] = []
    collect_strings(raw, strings)
    urls = sorted({item for item in strings if item.startswith("http")})
    md5s = sorted(
        {
            item[:32]
            for item in strings
            if len(item) >= 32
            and all(ch in "0123456789abcdef" for ch in item[:32].lower())
        }
    )
    return {
        "favorite_archive": str(path),
        "url_count": len(urls),
        "urls": urls,
        "md5_count": len(md5s),
        "md5s": md5s,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("wechat_stickers_dir", type=Path, help="Path to the WeChat Stickers directory")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("test/mememover_export"),
        help="Directory where export files are written",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    wechat_root = args.wechat_stickers_dir
    output_root = args.output_dir

    if output_root.exists():
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True)

    persistence = export_files(wechat_root / "Persistence", output_root / "Persistence")
    thumbs = export_files(wechat_root / "Thumbs", output_root / "Thumbs")

    favorites = parse_favorites(wechat_root / "fav.archive")
    shutil.copy2(wechat_root / "fav.archive", output_root / "fav.archive")

    summary = {
        "wechat_root": str(wechat_root),
        "export_root": str(output_root),
        "persistence_count": len(persistence),
        "thumb_count": len(thumbs),
        "blob_persistence_count": sum(1 for item in persistence if item["kind"] == "blob"),
        "blob_thumb_count": sum(1 for item in thumbs if item["kind"] == "blob"),
        "favorites": favorites,
    }

    (output_root / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    (output_root / "persistence_manifest.json").write_text(
        json.dumps(persistence, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    (output_root / "thumb_manifest.json").write_text(
        json.dumps(thumbs, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    (output_root / "favorites.json").write_text(json.dumps(favorites, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
