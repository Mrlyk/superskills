---
topic: Diagrams & SVG assets
tags: [docs, assets]
---
# Diagrams & SVG assets

**README hero**: `assets/hero.svg` is a hand-authored SVG (`viewBox` 960×600), referenced by both `README.md` and `README.en.md` at `width="880"`. Editorial palette: bg `#F2EFE8`, terracotta `#D88966`, blue `#6FA8D6`, green `#7FB08F`. It should track the real architecture (currently: 4 skills, 3 hooks — SessionStart inject, Stop·verify, Stop·learn — and the topic-wiki memory loop).

**Before committing an SVG edit**: validate and eyeball it, don't trust the markup blind.
- well-formed: `python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('assets/hero.svg')"`
- render to preview: `qlmanage -t -s 960 -o /tmp assets/hero.svg` → writes `/tmp/hero.svg.png` (no rsvg/cairosvg needed on macOS).
- route flow arrows clear of node boxes — a return arrow at the box's own x runs through it; send it outside the pills.
