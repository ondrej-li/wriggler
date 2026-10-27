#!/usr/bin/env python3
"""Generates placeholder pixel art for the Wriggler iOS app.

The final artwork will be extracted from `resources/Wriggler.tzx` by the asset
pipeline; until that exists this script keeps the app looking like a Spectrum game
and exercises the sprite pipeline end to end.

Art is authored as character grids in the classic ZX Spectrum palette and written
straight into an asset catalog. Re-run after editing the grids:

    python3 Scripts/generate_placeholder_art.py
"""

from __future__ import annotations

import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Sources" / "Wriggler" / "Resources" / "Assets.xcassets"

# ZX Spectrum palette, keyed by the characters used in the grids below.
PALETTE = {
    ".": (0, 0, 0, 0),          # transparent
    "k": (0, 0, 0, 255),        # black
    "K": (0, 0, 0, 255),        # black (alias, used for eyes)
    "b": (0, 0, 215, 255),
    "B": (0, 0, 255, 255),
    "r": (215, 0, 0, 255),
    "R": (255, 0, 0, 255),
    "m": (215, 0, 215, 255),
    "M": (255, 0, 255, 255),
    "g": (0, 215, 0, 255),
    "G": (0, 255, 0, 255),
    "c": (0, 215, 215, 255),
    "C": (0, 255, 255, 255),
    "y": (215, 215, 0, 255),
    "Y": (255, 255, 0, 255),
    "w": (215, 215, 215, 255),
    "W": (255, 255, 255, 255),
}

TILES: dict[str, list[str]] = {
    "tile_wall": [
        "CCCCCCCC",
        "CkkkkkkC",
        "CkCCCCkC",
        "CkCkkCkC",
        "CkCkkCkC",
        "CkCCCCkC",
        "CkkkkkkC",
        "CCCCCCCC",
    ],
    "tile_platform": [
        "YYYYYYYY",
        "YkkkkkkY",
        "........",
        "........",
        "........",
        "........",
        "........",
        "........",
    ],
    "tile_ladder": [
        ".g....g.",
        ".gYYYYg.",
        ".g....g.",
        ".gYYYYg.",
        ".g....g.",
        ".gYYYYg.",
        ".g....g.",
        ".gYYYYg.",
    ],
    "tile_spike": [
        "........",
        "........",
        "..M..M..",
        "..M..M..",
        ".MM.MM.M",
        ".MM.MM.M",
        "MMMMMMMM",
        "MMMMMMMM",
    ],
    "tile_exit": [
        "CCCCCCCC",
        "CwwCCwwC",
        "CwwCCwwC",
        "CCCCCCCC",
        "CCCCCCCC",
        "CwwCCwwC",
        "CwwCCwwC",
        "CCCCCCCC",
    ],
}

PLAYER_BODY = [
    "................",
    "................",
    ".....GGGGGG.....",
    "....GGGGGGGG....",
    "...GGWWGGWWGG...",
    "...GGWKGGWKGG...",
    "...GGGGGGGGGG...",
    "...GGGKKKKGGG...",
    "....GGGGGGGG....",
    ".....GGGGGG.....",
    "......GGGG......",
    ".......GG.......",
    "......GG........",
    ".....GGG........",
    "....GGG.........",
    "................",
]

SPRITES: dict[str, list[str]] = {
    "player_idle": PLAYER_BODY,
    "player_walk_a": PLAYER_BODY[:11] + [
        "........GG......",
        "........GG......",
        ".......GGG......",
        "......GGG.......",
        "................",
    ],
    "player_walk_b": PLAYER_BODY[:11] + [
        ".....GG.........",
        ".....GG.........",
        "....GGG.........",
        "...GGG..........",
        "................",
    ],
    "player_jump": [
        "................",
        "................",
        "................",
        "....GGGGGGGG....",
        "...GGWWGGWWGG...",
        "...GGWKGGWKGG...",
        "...GGGGGGGGGG...",
        "...GGGKKKKGGG...",
        "..GGGGGGGGGGGG..",
        "..GG.GGGGGG.GG..",
        ".....GGGGGG.....",
        "....GG....GG....",
        "...GG......GG...",
        "................",
        "................",
        "................",
    ],
    "enemy_crawler": [
        "................",
        "................",
        "....MMMMMMMM....",
        "...MMMMMMMMMM...",
        "..MMWWMMMMWWMM..",
        "..MMWKMMMMWKMM..",
        "..MMMMMMMMMMMM..",
        "..MMMKKKKKKMMM..",
        ".MMMMMMMMMMMMMM.",
        ".MM.MMMMMMMM.MM.",
        "...MMMMMMMMMM...",
        "....MMMMMMMM....",
        "...MM..MM..MM...",
        "..MM....M....MM.",
        "................",
        "................",
    ],
}


def rasterize(grid: list[str], size: int) -> list[list[tuple[int, int, int, int]]]:
    if len(grid) != size:
        raise ValueError(f"expected {size} rows, got {len(grid)}")
    rows = []
    for index, row in enumerate(grid):
        if len(row) != size:
            raise ValueError(f"row {index} has {len(row)} columns, expected {size}: {row!r}")
        rows.append([PALETTE[char] for char in row])
    return rows


def scale(rows: list[list[tuple[int, int, int, int]]], factor: int):
    out = []
    for row in rows:
        expanded = [pixel for pixel in row for _ in range(factor)]
        out.extend([expanded] * factor)
    return out


def write_png(path: Path, rows: list[list[tuple[int, int, int, int]]]) -> None:
    height = len(rows)
    width = len(rows[0])
    raw = b"".join(b"\x00" + bytes(channel for pixel in row for channel in pixel) for row in rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def write_imageset(name: str, rows: list[list[tuple[int, int, int, int]]]) -> None:
    imageset = ASSETS / f"{name}.imageset"
    write_png(imageset / f"{name}.png", rows)
    contents = {
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def write_catalog_metadata() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )

    accent = ASSETS / "AccentColor.colorset"
    accent.mkdir(parents=True, exist_ok=True)
    (accent / "Contents.json").write_text(
        json.dumps(
            {
                "colors": [
                    {
                        "color": {
                            "color-space": "srgb",
                            "components": {
                                "alpha": "1.000",
                                "blue": "1.000",
                                "green": "1.000",
                                "red": "0.000",
                            },
                        },
                        "idiom": "universal",
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n"
    )


def write_app_icon() -> None:
    icon = ASSETS / "AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)

    player = rasterize(SPRITES["player_idle"], 16)
    canvas = [[(0, 0, 0, 255)] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            pixel = player[y][x]
            if pixel[3]:
                canvas[y][x] = pixel
    write_png(icon / "AppIcon-1024.png", scale(canvas, 64))

    (icon / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {
                        "filename": "AppIcon-1024.png",
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024",
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n"
    )


def main() -> None:
    write_catalog_metadata()

    for name, grid in TILES.items():
        write_imageset(name, rasterize(grid, 8))

    for name, grid in SPRITES.items():
        write_imageset(name, rasterize(grid, 16))

    write_app_icon()
    print(f"wrote {len(TILES) + len(SPRITES)} sprites into {ASSETS.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
