#!/usr/bin/env python3
"""Merge shard JSON into ui-results.json.

Shard files are ``results.json`` objects: ``{"shard": 1, "results": {id: {...}}}``.
Screenshots stay as relative paths inside each shard directory. This copies
them next to the merged file and rewrites the paths.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from tellomi_ui_results import classify, load_backlog, load_coverage, merge, write_json


def shard_payloads(directory: Path) -> list[dict]:
    payloads = []
    if not directory.is_dir():
        return payloads
    for path in sorted(directory.glob("*/results.json")) + sorted(directory.glob("results-*.json")):
        payloads.append(json.loads(path.read_text(encoding="utf-8")))
        payloads[-1]["_path"] = path
    return payloads


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--backlog", type=Path, required=True)
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--shards", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    rows = load_backlog(args.backlog)
    coverage = load_coverage(args.sources)
    manifest = classify(rows, coverage)
    raw = shard_payloads(args.shards)
    if not raw:
        print(f"no shard results under {args.shards}", file=sys.stderr)
        return 1
    merged = merge(manifest, raw)
    screenshot_dir = args.out.parent / "screenshots"
    screenshot_dir.mkdir(parents=True, exist_ok=True)
    for payload in raw:
        shard_root = Path(payload["_path"]).parent
        for entry in payload.get("results", {}).values():
            shot = entry.get("screenshot")
            if not shot:
                continue
            source = shard_root / shot
            if not source.is_file():
                continue
            target = screenshot_dir / source.name
            shutil.copyfile(source, target)
    for entry in merged["results"].values():
        shot = entry.get("screenshot")
        if not shot:
            continue
        name = Path(shot).name
        if (screenshot_dir / name).is_file():
            entry["screenshot"] = f"screenshots/{name}"
        else:
            entry["screenshot"] = None
            if entry["status"] != "pass":
                note = "screenshot file was not in the shard artifact"
                entry["error"] = f"{entry['error']}; {note}" if entry.get("error") else note
    merged["backlog_rows"] = len(rows)
    write_json(args.out, merged)
    print(json.dumps(merged["counts"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
