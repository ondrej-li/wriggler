#!/usr/bin/env python3
"""Traces the room-to-room links of the Wriggler maze.

The map draws every room in a yellow frame and connects exits with thick white
bands routed through the empty space between rooms. Rooms are laid out on a
regular 288x176 grid; each side of a room can carry up to three exits.

An exit is written `row,col,slot`, where slot encodes both the side and which
of the three positions on that side it is:

    0 1 2   top, left to right
    3 4 5   right, top to bottom
    6 7 8   bottom, right to left
    9 a b   left, bottom to top

Links are recovered by connected-component analysis of the white bands: a band
that touches exactly two rooms is a link. Bands that touch only one room are
reported with a `?` destination so they can be filled in by hand.

Usage:
    python3 Scripts/extract_links.py
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Extracted"
ORIGIN_X, ORIGIN_Y = 94, 155
CELL_W, CELL_H = 288, 176
FRAME_W, FRAME_H = 256, 144
BORDER = 8
BRIGHT = np.array([255, 255, 255], np.uint8)

SLOT_LETTERS = "0123456789ab"


def find_rooms(img: np.ndarray) -> dict[tuple[int, int], tuple[int, int]]:
    yellow = np.all(img == np.array([204, 204, 0], np.uint8), axis=2)
    height, width = yellow.shape
    rooms: dict[tuple[int, int], tuple[int, int]] = {}
    for y in range(1, height - FRAME_H):
        xs = np.nonzero(yellow[y])[0]
        if len(xs) < FRAME_W:
            continue
        for run in np.split(xs, np.nonzero(np.diff(xs) > 1)[0] + 1):
            if len(run) != FRAME_W:
                continue
            x0 = int(run[0])
            if yellow[y - 1, x0 : x0 + FRAME_W].mean() > 0.95:
                continue
            bottom = yellow[y + FRAME_H - 1, x0 : x0 + FRAME_W].mean()
            left = yellow[y : y + FRAME_H, x0].mean()
            right = yellow[y : y + FRAME_H, x0 + FRAME_W - 1].mean()
            if bottom > 0.95 and left > 0.6 and right > 0.6:
                column = round((x0 - ORIGIN_X) / CELL_W)
                row = round((y - ORIGIN_Y) / CELL_H)
                if (x0, y) == (ORIGIN_X + column * CELL_W, ORIGIN_Y + row * CELL_H):
                    rooms[(row, column)] = (x0, y)
    return rooms


def slot_for(row: int, column: int, side: str, centre: int, room_xy: tuple[int, int]) -> int:
    """Map a contact position to one of the twelve slots."""
    x0, y0 = room_xy
    # Divided in thirds of the frame, measured from the play area: this matches
    # how the exits read on the map (a band on the play-area edge lands in the
    # first third, not the second).
    if side in ("top", "bottom"):
        third = min(2, max(0, int((centre - x0 - BORDER) / (FRAME_W / 3))))
        return third if side == "top" else 6 + (2 - third)
    third = min(2, max(0, int((centre - y0 - BORDER) / (FRAME_H / 3))))
    return 3 + third if side == "right" else 9 + (2 - third)


def contiguous(mask: np.ndarray, origin: int) -> list[tuple[int, int]]:
    out, start = [], None
    for i, value in enumerate(mask):
        if value and start is None:
            start = i
        elif not value and start is not None:
            out.append((start + origin, i - 1 + origin))
            start = None
    if start is not None:
        out.append((start + origin, len(mask) - 1 + origin))
    return out


def resolve_dead_end(
    component: int, labels: np.ndarray, boxes, rooms: dict, source: tuple[int, int], limit: int = 90
) -> tuple[tuple[int, int], str, int] | None:
    """A route that ends a few pixels short of a frame: snap it to the nearest room."""
    box = boxes[component - 1]
    mask = labels[box] == component
    ys, xs = np.nonzero(mask)
    ys = ys + box[0].start
    xs = xs + box[1].start
    sx, sy = rooms[source]
    far = int(np.argmax((xs - sx - FRAME_W / 2) ** 2 + (ys - sy - FRAME_H / 2) ** 2))
    fx, fy = int(xs[far]), int(ys[far])

    best = None
    for room, (x0, y0) in rooms.items():
        if room == source:
            continue
        left = abs(fx - x0)
        right = abs(fx - (x0 + FRAME_W - 1))
        top = abs(fy - y0)
        bottom = abs(fy - (y0 + FRAME_H - 1))
        inside_x = x0 <= fx <= x0 + FRAME_W - 1
        inside_y = y0 <= fy <= y0 + FRAME_H - 1
        if inside_y:
            for side, distance in (("left", left), ("right", right)):
                if distance < limit and (best is None or distance < best[0]):
                    best = (distance, room, side, fy)
        if inside_x:
            for side, distance in (("top", top), ("bottom", bottom)):
                if distance < limit and (best is None or distance < best[0]):
                    best = (distance, room, side, fx)
    if best is None:
        return None
    _, room, side, centre = best
    return room, side, slot_for(room[0], room[1], side, centre, rooms[room])


def trace(img: np.ndarray) -> tuple[dict, list]:
    bright = np.all(img == BRIGHT, axis=2)
    rooms = find_rooms(img)
    labels, _ = ndimage.label(bright, structure=np.ones((3, 3)))

    # component -> contacts
    boxes = ndimage.find_objects(labels)
    contacts: dict[int, list[tuple[tuple[int, int], str, int, int, int]]] = defaultdict(list)
    for room, (x0, y0) in rooms.items():
        probes = (
            ("top", bright[y0 - 1, x0 : x0 + FRAME_W], x0, y0 - 1, True),
            ("bottom", bright[y0 + FRAME_H, x0 : x0 + FRAME_W], x0, y0 + FRAME_H, True),
            ("left", bright[y0 : y0 + FRAME_H, x0 - 1], y0, x0 - 1, False),
            ("right", bright[y0 : y0 + FRAME_H, x0 + FRAME_W], y0, x0 + FRAME_W, False),
        )
        for side, mask, origin, fixed, horizontal in probes:
            for start, end in contiguous(mask, origin):
                centre = (start + end) / 2
                component = (
                    labels[fixed, int(centre)] if horizontal else labels[int(centre), fixed]
                )
                if component == 0:
                    continue
                contacts[int(component)].append(
                    (room, side, slot_for(room[0], room[1], side, int(centre), (x0, y0)), int(centre), end - start + 1)
                )
    # Routes that stop short of the frame: snap to the nearest room.
    for component, items in list(contacts.items()):
        if len(items) != 1:
            continue
        guess = resolve_dead_end(component, labels, boxes, rooms, items[0][0])
        if guess is not None:
            room, side, slot = guess
            contacts[component].append((room, side, slot, 0, 0))

    return contacts, list(rooms)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", type=Path, default=OUT / "wriggler-map-source.png")
    args = parser.parse_args()

    img = np.asarray(Image.open(args.map).convert("RGB"))
    contacts, room_keys = trace(img)
    rooms = find_rooms(img)

    links: dict[tuple[int, int, int], tuple[int, int, int] | None] = {}
    for component, items in contacts.items():
        if len(items) == 2:
            (a, _, slot_a, _, _), (b, _, slot_b, _, _) = items
            links[(a[0], a[1], slot_a)] = (b[0], b[1], slot_b)
            links[(b[0], b[1], slot_b)] = (a[0], a[1], slot_a)
        else:
            for room, _, slot, _, _ in items:
                links.setdefault((room[0], room[1], slot), None)

    def fmt(entry: tuple[int, int, int] | None) -> str:
        if entry is None:
            return "?,?,?"
        return f"{entry[0]},{entry[1]},{SLOT_LETTERS[entry[2]]}"

    lines = []
    for key in sorted(links):
        row, column, slot = key
        lines.append(f"{row},{column},{SLOT_LETTERS[slot]} -> {fmt(links[key])}")

    (OUT / "maze-links.txt").write_text("\n".join(lines) + "\n")
    # sanity: no self-links, no duplicate slots
    self_links = [k for k, v in links.items() if v is not None and (v[0], v[1]) == (k[0], k[1])]
    if self_links:
        print(f"dropping {len(self_links)} self-links: {self_links[:5]}")
        for key in self_links:
            links[key] = None
    resolved = sum(1 for v in links.values() if v is not None)
    print(f"exits: {len(links)}  resolved: {resolved}  unknown: {len(links) - resolved}")

    graph = {
        "convention": {
            "room": "row,column with 0,0 at the top-left of the map",
            "slot": {
                "0-2": "top, left to right",
                "3-5": "right, top to bottom",
                "6-8": "bottom, right to left",
                "9,a,b": "left, bottom to top",
            },
        },
        "grid": {
            "rows": max(r for r, _ in room_keys) + 1,
            "columns": max(c for _, c in room_keys) + 1,
            "rooms": len(rooms),
        },
        "links": {f"{r},{c},{SLOT_LETTERS[s]}": (fmt(v) if v else None) for (r, c, s), v in sorted(links.items())},
    }
    (OUT / "maze-links.json").write_text(json.dumps(graph, indent=1))
    print("wrote Extracted/maze-links.txt and Extracted/maze-links.json")

    # Visual check: draw every recovered link as a straight line between rooms.
    scale = 6
    canvas = Image.fromarray(img).resize((img.shape[1] // scale, img.shape[0] // scale), Image.LANCZOS)
    canvas = canvas.point(lambda v: int(v * 0.35))
    draw = ImageDraw.Draw(canvas)
    for (row, column, slot), target in links.items():
        if target is None:
            continue
        x0, y0 = rooms[(row, column)]
        x1, y1 = rooms[(target[0], target[1])]
        draw.line(
            [(x0 + FRAME_W // 2) // scale, (y0 + FRAME_H // 2) // scale,
             (x1 + FRAME_W // 2) // scale, (y1 + FRAME_H // 2) // scale],
            fill=(0, 255, 0),
            width=1,
        )
    canvas.save(OUT / "links-overlay.png")
    print("wrote Extracted/links-overlay.png")


if __name__ == "__main__":
    main()
