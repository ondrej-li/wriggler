#!/usr/bin/env python3
"""Extracts the Wriggler maze and its artwork from the community map.

The ZX Spectrum original is a single-screen-at-a-time maze: each "room" is one
30x16 cell view, and rooms are connected by marked passages. The stitched map on
maps.speccy.cz draws every room with a yellow frame plus white connector lines
showing which room leads to which.

This script turns that map back into data the port can use:

* every room cropped to its play area
* a deduplicated tile set (8x8 cells, in ZX Spectrum colours)
* the creatures and props that are drawn over the tiles
* a JSON index of rooms and their tile grids

Nothing here is shipped in the app - the output lands in `Extracted/`, which is
git-ignored, because the artwork belongs to the original game's authors. It is
reference material for building new art, not an asset to redistribute.

Usage:
    python3 Scripts/extract_map.py                # use/download the map
    python3 Scripts/extract_map.py --map foo.png
"""

from __future__ import annotations

import argparse
import json
import struct
import urllib.request
import zlib
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Extracted"
MAP_URL = "https://maps.speccy.cz/maps/Wriggler.png"

# Geometry of the stitched map, measured from the image itself.
ORIGIN_X, ORIGIN_Y = 94, 155
CELL_W, CELL_H = 288, 176        # room pitch
FRAME = 256, 144                 # yellow frame around each room
BORDER = 8                       # frame thickness
TILES_X, TILES_Y = 30, 16        # play area in 8x8 cells

YELLOW = np.array([204, 204, 0], np.uint8)
WHITE = np.array([204, 204, 204], np.uint8)
BLACK = np.array([0, 0, 0], np.uint8)


def ensure_map(path: Path) -> Path:
    if not path.exists():
        print(f"downloading {MAP_URL}")
        path.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(MAP_URL, path)
    return path


def find_rooms(img: np.ndarray) -> dict[tuple[int, int], tuple[int, int]]:
    """Locate every room frame and snap it to the grid."""
    yellow = np.all(img == YELLOW, axis=2)
    height, width = yellow.shape
    rooms: dict[tuple[int, int], tuple[int, int]] = {}

    for y in range(1, height - FRAME[1]):
        xs = np.nonzero(yellow[y])[0]
        if len(xs) < FRAME[0]:
            continue
        for run in np.split(xs, np.nonzero(np.diff(xs) > 1)[0] + 1):
            if len(run) != FRAME[0]:
                continue
            x0 = int(run[0])
            # Only treat this as a top edge, and require the frame to close up.
            if yellow[y - 1, x0 : x0 + FRAME[0]].mean() > 0.95:
                continue
            bottom = yellow[y + FRAME[1] - 1, x0 : x0 + FRAME[0]].mean()
            left = yellow[y : y + FRAME[1], x0].mean()
            right = yellow[y : y + FRAME[1], x0 + FRAME[0] - 1].mean()
            if bottom > 0.95 and left > 0.6 and right > 0.6:
                column = round((x0 - ORIGIN_X) / CELL_W)
                row = round((y - ORIGIN_Y) / CELL_H)
                if (x0, y) == (ORIGIN_X + column * CELL_W, ORIGIN_Y + row * CELL_H):
                    rooms[(column, row)] = (x0, y)
    return rooms


def play_area(img: np.ndarray, x0: int, y0: int) -> np.ndarray:
    return img[y0 + BORDER : y0 + FRAME[1] - BORDER, x0 + BORDER : x0 + FRAME[0] - BORDER]


def cut_tiles(area: np.ndarray) -> list[bytes]:
    tiles = []
    for ty in range(TILES_Y):
        for tx in range(TILES_X):
            block = area[ty * 8 : ty * 8 + 8, tx * 8 : tx * 8 + 8]
            tiles.append(block.tobytes())
    return tiles


