# Emoji catalog sources

EmojiCatalog.json is generated from the stable Unicode Emoji 18.0 data and CLDR 49 EN/RU annotations.
It contains all 3,963 fully-qualified sequences, grouped into 1,923 base entries across nine Unicode categories.
The nine isolated skin/hair components are excluded; their valid combinations remain in the catalog.
Names and keywords come from CLDR annotations and annotationsDerived. Categories are translated locally.
Tone grouping removes modifiers and applies twelve explicit aliases for Unicode's expanded mixed-tone sequences.
The Unicode order is retained. No combinations are invented. All fully-qualified source sequences occur exactly once.

Rendering depends on the installed system emoji font; a catalog entry does not guarantee Apple rendering support.
The app reads bundled data only. The generator may download sources during development; it validates every SHA-256.

Release verification:
- https://www.unicode.org/Public/emoji/latest/ReadMe.txt (checked 2026-11-05: final Emoji 18.0)
- https://cldr.unicode.org/downloads/cldr-49 (stable release 2026-10-22; Unicode 18 annotations)

Pinned inputs:

- emoji-test.txt: https://www.unicode.org/Public/18.0.0/emoji/emoji-test.txt
  SHA-256: `8f3735cda1f92a779d78af67cf86066bb1f07143dc22f2ac29394d9bc57ab21a`
- annotations-en.xml: https://raw.githubusercontent.com/unicode-org/cldr/release-49/common/annotations/en.xml
  SHA-256: `14d0e9bb5003c085250df4ac7bd7ba1e26d92e74174d7a3a2f42dc16e07fb155`
- annotations-ru.xml: https://raw.githubusercontent.com/unicode-org/cldr/release-49/common/annotations/ru.xml
  SHA-256: `4567afe74b0b65a1f07ce259867cd9b4b30901d56b8464be5d748873f97e792c`
- derived-en.xml: https://raw.githubusercontent.com/unicode-org/cldr/release-49/common/annotationsDerived/en.xml
  SHA-256: `a4a6c1a4c341d94179cb116623c5f44c47400a5bc55da483423ef7430ecf622e`
- derived-ru.xml: https://raw.githubusercontent.com/unicode-org/cldr/release-49/common/annotationsDerived/ru.xml
  SHA-256: `509fc079decc3ae19a0fbdd7426d5cdd8dfc3d3038dc473115882f052b23f5f3`
- LICENSE: https://raw.githubusercontent.com/unicode-org/cldr/release-49/LICENSE
  SHA-256: `65eb33419e22a297550a811b5b535f5e532f9a7e0114b516c0ea18afd53c3804`

Regenerate from the project directory:

```sh
python3 Scripts/generate_emoji_catalog.py --source-dir /tmp/splitpad-emoji-sources --download
python3 Scripts/generate_emoji_catalog.py --source-dir /tmp/splitpad-emoji-sources --check
```

Unicode data and CLDR annotations are distributed under Unicode License V3.
The unmodified upstream copyright and permission notice is bundled as LICENSE-UNICODE.txt.
