#!/usr/bin/env python3
"""Pulls the loading screen and a memory map out of `resources/Wriggler.tzx`.

The tape is a plain TZX v1.0 with standard-speed blocks, no custom loader
metadata, so it can be read straight through:

    0  header   "wriggler"  BASIC program, 273 bytes
    1  data     the first-stage loader
    2  header   machine code, 2200 bytes
    3  data     the second-stage loader
    4  data     the loading screen (6912 bytes, the usual 0x4000 SCREEN$)
    5  data     everything else: 41768 bytes that fill 0x5CD8..0xFFFF

Block 5 is the game itself. It is plain memory - the first ~26 KB is artwork,
tile data and tables, the last ~15 KB is Z80 code (a linear sweep of the upper
half shows the usual 40%+ opcode density, and it reads `LD A,(0x5C78)` for the
frame counter and `IN A,(0x7FFE)` for the keyboard).

Outputs (git-ignored, the artwork stays the authors'):

    Extracted/loading-screen.png   the loading screen, 2x
    Extracted/memory.bin           the 48K image that would be in RAM
    Extracted/tape.json            block table + segmentation report

Usage:
    python3 Scripts/extract_tape.py
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Extracted"
LOAD_ADDRESS = 0x5CD8  # block 5 lands here and runs exactly to 0xFFFF

ZX_PALETTE = [
    (0, 0, 0), (0, 0, 205), (205, 0, 0), (205, 0, 205),
    (0, 205, 0), (0, 205, 205), (205, 205, 0), (205, 205, 205),
    (0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
    (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255),
]

# Opcodes that make up a large share of real Z80 game code; used only to tell
# the artwork half of the image from the code half.
CODE_OPS = {
    0x21, 0x11, 0x01, 0x3E, 0xCD, 0xC3, 0x32, 0x3A, 0x7E, 0x77, 0x23, 0x2B,
    0x13, 0x0B, 0xAF, 0xFE, 0xCA, 0xD0, 0xC9, 0xF5, 0xC5, 0xE5, 0xF1, 0xC1,
    0xE1, 0x18, 0x20, 0x28, 0x38, 0x30, 0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E,
    0x36, 0xBE, 0xB7, 0xA7, 0xE6, 0xF6, 0xCB, 0xDD, 0xED, 0x87, 0x4F, 0x47,
}

NAMES = {0x00: "program", 0x01: "number array", 0x02: "character array", 0x03: "code"}


def read_blocks(data: bytes) -> list[dict]:
    if data[:8] != b"ZXTape!\x1a":
        raise SystemExit("not a TZX file")
    blocks, pos = [], 10
    while pos < len(data):
        block_id = data[pos]
        pos += 1
        if block_id != 0x10:
            raise SystemExit(f"unexpected block 0x{block_id:02X} at 0x{pos - 1:X}")
        pause, length = struct.unpack_from("<HH", data, pos)
        pos += 4
        payload = data[pos : pos + length]
        pos += length
        checksum = 0
        for byte in payload[:-1]:
            checksum ^= byte
        entry = {"pause": pause, "length": length, "flag": payload[0], "checksum_ok": checksum == payload[-1]}
        # Headers are always 19 bytes. This tape also uses flag 0x00 for two
        # of its data blocks, so length is the reliable discriminator.
        if payload[0] == 0x00 and length == 19:
            entry["kind"] = "header"
            entry["header"] = {
                "type": NAMES.get(payload[1], hex(payload[1])),
                "name": payload[2:12].decode("latin-1").rstrip(),
                "size": struct.unpack_from("<H", payload, 12)[0],
                "param1": struct.unpack_from("<H", payload, 14)[0],
                "param2": struct.unpack_from("<H", payload, 16)[0],
            }
            entry["data"] = payload[18:-1]
        else:
            entry["kind"] = "data"
            entry["data"] = payload[1:-1]
        blocks.append(entry)
    return blocks


def render_screen(screen: bytes) -> list[list[tuple[int, int, int]]]:
    rows = []
    for y in range(192):
        address = ((y & 0xC0) << 5) | ((y & 0x07) << 8) | ((y & 0x38) << 2)
        attributes = screen[6144 + (y // 8) * 32 : 6144 + (y // 8) * 32 + 32]
        row = []
        for column in range(32):
            bits = screen[address + column]
            attribute = attributes[column]
            bright = (attribute & 0x40) >> 3
            ink = ZX_PALETTE[(attribute & 0x07) + bright]
            paper = ZX_PALETTE[((attribute >> 3) & 0x07) + bright]
            row.extend(ink if bits & (0x80 >> bit) else paper for bit in range(8))
        rows.append(row)
    return rows


def save_png(path: Path, rows: list[list[tuple[int, int, int]]], scale: int = 2) -> None:
    from PIL import Image

    image = Image.new("RGB", (len(rows[0]), len(rows)))
    image.putdata([pixel for row in rows for pixel in row])
    image.resize((image.width * scale, image.height * scale), Image.NEAREST).save(path)


def code_density(chunk: bytes) -> float:
    return sum(1 for byte in chunk if byte in CODE_OPS) / len(chunk)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tape", type=Path, default=ROOT / "resources" / "Wriggler.tzx")
    args = parser.parse_args()

    blocks = read_blocks(args.tape.read_bytes())
    OUT.mkdir(exist_ok=True)

    report = []
    for i, block in enumerate(blocks):
        row = {k: v for k, v in block.items() if k != "data"}
        row["index"] = i
        if block["kind"] == "data":
            row["bytes"] = len(block["data"])
        report.append(row)
        label = block.get("header", {}).get("type", "")
        print(f"{i}: {block['kind']:6s} {len(block['data']):6d} bytes {label}")

    screen = blocks[4]["data"]
    if len(screen) != 6912:
        raise SystemExit(f"screen block is {len(screen)} bytes, expected 6912")
    save_png(OUT / "loading-screen.png", render_screen(screen))
    print("wrote Extracted/loading-screen.png")

    memory = bytearray(65536)
    memory[0x5C00 : 0x5C00 + len(blocks[3]["data"])] = blocks[3]["data"]
    memory[LOAD_ADDRESS : LOAD_ADDRESS + len(blocks[5]["data"])] = blocks[5]["data"]
    (OUT / "memory.bin").write_bytes(memory)
    print(f"wrote Extracted/memory.bin (game image at 0x{LOAD_ADDRESS:04X}..0xFFFF)")

    game = blocks[5]["data"]
    split = next((i for i in range(0, len(game), 1024) if code_density(game[i : i + 1024]) > 0.25), len(game))
    report.append(
        {
            "index": "segmentation",
            "load_address": LOAD_ADDRESS,
            "data_region": [LOAD_ADDRESS, LOAD_ADDRESS + split],
            "code_region": [LOAD_ADDRESS + split, LOAD_ADDRESS + len(game) - 1],
        }
    )
    print(f"artwork ends around 0x{LOAD_ADDRESS + split:04X}, code runs to 0xFFFF")

    (OUT / "tape.json").write_text(json.dumps(report, indent=1))
    print("wrote Extracted/tape.json")


if __name__ == "__main__":
    main()
