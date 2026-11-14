#!/usr/bin/env python3
"""The bundled Tellomi strings cover every server langpack language."""
import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
I18N = Path(__file__).resolve().parent
LANGS = [
    "ar", "be", "ca", "cs", "de", "el", "en", "es", "fa", "fi", "fr", "he", "hi",
    "id", "it", "ja", "ko", "ms", "nb", "nl", "pl", "pt-br", "ro", "ru", "sv", "th",
    "tr", "uk", "uz", "vi", "zh-hans", "zh-hant",
]
PLACEHOLDER = re.compile(r'%(?:\d+\$)?[@ds]')
ENTRY = re.compile(r'"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;')


def parse(path):
    data = {}
    for match in ENTRY.finditer(path.read_text(encoding="utf-8")):
        data[match.group(1)] = match.group(2)
    return data


def main():
    tables = {code: parse(I18N / f"{code}.strings") for code in LANGS}
    english = tables["en"]
    assert len(english) > 150
    for code, table in tables.items():
        assert set(table) == set(english), code
        for key, value in table.items():
            assert value.strip(), (code, key)
            assert PLACEHOLDER.findall(value) == PLACEHOLDER.findall(english[key]), (code, key)
    assert tables["de"]["Tellomi.Settings.Privacy"] == "Privatsphäre und Sicherheit"
    assert tables["zh-hans"]["Tellomi.Discover.ConfirmCity"] == "确定"
    assert tables["zh-hant"]["Tellomi.Discover.ChangeCity"] == "更換城市"
    assert tables["ja"]["Tellomi.Discover.City.cn_chengdu"] == "成都"
    bundled = (ROOT / "submodules/TellomiDiscover/Sources/TellomiBundledLocalizations.swift").read_text(encoding="utf-8")
    for code in LANGS:
        assert f'"{code}":' in bundled
    with (I18N / "audit-ios.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == len(english)
    assert {row["key"] for row in rows} == set(english)
    missing = ",".join(code for code in LANGS if code not in ("en", "zh-hans", "zh-hant"))
    for row in rows:
        assert row["languages missing before"] == missing
        assert row["fixed"] == "yes"
        assert row["file"]
    print(f"ok {len(english)} keys x {len(LANGS)} languages")


if __name__ == "__main__":
    main()
