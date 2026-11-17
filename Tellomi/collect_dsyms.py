#!/usr/bin/env python3
"""Copy a release build's dSYMs into names that include the build number and UUID.

The TestFlight workflow stores that directory as a GitHub Actions artifact.
This script does not upload, sign, or publish.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import shutil
import subprocess
import sys

UUID_TEXT = r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
DWARFDUMP_UUID = re.compile(rf"UUID:\s*({UUID_TEXT})\s+\(([^)]+)\)")
CANONICAL_UUID = re.compile(rf"^{UUID_TEXT}$")


def parse_dwarfdump_uuids(text: str) -> list[tuple[str, str]]:
    found = []
    for match in DWARFDUMP_UUID.finditer(text):
        found.append((match.group(1).upper(), match.group(2).strip()))
    return found


def choose_uuid(entries: list[tuple[str, str]]) -> tuple[str, str]:
    arm64 = [entry for entry in entries if entry[1] == "arm64"]
    if len(arm64) == 1:
        return arm64[0]
    if len(arm64) == 0 and len(entries) == 1:
        return entries[0]
    raise ValueError("expected one arm64 UUID, got {}".format(entries))


def artifact_name(build_number: str) -> str:
    if not re.fullmatch(r"[0-9]+", build_number):
        raise ValueError("build number must be decimal")
    return "dsym-{}".format(build_number)


def bundle_dirname(build_number: str, uuid: str) -> str:
    artifact_name(build_number)
    if not CANONICAL_UUID.fullmatch(uuid):
        raise ValueError("uuid is not canonical")
    return "{}-{}.dSYM".format(build_number, uuid.upper())


def find_dsyms(search: pathlib.Path) -> list[pathlib.Path]:
    return sorted(path for path in search.glob("*.dSYM") if path.is_dir())


def read_uuids(dsym: pathlib.Path, dwarfdump: list[str]) -> list[tuple[str, str]]:
    completed = subprocess.run(
        dwarfdump + ["--uuid", str(dsym)],
        check=True,
        capture_output=True,
        text=True,
    )
    return parse_dwarfdump_uuids(completed.stdout)


def collect(search: pathlib.Path, build_number: str, out: pathlib.Path, dwarfdump: list[str]) -> str:
    bundles = find_dsyms(search)
    if not bundles:
        raise SystemExit("no dSYM bundles in {}".format(search))
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    lines = ["build\tuuid\tarch\tbinary\tbundle"]
    seen = set()
    for bundle in bundles:
        uuid, arch = choose_uuid(read_uuids(bundle, dwarfdump))
        if uuid in seen:
            raise SystemExit("duplicate UUID {}".format(uuid))
        seen.add(uuid)
        name = bundle_dirname(build_number, uuid)
        binary = bundle.name[:-5] if bundle.name.endswith(".dSYM") else bundle.name
        shutil.copytree(bundle, out / name)
        lines.append("\t".join([build_number, uuid, arch, binary, name]))
    name = artifact_name(build_number)
    (out / "manifest.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (out / "artifact-name.txt").write_text(name + "\n", encoding="utf-8")
    return name


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--search", required=True, type=pathlib.Path)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--dwarfdump", default="xcrun dwarfdump")
    args = parser.parse_args(argv)
    collect(args.search, args.build_number, args.out, args.dwarfdump.split())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
