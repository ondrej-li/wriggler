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

`Scripts/generate_placeholder_art.py` writes the current sprites — authored as character
grids in the ZX Spectrum palette — into `Assets.xcassets` at their native 8×8 / 16×16
sizes. It exists so the renderer, the atlas and the nearest-neighbour scaling path are
exercised before the real art exists.

The intended pipeline is:

1. Extract the map and sprite data from `resources/Wriggler.tzx`.
2. Emit levels as JSON (the format above) and sprites as 1× PNGs into `Assets.xcassets`,
   replacing the placeholder imagesets by name (`tile_wall`, `player_idle`, …).
3. Nothing in the app changes — `PixelArt` looks sprites up by name and falls back to flat
   ZX palette colours when an image is missing.

Rendering is pixel-perfect: the scene picks the largest integer scale of the 256×192
Spectrum screen that fits, rounds every actor position to a whole virtual pixel, and every
texture uses nearest-neighbour filtering. Larger screens simply reveal more of the maze.

## Workflow

`main` is protected: changes land through pull requests only, and a pull request can
only be merged once the `Lint` and `Build & Test` checks are green, its conversation is
resolved, and its branch is up to date. Force pushes and deletions are blocked, and
history stays linear (squash merges only).

CI runs on `macos-26` and does three things:

1. `swift format lint --strict` over `Sources` and `Tests`, plus a check that the
   committed pixel art matches what `Scripts/generate_placeholder_art.py` produces.
2. Generates the project with XcodeGen and runs the test suite on the newest available
   iOS simulator (`swift format` config lives in [.swift-format](./.swift-format)).
3. Builds the app for a real device destination, so device-only breakage is caught too.

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
