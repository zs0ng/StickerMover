#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path


IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".gif", ".webp"}


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def guess_kind(path: Path) -> str | None:
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
    return None


def iter_image_files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return sorted(path for path in root.rglob("*") if path.is_file())


def export_category(
    source_root: Path,
    target_root: Path,
    *,
    preserve_relative_to: Path | None = None,
) -> list[dict[str, object]]:
    if not source_root.exists():
        return []
    target_root.mkdir(parents=True, exist_ok=True)
    manifest: list[dict[str, object]] = []
    for path in iter_image_files(source_root):
        kind = guess_kind(path)
        if kind is None and path.suffix.lower() not in IMAGE_SUFFIXES:
            continue
        if preserve_relative_to is None:
            relative = path.relative_to(source_root)
        else:
            relative = path.relative_to(preserve_relative_to)
        target = target_root / relative
        if kind is not None and target.suffix.lower() not in IMAGE_SUFFIXES:
            target = target.with_name(f"{target.name}.{kind}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        manifest.append(
            {
                "source": str(path),
                "relative_path": str(relative),
                "output": str(target),
                "size": path.stat().st_size,
                "kind": kind or path.suffix.lower().lstrip("."),
                "sha256": file_sha256(path),
            }
        )
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("qq_emoji_dir", type=Path, help="Path to QQ nt_data/Emoji directory")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("test/qq_export"),
        help="Directory where export files are written",
    )
    parser.add_argument(
        "--include-emoji-recv",
        action="store_true",
        help="Also export received emoji cache from emoji-recv",
    )
    parser.add_argument(
        "--include-marketface",
        action="store_true",
        help="Also export downloaded marketface sticker assets",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    qq_root = args.qq_emoji_dir
    output_root = args.output_dir

    if output_root.exists():
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True)

    recv_root = qq_root / "emoji-recv"
    personal_root = qq_root / "personal_emoji"
    marketface_root = qq_root / "marketface"

    personal_ori = export_category(personal_root / "Ori", output_root / "personal_emoji" / "Ori")
    personal_thumb = export_category(personal_root / "Thumb", output_root / "personal_emoji" / "Thumb")

    recv_files: list[dict[str, object]] = []
    recv_ori_only: list[dict[str, object]] = []
    recv_thumb: list[dict[str, object]] = []
    if args.include_emoji_recv:
        recv_files = export_category(
            recv_root,
            output_root / "emoji_recv" / "Ori",
            preserve_relative_to=recv_root,
        )
        recv_ori_only = [item for item in recv_files if "/Ori/" in item["source"]]
        recv_thumb = [item for item in recv_files if "/Thumb/" in item["source"]]

    marketface: list[dict[str, object]] = []
    if args.include_marketface:
        marketface = export_category(
            marketface_root,
            output_root / "marketface",
            preserve_relative_to=marketface_root,
        )

    summary = {
        "qq_root": str(qq_root),
        "export_root": str(output_root),
        "include_emoji_recv": args.include_emoji_recv,
        "include_marketface": args.include_marketface,
        "emoji_recv_total": len(recv_files),
        "emoji_recv_ori_count": len(recv_ori_only),
        "emoji_recv_thumb_count": len(recv_thumb),
        "personal_emoji_ori_count": len(personal_ori),
        "personal_emoji_thumb_count": len(personal_thumb),
        "marketface_count": len(marketface),
    }

    (output_root / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    (output_root / "personal_emoji_ori_manifest.json").write_text(
        json.dumps(personal_ori, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    (output_root / "personal_emoji_thumb_manifest.json").write_text(
        json.dumps(personal_thumb, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    if args.include_emoji_recv:
        (output_root / "emoji_recv_manifest.json").write_text(
            json.dumps(recv_files, indent=2, ensure_ascii=False), encoding="utf-8"
        )
    if args.include_marketface:
        (output_root / "marketface_manifest.json").write_text(
            json.dumps(marketface, indent=2, ensure_ascii=False), encoding="utf-8"
        )


if __name__ == "__main__":
    main()
