"""Classify the Tellomi iOS backlog and merge shard UI results.

The CSV is the backlog. Swift ``Coverage`` arrays are the ids an XCUITest
actually checks. Everything else is ``blocked`` or ``device_only``.
"""

from __future__ import annotations

import csv
import json
import re
from pathlib import Path

STATUSES = ("pass", "fail", "blocked", "device_only")

# NSLog / print line emitted by TellomiUILog.
RESULT_RE = re.compile(
    r"TELLOMI_UI_RESULT\t([A-Za-z0-9_-]+)\t(pass|fail|blocked|device_only)\t(.*)$"
)

COVERAGE_RE = re.compile(
    r"static let (\w+): \[String\] = \[([\s\S]*?)\]",
    re.MULTILINE,
)
ID_RE = re.compile(r'"(I-[A-Z0-9-]+)"')


def load_backlog(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise SystemExit(f"backlog is empty: {path}")
    required = {"id", "区域", "界面/入口", "元素", "预期", "优先级"}
    missing = required - set(rows[0])
    if missing:
        raise SystemExit(f"backlog missing columns: {sorted(missing)}")
    return rows


def load_coverage(sources: Path) -> dict[str, list[str]]:
    """Map ``Type/method`` is not known here. Map Swift array name to ids."""
    coverage: dict[str, list[str]] = {}
    for path in sorted(sources.glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for match in COVERAGE_RE.finditer(text):
            name = match.group(1)
            ids = ID_RE.findall(match.group(2))
            if name in coverage:
                raise SystemExit(f"duplicate coverage array {name}")
            coverage[name] = ids
    if not coverage:
        raise SystemExit(f"no Coverage arrays under {sources}")
    return coverage


def test_phone_code(digits: str) -> str | None:
    """Code for the server's default test range.

    teamgram-server ``pkg/phonenumber/test_phone.go``: prefix ``99966``,
    length 10, code is the next digit repeated five times.
    ``99966170xx`` therefore uses ``11111``. ``12345`` is the dev SMS
    provider code and is not accepted for this range.
    """
    if len(digits) == 10 and digits.startswith("99966") and digits[5].isdigit():
        return digits[5] * 5
    return None


def _blob(row: dict[str, str]) -> str:
    return " ".join(
        (
            row.get("区域", ""),
            row.get("界面/入口", ""),
            row.get("元素", ""),
            row.get("预期", ""),
        )
    )


def device_only_reason(row: dict[str, str]) -> str | None:
    """Push, camera, mic, Siri, Face ID, and calls need a device.

    The calls-tab *toggle* in Settings is a simulator control and stays out
    of this set. Photo-library and location prompts are not in this set.
    """
    area = row.get("区域", "")
    element = row.get("元素", "")
    screen = row.get("界面/入口", "")
    # The element and the screen name, not the whole expected paragraph.
    # A settings sentence that mentions Siri or push must not swallow the row.
    focus = f"{element} {screen}"
    if area == "Notifications":
        return "push notification UI needs a device"
    if any(token in focus for token in ("Siri", "Face ID", "Touch ID", "面容", "指纹")):
        return "Face ID / Siri needs a device"
    if any(token in focus for token in ("麦克风", "Microphone", "听写")):
        return "microphone needs a device"
    if any(token in focus for token in ("相机", "摄像头", "拍照", "自拍")):
        return "camera needs a device"
    # A settings row that only shows or hides the Calls tab is not a call.
    if "【toggle】通话" in element and "导航栏" in screen:
        return None
    if any(token in focus for token in ("视频通话", "语音通话", "来电", "CallKit", "VoIP")):
        return "calls need a device"
    if "推送横幅" in screen or (area == "Notifications" and "推送" in element):
        return "push notification UI needs a device"
    return None


def blocked_reason(row: dict[str, str]) -> str:
    blob = _blob(row)
    element = row.get("元素", "")
    if any(token in element for token in ("【alert】", "【permission】")):
        return "needs a system alert or a server error this run cannot force"
    if any(token in blob for token in ("验证码已过期", "尝试次数过多", "发生错误", "密码错误", "封禁")):
        return "needs a specific server error"
    if row.get("区域") in ("Discover", "MOMENTS") and "底栏" in row.get("界面/入口", ""):
        return "needs a logged-in Discover session and feed content"
    if row.get("区域") in ("Chat", "Composer", "AI", "Translation", "Stickers", "Media"):
        return "needs a logged-in chat; AI compose switches are not changed"
    if row.get("区域") in ("Premium",):
        return "premium entry is behind a logged-in screen this run does not open"
    if row.get("区域") in ("DeepLinks",):
        return "needs a logged-in peer or an installed universal link"
    if row.get("区域") in ("Settings", "SETTINGS", "Privacy", "Profile", "Contacts", "CONTACTS"):
        return "needs a logged-in settings screen this run does not open"
    if row.get("区域") in ("Login", "LOGIN"):
        return "needs a login state this run does not reach"
    return "not covered by a simulator check in this run"


def classify(rows: list[dict[str, str]], coverage: dict[str, list[str]]) -> dict[str, dict]:
    automated: dict[str, str] = {}
    for name, ids in coverage.items():
        for backlog_id in ids:
            if backlog_id in automated:
                raise SystemExit(f"{backlog_id} is in both {automated[backlog_id]} and {name}")
            automated[backlog_id] = name
    known = {row["id"] for row in rows}
    unknown = sorted(set(automated) - known)
    if unknown:
        raise SystemExit(f"coverage ids missing from the backlog: {unknown}")
    manifest: dict[str, dict] = {}
    for row in rows:
        backlog_id = row["id"]
        reason = device_only_reason(row)
        if reason is not None:
            if backlog_id in automated:
                raise SystemExit(f"{backlog_id} is device_only and also covered by {automated[backlog_id]}")
            manifest[backlog_id] = {
                "status": "device_only",
                "area": row["区域"],
                "priority": row["优先级"],
                "test": None,
                "reason": reason,
            }
            continue
        if backlog_id in automated:
            manifest[backlog_id] = {
                "status": "automated",
                "area": row["区域"],
                "priority": row["优先级"],
                "test": automated[backlog_id],
                "reason": None,
            }
            continue
        manifest[backlog_id] = {
            "status": "blocked",
            "area": row["区域"],
            "priority": row["优先级"],
            "test": None,
            "reason": blocked_reason(row),
        }
    if len(manifest) != len(rows):
        raise SystemExit("manifest dropped a row")
    return manifest


def parse_result_log(text: str) -> dict[str, dict[str, str]]:
    found: dict[str, dict[str, str]] = {}
    for line in text.splitlines():
        match = RESULT_RE.search(line)
        if not match:
            continue
        backlog_id, status, error = match.groups()
        found[backlog_id] = {"status": status, "error": error.strip()}
    return found


def merge(
    manifest: dict[str, dict],
    shard_results: list[dict],
) -> dict:
    """Overlay shard reports onto the manifest.

    ``device_only`` is never overwritten. An automated id with no report
    stays blocked. A shard cannot invent an id.
    """
    results: dict[str, dict] = {}
    for backlog_id, entry in manifest.items():
        if entry["status"] == "automated":
            results[backlog_id] = {
                "status": "blocked",
                "test": entry["test"],
                "screenshot": None,
                "error": "test did not report this id",
            }
        else:
            results[backlog_id] = {
                "status": entry["status"],
                "test": entry.get("test"),
                "screenshot": None,
                "error": entry.get("reason"),
            }
    for shard in shard_results:
        for backlog_id, report in shard.get("results", {}).items():
            if backlog_id not in results:
                raise SystemExit(f"shard reported unknown id {backlog_id}")
            if manifest[backlog_id]["status"] == "device_only":
                raise SystemExit(f"shard reported device_only id {backlog_id}")
            status = report.get("status")
            if status not in ("pass", "fail", "blocked"):
                raise SystemExit(f"{backlog_id} has status {status!r}")
            results[backlog_id] = {
                "status": status,
                "test": report.get("test") or manifest[backlog_id].get("test"),
                "screenshot": report.get("screenshot"),
                "error": report.get("error"),
            }
    counts = {status: 0 for status in STATUSES}
    for entry in results.values():
        counts[entry["status"]] += 1
    if sum(counts.values()) != len(manifest):
        raise SystemExit("merged count does not match the backlog")
    return {"counts": counts, "results": results}


def counts_by_status(manifest: dict[str, dict]) -> dict[str, int]:
    counts = {"automated": 0, "blocked": 0, "device_only": 0}
    for entry in manifest.values():
        counts[entry["status"]] += 1
    return counts


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
