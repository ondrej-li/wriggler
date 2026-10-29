#!/usr/bin/env python3
"""Rebuilds each room's artwork from the map, as an atlas plus sprites.

The rooms are drawn from a small set of repeated 8x8 tiles; the creatures,
flowers and props are pasted on top. This script splits the two apart:

1. Every cell that exactly matches a frequently-reused tile is background, and
   the tile goes into an atlas. 331 tiles reproduce 98.9% of all 117,120 cells.
2. Cells that match nothing are the ones with something drawn over them. Their
   background is guessed from the neighbouring cells, and the pixels that differ
   become part of a sprite.
3. Overlapping sprite pixels are grouped into components, cropped, and
   deduplicated, so the output is a sprite atlas plus a list of placements.

The result has no transparency problems and no baked-in enemies: the game can
skip a category and the sprite simply is not drawn.

Usage:
    python3 Scripts/build_room_art.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_links import find_rooms  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Extracted"
# The game loads these; they are the reconstructed room art.
RESOURCES = ROOT / "Sources" / "Wriggler" / "Resources" / "RoomArt"
BORDER = 8
CELL = 8
COLUMNS, ROWS = 30, 16
MIN_TILE_USES = 4


def load_rooms(img: np.ndarray) -> dict[tuple[int, int], np.ndarray]:
    rooms = {}
    for (row, column), (x0, y0) in find_rooms(img).items():
        rooms[(row, column)] = img[
            y0 + BORDER : y0 + BORDER + ROWS * CELL,
            x0 + BORDER : x0 + BORDER + COLUMNS * CELL,
        ]
    return rooms


def build_atlas(rooms: dict[tuple[int, int], np.ndarray]) -> tuple[list[bytes], dict[bytes, int]]:
    counts: Counter[bytes] = Counter()
    for area in rooms.values():
        for row in range(ROWS):
            for column in range(COLUMNS):
                cell = area[row * CELL : (row + 1) * CELL, column * CELL : (column + 1) * CELL]
                counts[cell.tobytes()] += 1
    ordered = [cell for cell, uses in counts.most_common() if uses >= MIN_TILE_USES]
    return ordered, {cell: index for index, cell in enumerate(ordered)}


def cell_bytes(area: np.ndarray, row: int, column: int) -> bytes:
    return area[row * CELL : (row + 1) * CELL, column * CELL : (column + 1) * CELL].tobytes()


def background_for(area: np.ndarray, lookup: dict[bytes, int]) -> tuple[np.ndarray, list[int]]:
    """Match each cell to an atlas tile, guessing neighbours' tiles for overlays."""
    indices: list[list[int]] = [[-1] * COLUMNS for _ in range(ROWS)]
    overlay = np.zeros((ROWS, COLUMNS), dtype=bool)

    for row in range(ROWS):
        for column in range(COLUMNS):
            match = lookup.get(cell_bytes(area, row, column))
            if match is not None:
                indices[row][column] = match
            else:
                overlay[row][column] = True

    # Fill the gaps from the neighbours: rooms are locally uniform, so this puts
    # the right floor or wall behind a creature.
    for _ in range(3):
        changed = False
        for row in range(ROWS):
            for column in range(COLUMNS):
                if indices[row][column] != -1:
                    continue
                votes = Counter()
                for dr in (-1, 0, 1):
                    for dc in (-1, 0, 1):
                        rr, cc = row + dr, column + dc
                        if 0 <= rr < ROWS and 0 <= cc < COLUMNS and indices[rr][cc] != -1:
                            votes[indices[rr][cc]] += 1
                if votes:
                    indices[row][column] = votes.most_common(1)[0][0]
                    changed = True
        if not changed:
            break

    return np.array(indices, dtype=np.int32), overlay


