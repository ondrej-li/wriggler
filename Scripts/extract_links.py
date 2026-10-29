#!/usr/bin/env python3
"""Traces the room-to-room links of the Wriggler maze.

The map draws every room in a yellow frame and connects exits with thick white
bands routed through the empty space between rooms. Rooms sit on a regular
288x176 grid; each side of a room can carry up to three exits.

An exit is written `row,col,slot`, with `0,0` at the top-left of the map and the
slot encoding both the side and the position on it:

    0 1 2   top, left to right
    3 4 5   right, top to bottom
    6 7 8   bottom, right to left
    9 a b   left, bottom to top

Links come from connected-component analysis: a band that touches exactly two
rooms joins them. Positions are bucketed into thirds of the frame, measured from
the play area.

Bands that touch only one room are left unresolved (`?`) rather than guessed at;
that is what `Scripts/links-overrides.txt` is for. The override file holds
hand-traced links and wins over the automatic result, so the script stays
reproducible while the curated data stays authoritative.

Usage:
    python3 Scripts/extract_links.py
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Extracted"
OVERRIDES = Path(__file__).resolve().parent / "links-overrides.txt"

ORIGIN_X, ORIGIN_Y = 94, 155
CELL_W, CELL_H = 288, 176
FRAME_W, FRAME_H = 256, 144
BORDER = 8
BRIGHT = np.array([255, 255, 255], np.uint8)
YELLOW = np.array([204, 204, 0], np.uint8)

SLOTS = "0123456789ab"

Key = tuple[int, int, int]  # row, column, slot


@dataclass(frozen=True)
class Contact:
    """Where one end of a route meets a room frame."""

    room: tuple[int, int]
    side: str
    slot: int
    # Centre of the band along the side, in map pixels (x for top/bottom, y for left/right).
    centre: int
    # Width of the band in pixels.
    width: int

    @property
    def key(self) -> tuple[int, int, int]:
        return (self.room[0], self.room[1], self.slot)


def find_rooms(img: np.ndarray) -> dict[tuple[int, int], tuple[int, int]]:
    """Locate every room frame, keyed by (row, column)."""
    yellow = np.all(img == YELLOW, axis=2)
    height, _ = yellow.shape
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
                continue  # not a top edge
            bottom = yellow[y + FRAME_H - 1, x0 : x0 + FRAME_W].mean()
            left = yellow[y : y + FRAME_H, x0].mean()
            right = yellow[y : y + FRAME_H, x0 + FRAME_W - 1].mean()
            if bottom > 0.95 and left > 0.6 and right > 0.6:
                column = round((x0 - ORIGIN_X) / CELL_W)
                row = round((y - ORIGIN_Y) / CELL_H)
                if (x0, y) == (ORIGIN_X + column * CELL_W, ORIGIN_Y + row * CELL_H):
                    rooms[(row, column)] = (x0, y)
    return rooms


def slot_for(side: str, centre: int, room_xy: tuple[int, int]) -> int:
    x0, y0 = room_xy
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


def trace(img: np.ndarray) -> tuple[dict[int, list[Contact]], dict]:
    """Return, per white band, the frame contacts it makes."""
    bright = np.all(img == BRIGHT, axis=2)
    rooms = find_rooms(img)
    labels, _ = ndimage.label(bright, structure=np.ones((3, 3)))

    contacts: dict[int, list[Contact]] = defaultdict(list)
    for room, (x0, y0) in rooms.items():
        probes = (
            ("top", bright[y0 - 1, x0 : x0 + FRAME_W], x0, y0 - 1, True),
            ("bottom", bright[y0 + FRAME_H, x0 : x0 + FRAME_W], x0, y0 + FRAME_H, True),
            ("left", bright[y0 : y0 + FRAME_H, x0 - 1], y0, x0 - 1, False),
            ("right", bright[y0 : y0 + FRAME_H, x0 + FRAME_W], y0, x0 + FRAME_W, False),
        )
        for side, mask, origin, fixed, horizontal in probes:
            for start, end in contiguous(mask, origin):
                centre = int((start + end) / 2)
                band = labels[fixed, centre] if horizontal else labels[centre, fixed]
                if band == 0:
                    continue
                contact = Contact(
                    room=room,
                    side=side,
                    slot=slot_for(side, centre, (x0, y0)),
                    centre=centre,
                    width=end - start + 1,
                )
                if (contact.room, contact.slot) not in {(c.room, c.slot) for c in contacts[int(band)]}:
                    contacts[int(band)].append(contact)
    return contacts, rooms


def build_links(contacts: dict[int, list]) -> dict[Key, Key | None]:
    links: dict[Key, Key | None] = {}
    for _, entries in contacts.items():
        if len(entries) == 2:
            first, second = entries
            a = first.key
            b = second.key
            links[a] = b
            links[b] = a
        else:
            for contact in entries:
                links.setdefault(contact.key, None)
    return links


def parse_key(text: str) -> Key:
    row, column, slot = [part.strip() for part in text.split(",")]
    if slot not in SLOTS:
        raise ValueError(f"bad slot {slot!r} in {text!r}")
    return (int(row), int(column), SLOTS.index(slot))


def format_key(key: Key | None) -> str:
    if key is None:
        return "?,?,?"
    return f"{key[0]},{key[1]},{SLOTS[key[2]]}"


def load_overrides(path: Path) -> tuple[list[tuple[Key, Key]], list[Key]]:
    """Read hand-traced links and deletions. `-row,col,slot` drops a slot."""
    pairs: list[tuple[Key, Key]] = []
    deletions: list[Key] = []
    if not path.exists():
        return pairs, deletions
    for number, raw in enumerate(path.read_text().splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("-"):
            deletions.append(parse_key(line[1:]))
        elif "->" in line:
            source, target = line.split("->", 1)
            pairs.append((parse_key(source), parse_key(target)))
        else:
            raise ValueError(f"{path.name}:{number}: cannot parse {raw!r}")
    return pairs, deletions


def apply_overrides(
    links: dict[Key, Key | None],
    pairs: list[tuple[Key, Key]],
    deletions: list[Key],
    rooms: dict,
) -> list[str]:
    problems: list[str] = []

    for key in deletions:
        links.pop(key, None)
        for other, target in list(links.items()):
            if target == key:
                links[other] = None

    for source, target in pairs:
        missing = [key for key in (source, target) if (key[0], key[1]) not in rooms]
        for key in missing:
            problems.append(f"{format_key(key)}: room does not exist")
        if missing:
            continue

        current = links.get(source)
        if current is not None and current != target:
            problems.append(
                f"{format_key(source)}: traced to {format_key(current)}, override says {format_key(target)}"
            )
        back = links.get(target)
        if back is not None and back != source:
            problems.append(
                f"{format_key(target)}: traced to {format_key(back)}, override says {format_key(source)}"
            )
        links[source] = target
        links[target] = source
    return problems


def format_key_list(links: dict[Key, Key | None]) -> list[str]:
    return [f"{format_key(key)} -> {format_key(target)}" for key, target in sorted(links.items())]


def draw_overlay(img: np.ndarray, rooms: dict, links: dict[Key, Key | None]) -> None:
    scale = 6
    canvas = Image.fromarray(img).resize((img.shape[1] // scale, img.shape[0] // scale), Image.LANCZOS)
    canvas = canvas.point(lambda value: int(value * 0.35))
    draw = ImageDraw.Draw(canvas)
    for (row, column, _), target in links.items():
        if target is None:
            continue
        x0, y0 = rooms[(row, column)]
        x1, y1 = rooms[(target[0], target[1])]
        draw.line(
            [
                (x0 + FRAME_W // 2) // scale,
                (y0 + FRAME_H // 2) // scale,
                (x1 + FRAME_W // 2) // scale,
                (y1 + FRAME_H // 2) // scale,
            ],
            fill=(0, 255, 0),
            width=1,
        )
    canvas.save(OUT / "links-overlay.png")
    print("wrote Extracted/links-overlay.png")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", type=Path, default=OUT / "wriggler-map-source.png")
    parser.add_argument("--overrides", type=Path, default=OVERRIDES)
    args = parser.parse_args()

    img = np.asarray(Image.open(args.map).convert("RGB"))
    contacts, rooms = trace(img)
    links = build_links(contacts)

    pairs, deletions = load_overrides(args.overrides)
    problems = apply_overrides(links, pairs, deletions, rooms)

    (OUT / "maze-links.txt").write_text("\n".join(format_key_list(links)) + "\n")

    resolved = sum(1 for value in links.values() if value is not None)
    print(f"rooms: {len(rooms)}   bands: {len(contacts)}   exits: {len(links)}")
    print(f"resolved: {resolved}   unknown: {len(links) - resolved}")
    print(f"overrides: {len(pairs)} links, {len(deletions)} deletions")
    for problem in problems:
        print(f"  conflict: {problem}")

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
            "rows": max(row for row, _ in rooms) + 1,
            "columns": max(column for _, column in rooms) + 1,
            "rooms": len(rooms),
        },
        "stats": {"exits": len(links), "resolved": resolved, "unknown": len(links) - resolved},
        "links": {
            format_key(key): (format_key(value) if value else None) for key, value in sorted(links.items())
        },
    }
    (OUT / "maze-links.json").write_text(json.dumps(graph, indent=1))
    print("wrote Extracted/maze-links.txt and Extracted/maze-links.json")

    if problems:
        (OUT / "maze-links-conflicts.txt").write_text("\n".join(problems) + "\n")
        print("wrote Extracted/maze-links-conflicts.txt")
    draw_overlay(img, rooms, links)


if __name__ == "__main__":
    main()
