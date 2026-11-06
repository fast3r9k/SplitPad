#!/usr/bin/env python3
"""Generate the bundled offline catalog from hash-pinned Unicode/CLDR releases.

python3 Scripts/generate_emoji_catalog.py --source-dir /tmp/emoji-sources --download
python3 Scripts/generate_emoji_catalog.py --source-dir /tmp/emoji-sources --check
No third-party Python packages are required. Downloading happens only here,
never from the app. The cache is validated on every generation/check.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.request import urlopen
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "emoji-test.txt": (
        "https://www.unicode.org/Public/18.0.0/emoji/emoji-test.txt",
        "8f3735cda1f92a779d78af67cf86066bb1f07143dc22f2ac29394d9bc57ab21a"),
    "annotations-en.xml": (
        "https://raw.githubusercontent.com/unicode-org/cldr/release-49/common/annotations/en.xml",
        "14d0e9bb5003c085250df4ac7bd7ba1e26d92e74174d7a3a2f42dc16e07fb155"),
    "annotations-ru.xml": (
        "https://raw.githubusercontent.com/unicode-org/cldr/release-49/common/annotations/ru.xml",
        "4567afe74b0b65a1f07ce259867cd9b4b30901d56b8464be5d748873f97e792c"),
    "derived-en.xml": (
        "https://raw.githubusercontent.com/unicode-org/cldr/release-49/common/annotationsDerived/en.xml",
        "a4a6c1a4c341d94179cb116623c5f44c47400a5bc55da483423ef7430ecf622e"),
    "derived-ru.xml": (
        "https://raw.githubusercontent.com/unicode-org/cldr/release-49/common/annotationsDerived/ru.xml",
        "509fc079decc3ae19a0fbdd7426d5cdd8dfc3d3038dc473115882f052b23f5f3"),
    "LICENSE": (
        "https://raw.githubusercontent.com/unicode-org/cldr/release-49/LICENSE",
        "65eb33419e22a297550a811b5b535f5e532f9a7e0114b516c0ea18afd53c3804"),
}
CATEGORIES = {
    "Smileys & Emotion": ("smileys", "😀", "Смайлы и эмоции", "Smileys & Emotion"),
    "People & Body": ("people", "👋", "Люди и жесты", "People & Body"),
    "Animals & Nature": ("nature", "🐻", "Животные и природа", "Animals & Nature"),
    "Food & Drink": ("food", "🍎", "Еда и напитки", "Food & Drink"),
    "Travel & Places": ("travel", "🚗", "Поездки и места", "Travel & Places"),
    "Activities": ("activities", "⚽️", "Занятия и спорт", "Activities"),
    "Objects": ("objects", "💡", "Предметы", "Objects"),
    "Symbols": ("symbols", "❤️", "Символы", "Symbols"),
    "Flags": ("flags", "🏁", "Флаги", "Flags"),
}
# Unicode uses older single-scalar/short sequences for these unmodified bases
# and expanded ZWJ forms for mixed tones. Removing modifiers alone is not enough.
BASE_ALIASES = {
    "🫱‍🫲": "🤝",
    "🧑‍🐰‍🧑": "👯", "👨‍🐰‍👨": "👯‍♂", "👩‍🐰‍👩": "👯‍♀",
    "🧑‍🫯‍🧑": "🤼", "👨‍🫯‍👨": "🤼‍♂", "👩‍🫯‍👩": "🤼‍♀",
    "👩‍🤝‍👩": "👭", "👩‍🤝‍👨": "👫", "👨‍🤝‍👨": "👬",
    "🧑‍❤‍💋‍🧑": "💏", "🧑‍❤‍🧑": "💑",
}


def lookup_key(glyph):
    return glyph.replace("\ufe0f", "")


def without_tones(glyph):
    return "".join(c for c in lookup_key(glyph) if not 0x1F3FB <= ord(c) <= 0x1F3FF)


def load_sources(directory, download):
    result = {}
    directory.mkdir(parents=True, exist_ok=True)
    for name, (url, expected) in SOURCES.items():
        path = directory / name
        if not path.exists():
            if not download:
                raise SystemExit(f"Missing {path}; pass --download to fetch pinned sources")
            with urlopen(url, timeout=60) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != expected:
                raise SystemExit(f"Downloaded source hash mismatch: {url}")
            path.write_bytes(data)
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise SystemExit(f"Cached source hash mismatch: {path}")
        result[name] = data
    return result


def annotations(sources, language):
    result = {}
    for name in (f"annotations-{language}.xml", f"derived-{language}.xml"):
        for node in ET.fromstring(sources[name]).iter("annotation"):
            text = (node.text or "").strip()
            if not text or text in ("↑↑↑", "∅∅∅"):
                continue
            item = result.setdefault(lookup_key(node.attrib["cp"]), {"name": "", "keywords": set()})
            if node.get("type") == "tts":
                item["name"] = text
            else:
                item["keywords"].update(part.strip() for part in text.split("|") if part.strip())
    return result


def generate(sources):
    text = sources["emoji-test.txt"].decode("utf-8")
    assert "# Version: 18.0\n" in text
    records = []
    components = []
    for line in text.splitlines():
        if line.startswith("# group: "):
            group = line.removeprefix("# group: ")
        if not line or line.startswith("#"):
            continue
        points, remainder = line.split(";", 1)
        status, comment = remainder.split("#", 1)
        glyph = "".join(chr(int(point, 16)) for point in points.split())
        if status.strip() == "component":
            components.append(glyph)
        if status.strip() == "fully-qualified":
            name = re.split(r" E[0-9.]+ ", comment.strip(), maxsplit=1)[1]
            records.append({"glyph": glyph, "group": group, "name": name})
    assert len(records) == 3963 and len(components) == 9
    assert len({record["glyph"] for record in records}) == len(records)
    locales = {language: annotations(sources, language) for language in ("en", "ru")}
    bases = {lookup_key(row["glyph"]): row for row in records
             if without_tones(row["glyph"]) == lookup_key(row["glyph"])}
    variants = {key: [] for key in bases}
    for row in records:
        key = without_tones(row["glyph"])
        key = BASE_ALIASES.get(key, key)
        assert key in bases, f"Unmapped variant: {row}"
        assert row["group"] == bases[key]["group"]
        variants[key].append(row["glyph"])
    categories = []
    for group, (identifier, icon, russian, english) in CATEGORIES.items():
        entries = []
        for key, row in bases.items():
            if row["group"] != group:
                continue
            forms = [row["glyph"]] + [form for form in variants[key] if form != row["glyph"]]
            names = {language: locales[language][key]["name"] for language in locales}
            assert all(names.values()), row
            keywords = {row["name"]}
            for form in forms:
                for locale in locales.values():
                    annotation = locale[lookup_key(form)]
                    keywords.update(annotation["keywords"])
            entries.append({"glyph": row["glyph"], "russian": names["ru"], "english": names["en"],
                            "categoryID": identifier, "variants": forms, "keywords": sorted(keywords)})
        categories.append({"id": identifier, "icon": icon, "russian": russian,
                           "english": english, "entries": entries})
    all_entries = [entry for category in categories for entry in category["entries"]]
    all_forms = [form for entry in all_entries for form in entry["variants"]]
    assert len(all_entries) == 1923
    assert len(all_forms) == len(set(all_forms)) == len(records)
    assert set(all_forms) == {record["glyph"] for record in records}
    payload = {"formatVersion": 1, "unicodeVersion": "18.0", "cldrVersion": "49",
               "fullyQualifiedCount": len(records), "baseCount": len(all_entries),
               "sources": [{"url": url, "sha256": digest} for url, digest in SOURCES.values()],
               "categories": categories}
    return payload


def provenance(payload):
    lines = [
        "# Emoji catalog sources", "",
        "EmojiCatalog.json is generated from the stable Unicode Emoji 18.0 data and CLDR 49 EN/RU annotations.",
        "It contains all 3,963 fully-qualified sequences, grouped into 1,923 base entries across nine Unicode categories.",
        "The nine isolated skin/hair components are excluded; their valid combinations remain in the catalog.",
        "Names and keywords come from CLDR annotations and annotationsDerived. Categories are translated locally.",
        "Tone grouping removes modifiers and applies twelve explicit aliases for Unicode's expanded mixed-tone sequences.",
        "The Unicode order is retained. No combinations are invented. All fully-qualified source sequences occur exactly once.",
        "", "Rendering depends on the installed system emoji font; a catalog entry does not guarantee Apple rendering support.",
        "The app reads bundled data only. The generator may download sources during development; it validates every SHA-256.",
        "", "Release verification:",
        "- https://www.unicode.org/Public/emoji/latest/ReadMe.txt (checked 2026-11-05: final Emoji 18.0)",
        "- https://cldr.unicode.org/downloads/cldr-49 (stable release 2026-10-22; Unicode 18 annotations)",
        "", "Pinned inputs:", "",
    ]
    for name, (url, digest) in SOURCES.items():
        lines += [f"- {name}: {url}", f"  SHA-256: `{digest}`"]
    lines += ["", "Regenerate from the project directory:", "", "```sh",
              "python3 Scripts/generate_emoji_catalog.py --source-dir /tmp/thumbsplit-emoji-sources --download",
              "python3 Scripts/generate_emoji_catalog.py --source-dir /tmp/thumbsplit-emoji-sources --check",
              "```", "", "Unicode data and CLDR annotations are distributed under Unicode License V3.",
              "The unmodified upstream copyright and permission notice is bundled as LICENSE-UNICODE.txt.", ""]
    return "\n".join(lines).encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--check", action="store_true", help="Validate generated files without writing")
    args = parser.parse_args()
    sources = load_sources(args.source_dir, args.download)
    payload = generate(sources)
    outputs = {
        "EmojiCatalog.json": (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"),
        "EmojiCatalogSources.md": provenance(payload),
        "LICENSE-UNICODE.txt": sources["LICENSE"],
    }
    for name, data in outputs.items():
        path = ROOT / "KeyboardExtension" / name
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit(f"Generated file differs: {path}")
        else:
            path.write_bytes(data)
    print(f"{'Verified' if args.check else 'Generated'} {payload['baseCount']} bases / "
          f"{payload['fullyQualifiedCount']} fully-qualified sequences / {len(payload['categories'])} categories")


if __name__ == "__main__":
    main()
