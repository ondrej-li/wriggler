#!/usr/bin/env python3
"""Draws the app icon.

Kept as a script rather than a hand-made binary so it can be regenerated.
App Store Connect rejects a 1024 icon that carries an alpha channel, so this
writes plain RGB on an opaque background.

Usage:
    python3 Scripts/make_app_icon.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "Sources/Wriggler/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

SIZE = 1024
INK = (0, 0, 0)
BODY = (0, 220, 0)
BODY_DARK = (0, 150, 0)
EYE = (240, 255, 240)
BORDER = (220, 220, 0)


def main() -> None:
    image = Image.new("RGB", (SIZE, SIZE), INK)
    draw = ImageDraw.Draw(image)

    # A worm curling from the bottom-left to the top-right.
    steps = 220
    for index in range(steps):
        t = index / (steps - 1)
        x = 190 + t * 640
        y = 760 - math.sin(t * math.pi * 0.9) * 430
        radius = 96 - t * 34
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=BODY)

    # Segment ridges, a darker ring every few steps.
    for index in range(0, steps, 26):
        t = index / (steps - 1)
        x = 190 + t * 640
        y = 760 - math.sin(t * math.pi * 0.9) * 430
        radius = 96 - t * 34
        draw.ellipse(
            [x - radius, y - radius * 0.16, x + radius, y + radius * 0.16],
            outline=BODY_DARK,
            width=9,
        )

    # Head, facing right.
    head_x, head_y, head_r = 830, 330, 116
    draw.ellipse([head_x - head_r, head_y - head_r, head_x + head_r, head_y + head_r], fill=BODY)
    draw.ellipse([head_x - 42, head_y - 58, head_x + 14, head_y - 2], fill=EYE)
    draw.ellipse([head_x - 18, head_y - 46, head_x + 8, head_y - 20], fill=INK)

    # Yellow frame, echoing the room borders in the game.
    draw.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=BORDER, width=26)

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    image.save(TARGET, format="PNG", optimize=True)
    print(f"wrote {TARGET.relative_to(ROOT)} ({image.mode}, {image.size[0]}x{image.size[1]})")


if __name__ == "__main__":
    main()