def png(path: Path, rows: np.ndarray, scale: int = 1) -> None:
    image = Image.fromarray(rows)
    if scale > 1:
        image = image.resize((image.width * scale, image.height * scale), Image.NEAREST)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", type=Path, default=OUT / "wriggler-map-source.png")
    parser.add_argument("--scale", type=int, default=3, help="zoom factor for contact sheets")
    args = parser.parse_args()

    map_path = ensure_map(args.map)
    img = np.asarray(Image.open(map_path).convert("RGB"))
    print(f"map {map_path.name}: {img.shape[1]}x{img.shape[0]}")

    rooms = find_rooms(img)
    columns = max(c for c, _ in rooms) + 1
    rows = max(r for _, r in rooms) + 1
    print(f"rooms: {len(rooms)} on a {columns}x{rows} grid")

    OUT.mkdir(exist_ok=True)

    # --- rooms -------------------------------------------------------------
    room_dir = OUT / "rooms"
    for (c, r), (x0, y0) in rooms.items():
        png(room_dir / f"room_c{c:02d}_r{r:02d}.png", play_area(img, x0, y0), 2)
    print(f"wrote {len(rooms)} room images to {room_dir.relative_to(ROOT)}")

    # --- tile set ----------------------------------------------------------
    counts: Counter[bytes] = Counter()
    grids: dict[str, list[str]] = {}
    for (c, r), (x0, y0) in rooms.items():
        tiles = cut_tiles(play_area(img, x0, y0))
        counts.update(tiles)
        grids[f"{c},{r}"] = tiles

    palette: dict[bytes, str] = {}
    ordered = [blob for blob, n in counts.most_common() if n >= 8]
    for i, blob in enumerate(ordered):
        palette[blob] = f"t{i:03d}"

    sheet_cols = 16
    sheet_rows = (len(ordered) + sheet_cols - 1) // sheet_cols
    sheet = Image.new("RGB", (sheet_cols * 8, sheet_rows * 8), (24, 24, 24))
    for i, blob in enumerate(ordered):
        sheet.paste(Image.frombytes("RGB", (8, 8), blob), ((i % sheet_cols) * 8, (i // sheet_cols) * 8))
    sheet.resize((sheet.width * args.scale, sheet.height * args.scale), Image.NEAREST).save(OUT / "tileset.png")
    print(f"tileset: {len(counts)} distinct tiles, {len(ordered)} kept (>=8 uses) -> Extracted/tileset.png")

    # --- creatures and props ----------------------------------------------
    # They are drawn in white over the tiles, so each white blob is a sprite.
    sprites = []
    for (c, r), (x0, y0) in rooms.items():
        area = play_area(img, x0, y0)
        mask = np.all(area == WHITE, axis=2)
        labels, n = ndimage.label(mask, structure=np.ones((3, 3)))
        for index, box in enumerate(ndimage.find_objects(labels), start=1):
            if box is None:
                continue
            pixels = int((labels[box] == index).sum())
            h = box[0].stop - box[0].start
            w = box[1].stop - box[1].start
            if 12 <= pixels <= 500 and 4 <= h <= 28 and 4 <= w <= 32:
                sprites.append((c, r, x0 + BORDER + box[1].start, y0 + BORDER + box[0].start, w, h, pixels))

    groups: dict[tuple[int, int, bytes], list] = defaultdict(list)
    for c, r, x, y, w, h, pixels in sprites:
        blob = np.all(img[y : y + h, x : x + w] == WHITE, axis=2)
        groups[(h, w, blob.tobytes())].append((c, r, x, y, w, h, pixels))

    sprite_dir = OUT / "sprites"
    sprite_dir.mkdir(parents=True, exist_ok=True)
    catalogue = []
    for rank, (key, items) in enumerate(sorted(groups.items(), key=lambda kv: -len(kv[1]))[:16]):
        h, w, _ = key
        c, r, x, y, _, _, pixels = items[0]
        context = Image.fromarray(img[max(0, y - 2) : y + h + 2, max(0, x - 2) : x + w + 2])
        context.resize((context.width * 4, context.height * 4), Image.NEAREST).save(
            sprite_dir / f"sprite_{rank:02d}_{w}x{h}.png"
        )
        catalogue.append(
            {
                "rank": rank,
                "size": [w, h],
                "count": len(items),
                "example": {"room": [c, r], "x": x, "y": y},
                "rooms": sorted({f"{c},{r}" for c, r, *_ in items}),
            }
        )
    print(f"sprites: {len(sprites)} white blobs in {len(groups)} distinct shapes -> Extracted/sprites/")

    # --- index -------------------------------------------------------------
    index = {
        "source": MAP_URL,
        "grid": {"columns": columns, "rows": rows, "origin": [ORIGIN_X, ORIGIN_Y], "pitch": [CELL_W, CELL_H]},
        "playArea": {"tiles": [TILES_X, TILES_Y], "pixels": [FRAME[0] - 2 * BORDER, FRAME[1] - 2 * BORDER]},
        "rooms": {f"{c},{r}": {"x": x, "y": y} for (c, r), (x, y) in sorted(rooms.items())},
        "tilePalette": {name: blob.hex() for blob, name in palette.items()},
        "roomTiles": {key: [palette.get(t, "unknown") for t in tiles] for key, tiles in grids.items()},
        "actors": catalogue,
    }
    (OUT / "maze.json").write_text(json.dumps(index, indent=1))
    print("wrote Extracted/maze.json")

    # --- annotated overview ------------------------------------------------
    overview = Image.fromarray(img).resize((img.shape[1] // 8, img.shape[0] // 8), Image.NEAREST)
    draw = ImageDraw.Draw(overview)
    for (c, r), (x0, y0) in rooms.items():
        draw.text((x0 // 8 + 2, y0 // 8 + 2), f"{c},{r}", fill=(255, 255, 255))
    overview.save(OUT / "map-indexed.png")
    print("wrote Extracted/map-indexed.png")


if __name__ == "__main__":
    main()
