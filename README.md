# Wriggler (iOS)

[![CI](https://github.com/ondrej-li/wriggler/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ondrej-li/wriggler/actions/workflows/ci.yml)

An iOS port of the ZX Spectrum game **Wriggler** — a 2D maze platformer.

This repository is a **skeleton**: the project structure, rendering pipeline, input
handling and a fresh, testable game-logic core. The Spectrum original is used only as
source material for the map and sprite art (extraction from `resources/Wriggler.tzx` is
still to come); game mechanics, physics and AI are new implementations.

```
┌─────────────────────────────────────────────────────────────┐
│ Wriggler (app)                                              │
│  App/      SwiftUI shell: menu, HUD, overlays, touch pads   │
│  Game/     SpriteKit renderer, pixel-perfect camera, input  │
│  Content/  level discovery from the bundle                  │
└───────────────────────────┬─────────────────────────────────┘
                            │ uses
┌───────────────────────────▼─────────────────────────────────┐
│ WrigglerCore (framework, no SpriteKit / no UIKit)           │
│  Vec2/AABB · TileMap · Level parsing · KinematicBody        │
│  TileCollision · PlayerController · EnemyController · World │
└─────────────────────────────────────────────────────────────┘
```

The simulation never imports SpriteKit, so it is deterministic, unit-testable, and could
later run off the main thread or in a headless balance harness.

## Requirements

- Xcode 26 or newer (developed against Xcode 27.1 / iOS 26 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Deployment target: iOS 26.0, landscape only, iPhone and iPad

## Build and run

```sh
make generate   # writes Wriggler.xcodeproj from project.yml
make build      # build for the simulator
make test       # run the core test suite
make lint       # check formatting with swift-format
make run        # build, install and launch on a simulator
make art        # regenerate the placeholder pixel art
```

`Wriggler.xcodeproj` is generated and therefore not committed — run `make generate`
after pulling, or open `project.yml` and let your tooling regenerate it.

Useful launch flag while iterating:

```sh
xcrun simctl launch booted cz.ondrejli.wriggler -autostart
```

`-autostart` skips the menu and drops straight into the first level.

## Controls

| Action | Touch | Hardware keyboard |
| --- | --- | --- |
| Move / climb | on-screen D-pad | arrow keys, `WASD` |
| Jump | `JUMP` | space, `Z`, `K` |
| Pause | HUD button | `P`, escape |
| Restart | overlay button | `R` |

Touch controls write into `InputController`, the same press-state model the keyboard
uses, so both paths funnel into one `GameInput` snapshot per frame.

## Game model

**World units.** One unit is one tile. Tiles are 8×8 virtual pixels — a Spectrum
character cell — and the y axis points down, so the grid indices match the level text.

**Fixed timestep.** `World.advance(deltaTime:input:)` accumulates real time and steps the
simulation at 1/120 s. Rendering is decoupled and simply draws the latest snapshot, which
keeps physics stable at any display refresh rate.

**Collision.** `TileCollision.move` resolves one axis at a time (X then Y) against the
grid: intuitive wall sliding, no rotation, no physics engine. One-way platforms only
block bodies falling from above. Ladders never block. Deltas are expected to be smaller
than a tile, which the fixed step guarantees.

**Player.** Acceleration/friction, variable jump height, coyote time and jump buffering
live in `PlayerConfig` — tune the feel in one place.

**Enemies.** `EnemyController` implements a bounded ground patrol (turns at walls,
ledges and the end of its range). Replace it with a maze-graph pathfinder later; the
`World` only needs something that updates a `KinematicBody`.

## Level format

Levels are JSON files in [Sources/Wriggler/Resources/Levels](./Sources/Wriggler/Resources/Levels)
and are discovered at runtime, so adding a file adds a menu entry.

```json
{
  "name": "Sewer Maze",
  "tileset": "default",
  "rows": [
    "########",
    "#..P...#",
    "#^^^..*#",
    "########"
  ]
}
```

| Glyph | Meaning |
| --- | --- |
| `#` | solid wall |
| `=` | one-way platform |
| `H` | ladder |
| `^` | hazard (kills on contact) |
| `*` | level exit |
| `P` | player spawn |
| `e` | crawler spawn |
| `.` | empty |

Rows may be ragged; they are padded on the right. Outside the grid every cell reads as
solid, so levels are implicitly walled in. Glyph spawn markers sit in the cell the body
*occupies*, i.e. the row directly above the floor it stands on.

## Art pipeline

The original is used as **reference only**. Two scripts turn the source material into
data the port can learn from; both write into `Extracted/`, which is git-ignored because
the artwork belongs to the game's authors and is not ours to redistribute.

```sh
python3 -m venv .venv && .venv/bin/pip install -r Scripts/requirements.txt
make extract PYTHON=.venv/bin/python   # both of the below
python3 Scripts/extract_tape.py   # loading screen + memory map from the TZX
python3 Scripts/extract_map.py    # rooms, tile set and actors from the map
python3 Scripts/extract_links.py  # the room-to-room maze graph
```

### From the tape

`resources/Wriggler.tzx` is a plain TZX 1.0 with six standard-speed blocks: two loaders
(273 and 2200 bytes), the 6912-byte loading screen, and a 41768-byte block that fills
`0x5CD8`–`0xFFFF` exactly. That last block is the game: the first ~26 KB is artwork and
tables, the top ~15 KB is Z80 code (a linear sweep shows opcode density jumping from
~8% to ~40% at `0xC4D8`, and it reads `LD A,(0x5C78)` for the frame counter and
`IN A,(0x7FFE)` for the keyboard). `extract_tape.py` writes the loading screen, the 48K
memory image, and a block table with the code/artwork split.

### From the map

The community map stitches every room together. Each room is a 256×144 yellow frame on a
288×176 grid, holding a **30×16 play area of 8×8 cells**, and the white lines between
frames show which passage leads where. `extract_map.py` finds all 244 rooms, crops each
one, deduplicates the 1396 distinct 8×8 cells into a 282-tile set, and harvests the
creatures and props that are drawn in white over the tiles.

What the maze contains:

- **244 rooms** across a 39×38 grid, in colour-coded regions (green, red, blue)
- **actors** — ants, spiders and snail/worm-like creatures, plus a few larger ones
- **artefacts** — RIP tombstones, keys, mugs, bottles, skulls and wreaths, i.e. exactly
  the static and collectable objects a port needs to reimplement
- **terrain** — brick walls, water, foliage, ladders and gates, all on the 8×8 grid

### The maze graph

`extract_links.py` traces the white bands that the map draws between rooms.
Because the author routed every band through empty space, a band almost always
touches exactly two rooms — so connected-component analysis recovers the graph
directly. A band stopping just short of a frame is snapped to the nearest room;
anything still ambiguous is emitted as `?` rather than guessed.

Exits are written `row,col,slot`, with `0,0` at the top-left of the map and the
slot encoding the side and which of the three positions on it:

```
0 1 2   top, left to right      6 7 8   bottom, right to left
3 4 5   right, top to bottom    9 a b   left, bottom to top
```

So `0,0,8 -> 1,0,0` means "the bottom-left exit of the top-left room leads to the
top-left exit of the room below it". Current result: 244 rooms, 674 exits,
656 resolved, 18 left as `?`.

These are reference sheets for building new art, not assets to ship.

## Tests

`make test` runs Swift Testing suites against `WrigglerCore`:

- geometry and `TileMap` queries
- ASCII/JSON level parsing, including the shipped demo level
- collision resolution: floors, walls, ceilings, level edges, one-way platforms, ladders
- player feel: jumping, jump cut, coyote time, ladders, facing
- world: fixed-step timing, no tunnelling, hazards, exit, restart, enemy patrol

## Roadmap ideas

- TZX asset extraction (map + sprites) replacing the placeholder art
- Maze-graph pathfinding for enemies; more enemy kinds
- Sound (Spectrum-style beeper effects), game controller support
- Lives, score, level progression and a save file

The original 1985 ZX Spectrum game and its artwork belong to their respective authors.
