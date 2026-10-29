#!/usr/bin/env python3
"""Builds the maze data the game loads: room geometry, doorways, items, spawn.

Input is the community map plus the curated links in `links-overrides.txt`.
Output is `Sources/Wriggler/Resources/Maze/maze.json`, a compact functional
description of the maze - which cells are walkable, where the doors are, and
where the pickups sit. No pixel data is written: the game draws its own tiles.

Walkability is derived from the map's colours. The room art uses a small, fixed
vocabulary, so one 8x8 cell tells us what it is:

    green            floor
    red              brick wall
    blue             water
    yellow + black   the "WAY OUT" signs and other signage
    green + pattern  hedges and planting, which block
    green + grey     a creature or object drawn on top of floor, so floor

That last rule matters: creatures are drawn over the floor, and without it every
creature would punch a hole in the walkable area.

Rooms are 30x16 cells of 8x8 pixels; a cell is one character in the output:

    .  floor        #  brick        v  foliage
    w  water        s  sign

Usage:
    python3 Scripts/build_maze_data.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_links import (  # noqa: E402
    FRAME_H,
    FRAME_W,
    OUT,
    SLOTS,
    apply_overrides,
    build_links,
    find_rooms,
    load_overrides,
    trace,
)

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "Sources" / "Wriggler" / "Resources" / "Maze" / "maze.json"

BORDER = 8
COLUMNS, ROWS = 30, 16
CELL = 8

COLOURS = {
    "green": (0, 204, 0),
    "red": (204, 0, 0),
    "blue": (0, 0, 204),
    "yellow": (204, 204, 0),
    "black": (0, 0, 0),
    "grey": (204, 204, 204),
    "white": (255, 255, 255),
    "magenta": (204, 0, 204),
    "cyan": (0, 204, 204),
}

# Sprite shapes that read as collectable objects rather than creatures, keyed by
# the hash of their white mask (width, height, pixels). Curated by eye from
# Extracted/sprite-sheet.png; see the sprite catalogue in the README.
ITEM_SHAPES = {
    "14b960e95dd6": "tombstone",
    "390383c043db": "tombstone",
    "1e94f0792bf3": "mug",
    "ac827ce69d2e": "bottle",
    "5c9c18a2cf52": "skull",
    "e4e143a62b68": "key",
    "c28ec6d33f1b": "key",
    "2d6009e1ffc0": "key",
    "97eabfd4097c": "key",
    "80a6b2c3c897": "key",
}

START_ROOM = (3, 13)
# The four worms in the start room are drawn in two touching pairs; the player is
# the bottom-left one of the bottom-left pair.
START_POSITION = (9.5, 10.5)


def colour_fractions(cell: np.ndarray) -> dict[str, float]:
    flat = cell.reshape(-1, 3)
    out = {}
    for name, colour in COLOURS.items():
        out[name] = float(np.all(flat == np.array(colour, np.uint8), axis=1).sum()) / flat.shape[0]
    return out


def flat_colour(cell: np.ndarray) -> str | None:
    """The colour name covering most of a cell, if one clearly dominates."""
    fractions = colour_fractions(cell)
    name, share = max(fractions.items(), key=lambda kv: kv[1])
    return name if share >= 0.85 else None


def doorway_cells(slot: int, centre: int, origin: tuple[int, int]) -> list[tuple[int, int]]:
    """Cells on the frame boundary at a measured doorway centre."""
    x0, y0 = origin
    if slot <= 2:      # top
        column = (centre - x0 - BORDER) // CELL
        return [(0, column)]
    if slot <= 5:      # right
        row = (centre - y0 - BORDER) // CELL
        return [(row, COLUMNS - 1)]
    if slot <= 8:      # bottom
        column = (centre - x0 - BORDER) // CELL
        return [(ROWS - 1, column)]
    row = (centre - y0 - BORDER) // CELL
    return [(row, 0)]


def room_floor_colour(img: np.ndarray, origin: tuple[int, int], cells: list[tuple[int, int]]) -> str:
    """The room's floor colour, learned from the cells at its doorways.

    Regions of the map use different palettes - gardens are green, caves are
    black on red rock - so this cannot be a global constant. Every doorway is
    walkable by definition, which makes it the reliable sample point.
    """
    x0, y0 = origin[0] + BORDER, origin[1] + BORDER
    seen: Counter[str] = Counter()
    for row, column in cells:
        if not (0 <= row < ROWS and 0 <= column < COLUMNS):
            continue
        patch = img[y0 + row * CELL : y0 + (row + 1) * CELL, x0 + column * CELL : x0 + (column + 1) * CELL]
        name = flat_colour(patch)
        if name:
            seen[name] += 1
    return seen.most_common(1)[0][0] if seen else "green"


def obstacle_kind(cell: np.ndarray) -> str:
    f = colour_fractions(cell)
    if f["red"] >= 0.40:
        return "#"
    if f["blue"] >= 0.30:
        return "w"
    if f["yellow"] >= 0.15:
        return "s"
    if f["black"] >= 0.50:
        return "#"
    return "v"


def classify_room(img: np.ndarray, origin: tuple[int, int], floor: str, doors: list[tuple[int, int]]) -> list[str]:
    x0, y0 = origin[0] + BORDER, origin[1] + BORDER
    grid = []
    for ty in range(ROWS):
        line = []
        for tx in range(COLUMNS):
            cell = img[y0 + ty * CELL : y0 + (ty + 1) * CELL, x0 + tx * CELL : x0 + (tx + 1) * CELL]
            f = colour_fractions(cell)
            # Floor, or a creature/label drawn on top of floor (which leaves only
            # part of the cell in the floor colour).
            if f[floor] >= 0.30:
                line.append(".")
            else:
                line.append(obstacle_kind(cell))
        grid.append(line)

    # Keep only floor reachable from a doorway: this removes isolated patches
    # that share the floor colour but are sealed off by obstacles.
    return _clamp_to_reachable(grid, doors)


def _clamp_to_reachable(grid: list[list[str]], doors: list[tuple[int, int]]) -> list[list[str]]:
    from collections import deque

    seen = {(row, column) for row, column in doors if grid[row][column] == "."}
    queue = deque(seen)
    while queue:
        row, column = queue.popleft()
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                nxt = (row + dr, column + dc)
                if (
                    0 <= nxt[0] < ROWS
                    and 0 <= nxt[1] < COLUMNS
                    and nxt not in seen
                    and grid[nxt[0]][nxt[1]] == "."
                ):
                    seen.add(nxt)
                    queue.append(nxt)

    # Fill single-cell holes left by the middle of a sprite.
    for _ in range(2):
        fill = []
        for row in range(ROWS):
            for column in range(COLUMNS):
                if (row, column) in seen or grid[row][column] == ".":
                    continue
                around = sum(
                    1
                    for dr in (-1, 0, 1)
                    for dc in (-1, 0, 1)
                    if (dr or dc) and (row + dr, column + dc) in seen
                )
                if around >= 6:
                    fill.append((row, column))
        if not fill:
            break
        seen.update(fill)

    return ["".join("." if (row, column) in seen else grid[row][column] for column in range(COLUMNS))
            for row in range(ROWS)]


def find_items(img: np.ndarray, rooms: dict) -> dict[str, list[dict]]:
    items: dict[str, list[dict]] = {}
    mask_colour = np.array(COLOURS["grey"], np.uint8)
    for (row, column), (x0, y0) in rooms.items():
        area = img[y0 + BORDER : y0 + BORDER + ROWS * CELL, x0 + BORDER : x0 + BORDER + COLUMNS * CELL]
        mask = np.all(area == mask_colour, axis=2)
        labels, _ = ndimage.label(mask, structure=np.ones((3, 3)))
        found = []
        for index, box in enumerate(ndimage.find_objects(labels), start=1):
            if box is None:
                continue
            pixels = int((labels[box] == index).sum())
            height = box[0].stop - box[0].start
            width = box[1].stop - box[1].start
            if not (12 <= pixels <= 500 and 4 <= height <= 28 and 4 <= width <= 32):
                continue
            digest = hashlib.sha1(bytes([width, height]) + mask[box].tobytes()).hexdigest()[:12]
            kind = ITEM_SHAPES.get(digest)
            if kind is None:
                continue
            found.append(
                {
                    "kind": kind,
                    "x": round((box[1].start + width / 2) / CELL, 2),
                    "y": round((box[0].start + height / 2) / CELL, 2),
                }
            )
        if found:
            items[f"{row},{column}"] = sorted(found, key=lambda item: (item["y"], item["x"]))
    return items


def door_for(exit_key, contacts, rooms: dict) -> dict:
    """Position of a doorway along its side, in tiles from the play area origin."""
    row, column, slot = exit_key
    x0, y0 = rooms[(row, column)]
    side = "top" if slot <= 2 else "right" if slot <= 5 else "bottom" if slot <= 8 else "left"
    for entries in contacts.values():
        for contact in entries:
            if contact.room == (row, column) and contact.slot == slot:
                origin = x0 if side in ("top", "bottom") else y0
                return {
                    "side": side,
                    "at": round((contact.centre - origin - BORDER) / CELL, 2),
                    "width": round(contact.width / CELL, 2),
                }
    # Hand-traced exit with no measured band: fall back to the middle of its third.
    third = slot if slot <= 2 else slot - 3 if slot <= 5 else 2 - (slot - 6) if slot <= 8 else 2 - (slot - 9)
    span = (COLUMNS if side in ("top", "bottom") else ROWS) / 3
    return {"side": side, "at": round(span * (third + 0.5), 2), "width": round(span, 2)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", type=Path, default=OUT / "wriggler-map-source.png")
    args = parser.parse_args()

    img = np.asarray(Image.open(args.map).convert("RGB"))
    contacts, rooms = trace(img)
    links = build_links(contacts)

    overrides, deletions = load_overrides(Path(__file__).resolve().parent / "links-overrides.txt")
    problems = apply_overrides(links, overrides, deletions, rooms)

    # Door cells per room, from the measured band centres.
    contacts_by_exit = {}
    for entries in contacts.values():
        for contact in entries:
            contacts_by_exit[(contact.room[0], contact.room[1], contact.slot)] = contact

    exits_by_room: dict[tuple[int, int], list[int]] = {}
    for (row, column, slot) in links:
        exits_by_room.setdefault((row, column), []).append(slot)

    payload_rooms = {}
    tile_counts: Counter[str] = Counter()
    for (row, column), origin in sorted(rooms.items()):
        doors: list[tuple[int, int]] = []
        for slot in exits_by_room.get((row, column), []):
            contact = contacts_by_exit.get((row, column, slot))
            if contact is not None:
                doors.extend(doorway_cells(slot, contact.centre, origin))
        floor = room_floor_colour(img, origin, doors)
        rows = classify_room(img, origin, floor, doors)
        tile_counts.update("".join(rows))
        payload_rooms[f"{row},{column}"] = {"rows": rows, "floor": floor}

    items = find_items(img, rooms)
    for key, found in items.items():
        payload_rooms[key]["items"] = found

    payload_links = {}
    for (row, column, slot), target in sorted(links.items()):
        if not target:
            continue
        payload_links[f"{row},{column},{SLOTS[slot]}"] = {
            "to": f"{target[0]},{target[1]},{SLOTS[target[2]]}",
            **door_for((row, column, slot), contacts, rooms),
        }

    payload = {
        "version": 1,
        "cell": CELL,
        "room": {"columns": COLUMNS, "rows": ROWS},
        "spawn": {"room": f"{START_ROOM[0]},{START_ROOM[1]}", "x": START_POSITION[0], "y": START_POSITION[1]},
        "tiles": {".": "floor", "#": "brick", "v": "foliage", "w": "water", "s": "sign"},
        "rooms": payload_rooms,
        "links": payload_links,
    }
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(json.dumps(payload, separators=(",", ":")))
    size_kb = TARGET.stat().st_size // 1024

    walkable = tile_counts["."]
    total = sum(tile_counts.values())
    print(f"rooms: {len(payload_rooms)}   links: {len(payload_links)}   items: {sum(len(v) for v in items.values())}")
    print(f"tiles: " + ", ".join(f"{k}={v}" for k, v in tile_counts.most_common()))
    print(f"walkable: {walkable / total * 100:.1f}%")
    for problem in problems:
        print(f"  conflict: {problem}")
    print(f"wrote {TARGET.relative_to(ROOT)} ({size_kb} KB)")


if __name__ == "__main__":
    main()
