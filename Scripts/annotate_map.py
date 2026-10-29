#!/usr/bin/env python3
"""Stamps every room on the Wriggler map with its screen index.

Room coordinates match the link notation: `row,column`, with `0,0` at the
top-left of the map. The label is drawn inside each room's top-left corner so it
stays readable when the map is zoomed in.

Usage:
    python3 Scripts/annotate_map.py
    python3 Scripts/annotate_map.py --out resources/wriggler-map-annotated.png
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_links import find_rooms  # noqa: E402  (same directory, plain script)

ROOT = Path(__file__).resolve().parent.parent
MAP = ROOT / "Extracted" / "wriggler-map-source.png"
DEFAULT_OUT = ROOT / "resources" / "wriggler-map-annotated.png"

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Menlo.ttc",
]


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", type=Path, default=MAP)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--size", type=int, default=22, help="label font size in map pixels")
    args = parser.parse_args()

    source = Image.open(args.map).convert("RGB")
    image = source.convert("RGBA")
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    font = load_font(args.size)
    pad = max(3, args.size // 4)

    rooms = find_rooms(__import__("numpy").asarray(source))
    for (row, column), (x0, y0) in rooms.items():
        label = f"{row},{column}"
        left, top, right, bottom = draw.textbbox((0, 0), label, font=font)
        width = right - left
        height = bottom - top
        # Keep the label inside the play area, tucked into the top-left corner.
        bx, by = x0 + 8 + pad, y0 + 8 + pad
        draw.rectangle([bx - pad, by - pad, bx + width + pad, by + height + 2 * pad], fill=(0, 0, 0, 190))
        draw.text((bx - left, by - top), label, font=font, fill=(255, 255, 0, 255))

    Image.alpha_composite(image, overlay).convert("RGB").save(args.out, optimize=True)
    size_kb = args.out.stat().st_size // 1024
    print(f"labelled {len(rooms)} rooms -> {args.out.relative_to(ROOT)} ({size_kb} KB)")


if __name__ == "__main__":
    main()
