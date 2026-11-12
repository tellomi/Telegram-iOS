#!/usr/bin/env python3
"""Host checks for dSYM naming. No Xcode, no IPA, no upload."""

import importlib.util
import pathlib
import stat
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("collect_dsyms", ROOT / "Tellomi" / "collect_dsyms.py")
collect_dsyms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collect_dsyms)


def expect(condition, message):
    if not condition:
        raise SystemExit(message)


def test_parser_prefers_arm64():
    text = """
UUID: AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA (arm64e) /tmp/App.dSYM/Contents/Resources/DWARF/App
UUID: 1575DE22-0975-3591-A160-CCF1A2EA97F1 (arm64) /tmp/App.dSYM/Contents/Resources/DWARF/App
"""
    entries = collect_dsyms.parse_dwarfdump_uuids(text)
    expect(len(entries) == 2, "two uuids")
    uuid, arch = collect_dsyms.choose_uuid(entries)
    expect(uuid == "1575DE22-0975-3591-A160-CCF1A2EA97F1", uuid)
    expect(arch == "arm64", arch)
    expect(collect_dsyms.bundle_dirname("91", uuid) == "91-1575DE22-0975-3591-A160-CCF1A2EA97F1.dSYM", "bundle name")
    expect(collect_dsyms.artifact_name("91") == "dsym-91", "artifact name")


def test_collect_names_each_bundle_and_ignores_the_ipa():
    with tempfile.TemporaryDirectory() as raw:
        root = pathlib.Path(raw)
        search = root / "search"
        search.mkdir()
        (search / "Telegram.ipa").write_bytes(b"not a package we copy")
        ui = search / "TelegramUIFramework.dSYM"
        (ui / "Contents" / "Resources" / "DWARF").mkdir(parents=True)
        (ui / "Contents" / "Resources" / "DWARF" / "TelegramUIFramework").write_bytes(b"ui")
        core = search / "MtProtoKit.dSYM"
        (core / "Contents").mkdir(parents=True)
        (core / "Contents" / "Info.plist").write_text("core", encoding="utf-8")
        fake = root / "dwarfdump.py"
        fake.write_text(
            "#!/usr/bin/env python3\n"
            "import pathlib, sys\n"
            "path = pathlib.Path(sys.argv[-1]).name\n"
            "uuids = {\n"
            "  'TelegramUIFramework.dSYM': '1575DE22-0975-3591-A160-CCF1A2EA97F1',\n"
            "  'MtProtoKit.dSYM': 'AFFBBB6C-5A13-3862-9455-D27B0222A0A4',\n"
            "}\n"
            "print('UUID: %s (arm64) %s' % (uuids[path], sys.argv[-1]))\n",
            encoding="utf-8",
        )
        fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
        out = root / "out"
        name = collect_dsyms.collect(search, "91", out, [sys.executable, str(fake)])
        expect(name == "dsym-91", name)
        expect((out / "artifact-name.txt").read_text(encoding="utf-8") == "dsym-91\n", "name file")
        ui_out = out / "91-1575DE22-0975-3591-A160-CCF1A2EA97F1.dSYM"
        core_out = out / "91-AFFBBB6C-5A13-3862-9455-D27B0222A0A4.dSYM"
        expect((ui_out / "Contents" / "Resources" / "DWARF" / "TelegramUIFramework").read_bytes() == b"ui", "ui copied")
        expect((core_out / "Contents" / "Info.plist").read_text(encoding="utf-8") == "core", "core copied")
        expect(not (out / "Telegram.ipa").exists(), "ipa stays out")
        manifest = (out / "manifest.tsv").read_text(encoding="utf-8")
        expect("1575DE22-0975-3591-A160-CCF1A2EA97F1" in manifest, manifest)
        expect("AFFBBB6C-5A13-3862-9455-D27B0222A0A4" in manifest, manifest)
        expect("TelegramUIFramework" in manifest, manifest)


def test_missing_dsym_fails():
    with tempfile.TemporaryDirectory() as raw:
        root = pathlib.Path(raw)
        search = root / "empty"
        search.mkdir()
        try:
            collect_dsyms.collect(search, "91", root / "out", ["dwarfdump"])
        except SystemExit as exc:
            expect("no dSYM" in str(exc), str(exc))
            return
        raise SystemExit("empty search should fail")


def main():
    test_parser_prefers_arm64()
    test_collect_names_each_bundle_and_ignores_the_ipa()
    test_missing_dsym_fails()
    subprocess.run([sys.executable, str(ROOT / "Tellomi" / "collect_dsyms.py"), "--help"], check=True, capture_output=True)


if __name__ == "__main__":
    main()