def extract_sprites(area: np.ndarray, indices: np.ndarray, overlay: np.ndarray, atlas: list[bytes]):
    """Return (mask, colour image) pairs for whatever is drawn over the tiles."""
    diff = np.zeros((ROWS * CELL, COLUMNS * CELL), dtype=bool)
    for row in range(ROWS):
        for column in range(COLUMNS):
            if not overlay[row, column] or indices[row, column] < 0:
                continue
            tile = np.frombuffer(atlas[indices[row, column]], dtype=np.uint8).reshape(CELL, CELL, 3)
            cell = area[row * CELL : (row + 1) * CELL, column * CELL : (column + 1) * CELL]
            # Pixels that differ from the background tile are the overlay.
            diff[row * CELL : (row + 1) * CELL, column * CELL : (column + 1) * CELL] = np.any(cell != tile, axis=2)

    if not diff.any():
        return []

    merged = ndimage.binary_dilation(diff, np.ones((3, 3)))
    labels, count = ndimage.label(merged, structure=np.ones((3, 3)))
    sprites = []
    for index, box in enumerate(ndimage.find_objects(labels), start=1):
        if box is None:
            continue
        component = labels[box] == index
        sprite_mask = component & diff[box]
        if sprite_mask.sum() < 6:
            continue
        height = box[0].stop - box[0].start
        width = box[1].stop - box[1].start
        if height > 64 or width > 64:
            continue
        pixels = area[box]
        sprites.append((sprite_mask, pixels, box[1].start, box[0].start))
    return sprites


def categorise(mask: np.ndarray, pixels: np.ndarray) -> str:
    """Rough grouping by colour; refined by the curated table in the game."""
    colours = pixels[mask]
    if colours.size == 0:
        return "other"
    unique, counts = np.unique(colours.reshape(-1, 3), axis=0, return_counts=True)
    dominant = unique[counts.argmax()]
    grey = np.array([204, 204, 204])
    magenta = np.array([204, 0, 204])
    yellow = np.array([204, 204, 0])
    blue = np.array([0, 0, 204])
    cyan = np.array([0, 204, 204])

    def share(colour):
        return float(np.all(colours == colour, axis=1).sum()) / colours.shape[0]

    if share(grey) > 0.5:
        return "white"
    if share(magenta) + share(yellow) > 0.25:
        return "flower"
    if share(blue) + share(cyan) > 0.25:
        return "plant"
    if tuple(int(v) for v in dominant) == (0, 0, 0):
        return "black"
    return "other"


