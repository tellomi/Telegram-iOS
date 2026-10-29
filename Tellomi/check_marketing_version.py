#!/usr/bin/env python3
"""Check Tellomi's marketing version against the v* tag, when there is one.

v0.1.0-tf9 and v0.1.0 both mean marketing version 0.1.0. The same string is
CFBundleShortVersionString on the app and every extension, via Tellomi/version.
"""

import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION_PATH = ROOT / "Tellomi" / "version"
TAG_RE = re.compile(r"v(\d+(?:\.\d+){0,2})(?:-tf\d+)?\Z")


def read_version():
    text = VERSION_PATH.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", text):
        raise SystemExit("Tellomi/version is not a marketing version: {}".format(text))
    return text


def version_from_tag(tag):
    match = TAG_RE.fullmatch(tag or "")
    if not match:
        return None
    return match.group(1)


def main():
    version = read_version()
    tag = os.environ.get("GITHUB_REF_NAME", "")
    tagged = version_from_tag(tag)
    if tagged is not None and tagged != version:
        raise SystemExit(
            "tag {} is marketing version {}, but Tellomi/version is {}".format(tag, tagged, version)
        )
    print(version)


if __name__ == "__main__":
    main()
