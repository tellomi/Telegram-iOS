#!/usr/bin/env python3
"""Check Tellomi's marketing version against a v* tag, when the run is one.

v0.1.0-tf9 and v0.1.0 both mean marketing version 0.1.0. The same string is
CFBundleShortVersionString on the app and every extension, via Tellomi/version.

A push to master, a workflow_dispatch from a branch, and a local run are not
tags. Those ship Tellomi/version as-is. The TestFlight build number is chosen
later, one above every App Store Connect build of this app.
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


def tagged_marketing_version(ref_type, ref_name):
    """Marketing version implied by a tag ref, or None when this run is not a tag.

    Branch refs are never tags, even if the branch name looks like v1.2.3.
    """
    if ref_type == "branch":
        return None
    return version_from_tag(ref_name)


def _self_check():
    assert tagged_marketing_version("branch", "master") is None
    assert tagged_marketing_version("branch", "v14.0.4") is None
    assert tagged_marketing_version("tag", "v14.0.4") == "14.0.4"
    assert tagged_marketing_version("tag", "v14.0.4-tf2") == "14.0.4"
    assert tagged_marketing_version("tag", "v0.1.0-tf9") == "0.1.0"
    assert tagged_marketing_version("", "") is None
    assert tagged_marketing_version("tag", "vnot-a-version") is None


def main():
    _self_check()
    version = read_version()
    ref_type = os.environ.get("GITHUB_REF_TYPE", "")
    ref_name = os.environ.get("GITHUB_REF_NAME", "")
    tagged = tagged_marketing_version(ref_type, ref_name)
    if tagged is not None and tagged != version:
        raise SystemExit(
            "tag {} is marketing version {}, but Tellomi/version is {}".format(ref_name, tagged, version)
        )
    print(version)


if __name__ == "__main__":
    main()
