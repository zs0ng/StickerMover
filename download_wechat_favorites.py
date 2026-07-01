#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


HEADERS = {
    "User-Agent": "Mozilla/5.0",
    "Accept": "*/*",
    "Referer": "https://servicewechat.com/",
}

EXT_BY_CONTENT_TYPE = {
    "image/png": ".png",
    "image/gif": ".gif",
    "image/webp": ".webp",
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
}


def extension_for(data: bytes, content_type: str | None) -> str:
    if content_type and content_type in EXT_BY_CONTENT_TYPE:
        return EXT_BY_CONTENT_TYPE[content_type]
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if data.startswith(b"GIF87a") or data.startswith(b"GIF89a"):
        return ".gif"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return ".webp"
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    return ".bin"


def md5_from_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    query = urllib.parse.parse_qs(parsed.query)
    if "m" in query and query["m"]:
        return query["m"][0]
    tail = parsed.path.rstrip("/").split("/")[-2:]
    joined = "".join(tail)
    return joined[:32]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("favorites_json", type=Path, help="Path to favorites.json")
    parser.add_argument("--output-dir", type=Path, default=Path("test/RecoveredFavorites"))
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("test/recovered_favorites_manifest.json"),
        help="Path to output manifest JSON",
    )
    return parser.parse_args()


def load_urls(path: Path) -> list[str]:
    data = json.loads(path.read_text())
    return list(dict.fromkeys(data["urls"]))


def download(url: str) -> tuple[bytes, str | None]:
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=30) as response:
        content_type = response.headers.get_content_type()
        payload = response.read()
        return payload, content_type


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(exist_ok=True)
    results: list[dict[str, object]] = []
    for index, url in enumerate(load_urls(args.favorites_json), start=1):
        item = {"url": url, "index": index, "md5": md5_from_url(url)}
        try:
            payload, content_type = download(url)
            ext = extension_for(payload, content_type)
            target = args.output_dir / f"{item['md5']}{ext}"
            target.write_bytes(payload)
            item.update(
                {
                    "status": "ok",
                    "content_type": content_type,
                    "size": len(payload),
                    "output": str(target),
                }
            )
        except urllib.error.HTTPError as exc:
            item.update({"status": "http_error", "code": exc.code, "reason": str(exc.reason)})
        except Exception as exc:  # noqa: BLE001
            item.update({"status": "error", "reason": str(exc)})
        results.append(item)
        if index % 20 == 0:
            args.manifest.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
        time.sleep(0.15)
    args.manifest.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
