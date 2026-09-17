"""Extract the original text tables (reference/rise-of-legions/Lang/*.csv) into game/data/lang/<locale>.json.

The CSVs are ';'-separated with a "Column" key column and one column per language. Texts may reference
other keys with a leading paragraph sign (e.g. "§unitability_name_epic. Annihilates ...") and contain
HTML spans for keyword colouring; references are resolved here, tags are stripped (the HUD renders plain
text). Run: python tools/extract_lang.py [locale ...]  (default: en)
"""
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANG = ROOT / "reference" / "rise-of-legions" / "Lang"
OUT = ROOT / "game" / "data" / "lang"
RE_TAG = re.compile(r"<[^>]+>")
RE_REF = re.compile(r"§([A-Za-z0-9_]+)")


def load(locale: str) -> dict:
    table: dict = {}
    for path in sorted(LANG.glob("*.csv")):
        with path.open(encoding="utf-8-sig", newline="") as f:
            rows = csv.reader(f, delimiter=";", quotechar='"')
            header = next(rows)
            if locale not in header:
                continue
            col = header.index(locale)
            en = header.index("en") if "en" in header else col
            for row in rows:
                if not row or not row[0]:
                    continue
                text = row[col] if col < len(row) and row[col] else (row[en] if en < len(row) else "")
                table[row[0].lower()] = text   # the client looks keys up case-insensitively
    return table


def resolve(table: dict) -> dict:
    def sub(text: str, depth: int = 0) -> str:
        if depth > 5:
            return text
        return RE_REF.sub(lambda m: sub(table.get(m.group(1).lower(), m.group(0)), depth + 1), text)

    return {k: RE_TAG.sub("", sub(v)).replace("\\n", "\n") for k, v in table.items()}


def main() -> int:
    locales = sys.argv[1:] or ["en"]
    OUT.mkdir(parents=True, exist_ok=True)
    for locale in locales:
        table = resolve(load(locale))
        (OUT / f"{locale}.json").write_text(json.dumps(table, ensure_ascii=False, indent=0), encoding="utf-8")
        print(f"{locale}: {len(table)} keys")
    return 0


if __name__ == "__main__":
    sys.exit(main())
