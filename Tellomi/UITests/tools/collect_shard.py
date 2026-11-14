#!/usr/bin/env python3
"""Turn one shard's xcodebuild logs into results.json.

Each test log is ``<test>.log`` next to ``<test>.png``. Coverage arrays in
the Swift sources say which backlog ids that test owns. A line
``TELLOMI_UI_RESULT <id> <status> <error>`` wins. An id the test owns but
did not print becomes fail when xcodebuild failed, otherwise blocked.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from tellomi_ui_results import load_coverage, parse_result_log


def test_failed(log: str) -> bool:
    return "** TEST FAILED **" in log or " failed (" in log and "** TEST EXECUTE SUCCEEDED **" not in log


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--logs", type=Path, required=True)
    parser.add_argument("--shard", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    coverage = load_coverage(args.sources)
    # Array names are not test selectors. The log names are Class/method
    # with the slash turned into "__". Map by reading each log's printed ids.
    results: dict[str, dict] = {}
    for log_path in sorted(args.logs.glob("*.log")):
        text = log_path.read_text(encoding="utf-8", errors="replace")
        parsed = parse_result_log(text)
        screenshot = f"screenshots/{log_path.stem}.png"
        shot_path = args.logs.parent / screenshot
        if not shot_path.is_file():
            screenshot = None
        failed = test_failed(text)
        for backlog_id, report in parsed.items():
            results[backlog_id] = {
                "status": report["status"],
                "test": log_path.stem.replace("__", "/"),
                "screenshot": screenshot,
                "error": report["error"] or None,
            }
        if failed and not parsed:
            results[f"shard-{args.shard}-{log_path.stem}"] = {
                "status": "fail",
                "test": log_path.stem.replace("__", "/"),
                "screenshot": screenshot,
                "error": "xcodebuild failed before any backlog id was reported",
            }
    # Drop synthetic keys that are not backlog ids. The merge rejects them.
    results = {key: value for key, value in results.items() if key.startswith("I-")}
    if failed_without_ids(args.logs) and not results:
        print("shard produced no backlog ids", file=sys.stderr)
    payload = {"shard": args.shard, "results": results, "coverage_arrays": sorted(coverage)}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"reported {len(results)} ids")
    return 0


def failed_without_ids(logs: Path) -> bool:
    return any(test_failed(path.read_text(encoding="utf-8", errors="replace")) for path in logs.glob("*.log"))


if __name__ == "__main__":
    raise SystemExit(main())