def pack_indices(indices: np.ndarray) -> str:
    """Rooms are a 30x16 grid of atlas indices; base64 of uint16 halves the JSON."""
    import base64

    return base64.b64encode(indices.astype("<u2").tobytes()).decode("ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", type=Path, default=OUT / "wriggler-map-source.png")
    parser.add_argument("--resources", type=Path, default=RESOURCES)
    args = parser.parse_args()

    img = np.asarray(Image.open(args.map).convert("RGB"))
    rooms = load_rooms(img)
    atlas, lookup = build_atlas(rooms)
    print(f"atlas: {len(atlas)} tiles from {len(rooms)} rooms")

    art_dir = OUT / "roomart"
    art_dir.mkdir(parents=True, exist_ok=True)

    # --- tile atlas image -------------------------------------------------
    TILE_COLUMNS = 24
    SPRITE_COLUMNS = 12
    sprite_cell = 64

    rows = (len(atlas) + TILE_COLUMNS - 1) // TILE_COLUMNS
    tiles_sheet = Image.new("RGB", (TILE_COLUMNS * CELL, rows * CELL), (0, 0, 0))
    for index, blob in enumerate(atlas):
        tile = Image.frombytes("RGB", (CELL, CELL), blob)
        tiles_sheet.paste(tile, ((index % TILE_COLUMNS) * CELL, (index // TILE_COLUMNS) * CELL))
    tiles_sheet.save(art_dir / "tiles.png")

    # --- sprites ----------------------------------------------------------
    shapes: dict[str, int] = {}
    shape_pixels: list[tuple[np.ndarray, np.ndarray]] = []
    placements: dict[str, list[dict]] = {}
    categories: dict[str, Counter] = defaultdict(Counter)
    stats = Counter()

    room_tiles = {}
    for key, area in sorted(rooms.items()):
        indices, overlay = background_for(area, lookup)
        stats["overlay cells"] += int(overlay.sum())

        room_tiles[f"{key[0]},{key[1]}"] = indices
        entries = []
        for mask, pixels, x, y in extract_sprites(area, indices, overlay, atlas):
            digest = hashlib.sha1(bytes([mask.shape[1], mask.shape[0]]) + np.packbits(mask).tobytes()).hexdigest()[:12]
            if digest not in shapes:
                shapes[digest] = len(shape_pixels)
                shape_pixels.append((mask, pixels))
                categories[digest][categorise(mask, pixels)] += 1
            entries.append(
                {
                    "shape": shapes[digest],
                    "x": round(x / CELL, 3),
                    "y": round(y / CELL, 3),
                    "w": round(mask.shape[1] / CELL, 3),
                    "h": round(mask.shape[0] / CELL, 3),
                }
            )
        if entries:
            placements[f"{key[0]},{key[1]}"] = entries

    # --- sprite atlas -----------------------------------------------------
    rows = (len(shape_pixels) + SPRITE_COLUMNS - 1) // SPRITE_COLUMNS
    sprite_sheet = Image.new("RGBA", (SPRITE_COLUMNS * sprite_cell, rows * sprite_cell), (0, 0, 0, 0))
    bounds = []
    for index, (mask, pixels) in enumerate(shape_pixels):
        height, width = mask.shape
        sprite = np.zeros((height, width, 4), dtype=np.uint8)
        sprite[..., :3] = pixels
        sprite[..., 3] = np.where(mask, 255, 0)
        image = Image.fromarray(sprite, "RGBA")
        x, y = (index % SPRITE_COLUMNS) * sprite_cell, (index // SPRITE_COLUMNS) * sprite_cell
        sprite_sheet.paste(image, (x, y))
        bounds.append({"x": x, "y": y, "w": width, "h": height})
    sprite_sheet.save(art_dir / "sprites.png")

    payload = {
        "cell": CELL,
        "columns": COLUMNS,
        "rows": ROWS,
        "tiles": {"columns": TILE_COLUMNS, "count": len(atlas), "stride": CELL},
        "sprites": {"cell": sprite_cell, "columns": SPRITE_COLUMNS, "count": len(shape_pixels), "bounds": bounds},
        "rooms": {
            key: {"tiles": pack_indices(tiles), "sprites": placements.get(key, [])}
            for key, tiles in sorted(room_tiles.items())
        },
    }
    (art_dir / "roomart.json").write_text(json.dumps(payload, separators=(",", ":")))

    # --- publish to the app -------------------------------------------------
    args.resources.mkdir(parents=True, exist_ok=True)
    tiles_sheet.save(args.resources / "tiles.png")
    sprite_sheet.save(args.resources / "sprites.png")
    (args.resources / "roomart.json").write_text(json.dumps(payload, separators=(",", ":")))
    print(f"published room art to {args.resources.relative_to(ROOT)}")

    print(f"sprites: {len(shape_pixels)} distinct shapes, {sum(len(v) for v in placements.values())} placements")
    print(f"overlay cells: {stats['overlay cells']} of {len(rooms) * COLUMNS * ROWS}")
    print("colour groups:", Counter(categories[d].most_common(1)[0][0] for d in shapes).most_common())
    size = sum(p.stat().st_size for p in art_dir.iterdir())
    print(f"wrote {art_dir.relative_to(ROOT)} ({size // 1024} KB)")

    # --- reconstruction check --------------------------------------------
    check = Image.new("RGB", (COLUMNS * CELL, ROWS * CELL))
    for key in [k for k in rooms if k in {(3, 13), (0, 0)}]:
        indices, _ = background_for(rooms[key], lookup)
        marker = Image.new("RGB", (COLUMNS * CELL, ROWS * CELL))
        for row in range(ROWS):
            for column in range(COLUMNS):
                index = indices[row][column]
                if index >= 0:
                    marker.paste(Image.frombytes("RGB", (CELL, CELL), atlas[index]), (column * CELL, row * CELL))
        output = Image.new("RGB", (COLUMNS * CELL * 2 + 8, ROWS * CELL), (40, 40, 40))
        output.paste(Image.fromarray(rooms[key]), (0, 0))
        output.paste(marker, (COLUMNS * CELL + 8, 0))
        output.resize((output.width * 3, output.height * 3), Image.NEAREST).save(
            art_dir / f"check-{key[0]}-{key[1]}.png"
        )
    print("wrote reconstruction checks")


if __name__ == "__main__":
    main()
