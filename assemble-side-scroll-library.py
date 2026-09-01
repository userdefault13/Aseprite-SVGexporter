#!/usr/bin/env python3
"""Assemble aavegotchi_side-scroll_*.json from batch SVG-JSON exports.

Never writes or mutates aavegotchi_db_* files.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

RAW_DEFAULT = Path(
    "/Users/juliuswong/Dev/Paarcel/Assets/Resources/Aavegotchi/JSONs/_side-scroll-raw"
)
OUT_PAARCEL = Path("/Users/juliuswong/Dev/Paarcel/Assets/Resources/Aavegotchi/JSONs")
OUT_PAINT = Path("/Users/juliuswong/Dev/Aseprite-AavegotchiPaaint/JSONs")

VIEW_MAP = {
    "front": "front",
    "left": "left",
    "right": "right",
    "back": "back",
    "00": "back",
}


def load_svg_json(path: Path) -> dict | None:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"WARN: failed to parse {path}: {exc}")
        return None


def prefer_svg(data: dict | None) -> str | None:
    if not data:
        return None
    if data.get("svg"):
        return data["svg"]
    layers = data.get("layers") or []
    if not layers:
        return None
    # Concatenate layer SVGs' inner content into one wrapper if needed
    parts = []
    for layer in layers:
        svg = layer.get("svg") or ""
        # Prefer full svg strings as-is for first layer; merge subsequent
        parts.append(svg)
    if len(parts) == 1:
        return parts[0]
    return parts[0] if parts else None


def find_part(raw_dir: Path, part: str, *name_globs: str) -> str | None:
    part_dir = raw_dir / part
    if not part_dir.is_dir():
        return None
    for pattern in name_globs:
        matches = sorted(part_dir.glob(pattern))
        for m in matches:
            svg = prefer_svg(load_svg_json(m))
            if svg:
                return svg
    return None


def parse_body_views(raw_dir: Path) -> dict:
    out = {}
    body_dir = raw_dir / "body"
    if not body_dir.is_dir():
        return out
    for f in body_dir.glob("*.svg.json"):
        # body_front_amAAVE.svg.json / body_00_amAAVE.svg.json
        m = re.match(r"body_(front|left|right|back|00)_", f.stem, re.I)
        if not m:
            continue
        view = VIEW_MAP.get(m.group(1).lower())
        if not view:
            continue
        svg = prefer_svg(load_svg_json(f))
        if svg:
            out[view] = svg
    return out


def parse_collateral_views(raw_dir: Path) -> dict:
    out = {}
    d = raw_dir / "collateral"
    if not d.is_dir():
        return out
    for f in d.glob("*.svg.json"):
        m = re.match(r"collateral_(front|left|right|back)_", f.stem, re.I)
        if not m:
            continue
        view = m.group(1).lower()
        svg = prefer_svg(load_svg_json(f))
        if svg:
            out[view] = svg
    return out


def parse_hands(raw_dir: Path) -> dict:
    mapping = {
        "frontDownOpen": ("hands_down_open_*.svg.json",),
        "frontDownClosed": ("hands_down_closed_*.svg.json",),
        "frontUpOpen": ("hands_up_*.svg.json",),
        "left": ("hands_left_*.svg.json",),
        "right": ("hands_right_*.svg.json",),
    }
    out = {}
    for key, patterns in mapping.items():
        svg = find_part(raw_dir, "hands", *patterns)
        if svg:
            out[key] = svg
    return out


def parse_mouth(raw_dir: Path) -> dict:
    out = {}
    for expr in ("neutral", "happy", "sad", "surprised"):
        svg = find_part(
            raw_dir,
            "mouth",
            f"mouth_{expr}_00_*.svg.json",
            f"mouth_{expr}_*.svg.json",
        )
        if svg:
            out[expr] = svg
    return out


def parse_shadow(raw_dir: Path) -> list:
    shadows = []
    for idx in ("00", "01"):
        svg = find_part(raw_dir, "shadow", f"shadow_{idx}_*.svg.json")
        if svg:
            shadows.append(svg)
    return shadows


def parse_eye_shapes(raw_dir: Path) -> list:
    """Collect eye packs: range folder + rarity + views."""
    eye_root = raw_dir / "eye shape"
    if not eye_root.is_dir():
        return []

    by_key: dict[tuple, dict] = {}
    for f in eye_root.rglob("*.svg.json"):
        # haunt1_id00_front_common.svg.json under haunt1_id00_range0-1/
        stem = f.stem
        m = re.match(
            r"(haunt[12])_id(\d+)_(front|left|right)_(.+)$",
            stem,
            re.I,
        )
        if not m:
            continue
        haunt, id_s, view, rarity = m.group(1).lower(), m.group(2), m.group(3).lower(), m.group(4).lower()
        # range from parent folder if present
        parent = f.parent.name
        rm = re.search(r"range(\d+)-(\d+)", parent, re.I)
        rmin = int(rm.group(1)) if rm else 0
        rmax = int(rm.group(2)) if rm else 0
        key = (haunt, int(id_s), rmin, rmax, rarity)
        entry = by_key.setdefault(
            key,
            {
                "haunt": 1 if haunt == "haunt1" else 2,
                "id": int(id_s),
                "rangeMin": rmin,
                "rangeMax": rmax,
                "rarity": rarity,
                "svgs": {},
            },
        )
        svg = prefer_svg(load_svg_json(f))
        if svg:
            entry["svgs"][view] = svg

    results = []
    for entry in by_key.values():
        # Order front,left,right like official eye shapes
        ordered = [entry["svgs"].get(v) for v in ("front", "left", "right") if entry["svgs"].get(v)]
        results.append(
            {
                "haunt": entry["haunt"],
                "id": entry["id"],
                "rangeMin": entry["rangeMin"],
                "rangeMax": entry["rangeMax"],
                "rarity": entry["rarity"],
                "svgs": ordered,
                "svgsByView": entry["svgs"],
            }
        )
    results.sort(key=lambda e: (e["haunt"], e["id"], e["rarity"]))
    return results


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Safety: never write aavegotchi_db_*
    if path.name.startswith("aavegotchi_db_"):
        raise RuntimeError(f"Refusing to write official db file: {path}")
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {path}")


def assemble_collateral(raw_root: Path, collateral: str) -> dict:
    raw_dir = raw_root / collateral
    if not raw_dir.is_dir():
        raise FileNotFoundError(f"Missing raw export for {collateral}: {raw_dir}")
    return {
        "collateral": collateral,
        "source": "paarcel-aseprite-side-scroll",
        "body": parse_body_views(raw_dir),
        "hands": parse_hands(raw_dir),
        "mouth": parse_mouth(raw_dir),
        "shadow": parse_shadow(raw_dir),
        "collateralIcons": parse_collateral_views(raw_dir),
        "eyeShapes": parse_eye_shapes(raw_dir),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", type=Path, default=RAW_DEFAULT)
    ap.add_argument("--out-paarcel", type=Path, default=OUT_PAARCEL)
    ap.add_argument("--out-paint", type=Path, default=OUT_PAINT)
    ap.add_argument("collaterals", nargs="*", default=["amAAVE"])
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()

    if args.all:
        collaterals = sorted(p.name for p in args.raw.iterdir() if p.is_dir())
    else:
        collaterals = args.collaterals

    if not collaterals:
        raise SystemExit("No collaterals to assemble")

    bases = []
    all_eye_shapes = []
    collaterals_index = []

    for c in collaterals:
        print(f"Assembling {c}…")
        data = assemble_collateral(args.raw, c)
        bases.append(data)
        all_eye_shapes.extend(data.get("eyeShapes") or [])
        collaterals_index.append(
            {
                "name": c,
                "haunt": 2 if c.startswith("am") else 1,
                "svgsByView": data.get("collateralIcons") or {},
                "svgs": [
                    (data.get("collateralIcons") or {}).get(v)
                    for v in ("front", "left", "right", "back")
                    if (data.get("collateralIcons") or {}).get(v)
                ],
            }
        )

        base_name = f"aavegotchi_side-scroll_base-{c.lower()}.json"
        for out_root in (args.out_paarcel, args.out_paint):
            write_json(out_root / base_name, data)

    # Shared main: first collateral's body/hands/mouth/shadow as representative shared pack
    # plus list of available collaterals
    main_src = bases[0]
    main = {
        "source": "paarcel-aseprite-side-scroll",
        "note": "Derived from side-scroll Aseprite assets. Parallel to aavegotchi_db_*; do not confuse with official contract SVGs.",
        "body": main_src.get("body") or {},
        "hands": main_src.get("hands") or {},
        "mouth": main_src.get("mouth") or {},
        "shadow": main_src.get("shadow") or [],
        "collaterals": [c["name"] for c in collaterals_index],
    }

    files = {
        "aavegotchi_side-scroll_main.json": main,
        "aavegotchi_side-scroll_collaterals.json": {"collaterals": collaterals_index},
        "aavegotchi_side-scroll_eye_shapes_haunt1.json": {
            "eyeShapes": [e for e in all_eye_shapes if e.get("haunt") == 1]
        },
        "aavegotchi_side-scroll_eye_shapes_haunt2.json": {
            "eyeShapes": [e for e in all_eye_shapes if e.get("haunt") == 2]
        },
    }

    for name, payload in files.items():
        for out_root in (args.out_paarcel, args.out_paint):
            write_json(out_root / name, payload)

    print(f"Done. Assembled {len(collaterals)} collateral(s).")


if __name__ == "__main__":
    main()
