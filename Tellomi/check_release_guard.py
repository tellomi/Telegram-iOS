#!/usr/bin/env python3
"""Reject a pull request into release/ios that drops Moments, lowers the
marketing version, comes from master, or replaces the tree with master's.

    python3 Tellomi/check_release_guard.py --self-test
    python3 Tellomi/check_release_guard.py \
        --base <base-sha> --head <head-sha> --head-ref <branch> \
        --master-tree <origin/master tree sha>

The GitHub check that runs this is the job named release-guard.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys

MOMENTS_DIRECTORIES = (
    "submodules/TelegramUI/Components/Moments",
    "submodules/TelegramCore/Sources/TelegramEngine/Moments",
)


def fail(message: str) -> None:
    print(f"::error::{message}")
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def version_key(text: str) -> tuple[int, ...]:
    text = text.strip()
    if not text:
        raise ValueError("empty version")
    parts: list[int] = []
    for piece in text.split("."):
        if not piece.isdigit():
            raise ValueError(f"version {text!r} has a non-numeric component {piece!r}")
        parts.append(int(piece))
    return tuple(parts)


def version_is_lower(head: str, base: str) -> bool:
    left = version_key(head)
    right = version_key(base)
    width = max(len(left), len(right))
    left = left + (0,) * (width - len(left))
    right = right + (0,) * (width - len(right))
    return left < right


def git_show(rev: str, path: str) -> str:
    result = subprocess.run(
        ["git", "show", f"{rev}:{path}"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail(f"cannot read {path} at {rev}")
    return result.stdout


def tree_of(rev: str) -> str:
    result = subprocess.run(
        ["git", "rev-parse", f"{rev}^{{tree}}"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail(f"cannot resolve tree of {rev}")
    return result.stdout.strip()


def directory_exists(rev: str, path: str) -> bool:
    result = subprocess.run(
        ["git", "ls-tree", "-d", rev, path],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0 and bool(result.stdout.strip())


def changed_file_count(base: str, head: str) -> int:
    result = subprocess.run(
        ["git", "diff", "--name-only", base, head],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail(f"cannot diff {base} {head}")
    return len([line for line in result.stdout.splitlines() if line.strip()])


def marketing_version(rev: str) -> str:
    return git_show(rev, "Tellomi/version").strip()


def versions_json_app(rev: str) -> str:
    payload = json.loads(git_show(rev, "versions.json"))
    app = payload.get("app")
    if not isinstance(app, str) or not app.strip():
        fail(f"versions.json app is missing at {rev}")
    return app.strip()


def check(base: str, head: str, head_ref: str, master_tree: str) -> None:
    if head_ref == "master":
        fail("pull request head is master; do not open master into release/ios")

    head_tree = tree_of(head)
    if head_tree == master_tree:
        count = changed_file_count(base, head)
        fail(
            "head tree equals origin/master "
            f"({count} files differ from the release/ios base); "
            "this replaces release/ios with master"
        )

    for path in MOMENTS_DIRECTORIES:
        if not directory_exists(head, path):
            fail(f"Moments directory is missing on the pull request head: {path}")

    for label, reader in (
        ("Tellomi/version", marketing_version),
        ("versions.json app", versions_json_app),
    ):
        base_version = reader(base)
        head_version = reader(head)
        if version_is_lower(head_version, base_version):
            fail(f"{label} {head_version} is lower than the base {base_version}")
        print(f"{label}: base {base_version}, head {head_version}")

    print("release guard passed")


def self_test() -> None:
    assert version_is_lower("14.0.5", "14.0.6")
    assert version_is_lower("14.0.4", "14.0.6")
    assert version_is_lower("1.0.1", "14.0.6")
    assert version_is_lower("14", "14.0.6")
    assert not version_is_lower("14.0.6", "14.0.6")
    assert not version_is_lower("14.0.7", "14.0.6")
    assert not version_is_lower("14.0.10", "14.0.6")
    assert version_key("14.0.6") == (14, 0, 6)
    try:
        version_key("14.0.6-tf1")
    except ValueError:
        pass
    else:
        raise AssertionError("non-numeric version was accepted")
    print("self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--base")
    parser.add_argument("--head")
    parser.add_argument("--head-ref")
    parser.add_argument("--master-tree")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    missing = [name for name in ("base", "head", "head_ref", "master_tree") if not getattr(args, name)]
    if missing:
        fail("missing " + ", ".join(missing))
    check(args.base, args.head, args.head_ref, args.master_tree)


if __name__ == "__main__":
    main()
