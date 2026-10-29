# Wriggler (iOS)

[![CI](https://github.com/ondrej-li/wriggler/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ondrej-li/wriggler/actions/workflows/ci.yml)

An iOS port of the ZX Spectrum game **Wriggler** — a worm loose in a 244-room maze.

The maze layout, its doorways, the pickups and the room artwork are reconstructed from
the map; the game itself — movement, collision, falls, items — is a new implementation.

Playable now: eight-directional movement with tile collision, doorways between all
244 rooms, and picking up, carrying and swapping objects. Next up is giving the
objects effects, then enemies.

```
┌─────────────────────────────────────────────────────────────┐
│ Wriggler (app)                                              │
│  App/      SwiftUI shell: HUD, overlays, touch pad          │
│  Game/     SpriteKit room renderer, input, session, art     │
└───────────────────────────┬─────────────────────────────────┘
                            │ uses
┌───────────────────────────▼─────────────────────────────────┐
│ WrigglerCore (framework, no SpriteKit / no UIKit)           │
│  Vec2/AABB · TileKind · Room · Maze · Item                  │
│  MazeMovement · MazePlayer · MazeWorld                      │
└─────────────────────────────────────────────────────────────┘
```

The simulation never imports SpriteKit, so it is deterministic, unit-testable, and
could later run off the main thread or in a headless balance harness.

## Requirements

- Xcode 26 or newer (developed against Xcode 27.1 / iOS 26 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Deployment target: iOS 26.0, landscape only, iPhone and iPad

## Build and run

```sh
make open       # generate the Xcode project and open it
make generate   # just write Wriggler.xcodeproj from project.yml
make build      # build for the simulator
make test       # run the core test suite
make lint       # check formatting with swift-format
make run        # build, install and launch on a simulator
```

`make open` is the quickest way in: it regenerates the project and opens it in
Xcode, where the `Wriggler` scheme is ready to run. Pick a simulator and press
run, or choose your device after setting a team (below).

`Wriggler.xcodeproj` is generated and therefore not committed — run `make open`
after pulling and the project appears, correctly configured.

**Running on a device** needs your team ID. Drop it in `local.mk` (not committed)
and every `make` target picks it up:

```make
# local.mk
DEVELOPMENT_TEAM := ABCDE12345
```

or pass it per invocation: `make open DEVELOPMENT_TEAM=ABCDE12345`. Without it the
simulator works fine and Xcode only asks for a team when you target a device.

**Shipping to TestFlight** is `make upload-xcode` (one step, uses the account
signed in to Xcode) or `make archive` then `make upload` (needs an App Store Connect
API key). See [docs/TESTFLIGHT.md](./docs/TESTFLIGHT.md) for the setup and the CI
workflow.

Launch flags while iterating:

```sh
xcrun simctl launch booted cz.ondrejli.wriggler -demo
```

`-demo` ignores the controls and drives a fixed walk: fetch the key in the start
room, step back to the doorway and walk through it. Handy for checking that
movement, pickup and room changes still work after a refactor.

`-room 13,19` starts in the given room instead of the beginning, which is how the
underground rooms are checked in isolation.

## Controls

| Action | Touch | Hardware keyboard |
| --- | --- | --- |
| Move (eight directions) | on-screen cross; press two arrows for a diagonal | arrow keys, `WASD` |
| Pick up / swap / use | `USE` | space, `E`, `Z` |
| Pause | HUD button | `P`, escape |
| Restart | HUD button | `R` |

Touch and keyboard both feed `InputController`, so gameplay only ever sees one
`GameInput` snapshot per frame.

## The game

The player is a worm let loose in a 244-room maze. One room fills the screen;
walk out through a doorway and you arrive in the connected room, at the matching
doorway.

**Two kinds of ground.** The map divides cleanly: 100 garden rooms with green
floors and 144 underground rooms with black floors. They play differently.

- **Gardens** — the worm crawls over the floor in all eight directions, with no
  gravity. Diagonal input is normalised so it is not faster than walking straight.
- **Underground** — gravity applies. The worm walks left and right, cannot crawl
  up, and falls wherever there is no floor beneath it. Shafts drop it through
  doorways into the rooms below, gathering speed as it goes.

Collision is per-axis against the room's tile grid, so the worm slides along walls
instead of sticking.

**The room edge** holds the player in everywhere except at a doorway. Doorway
positions come from the maze data: they are the measured spots where the map's
connector lines meet each room's frame, so a room with a door in the middle of its
right edge lets you out exactly there and nowhere else.

**Rooms, not a scrolling level.** `MazeWorld` holds one room at a time, the items
lying in it, and what the worm is carrying. Stepping through a doorway swaps the
room and places the worm just inside the doorway it arrived through.

**One button for everything.** With empty hands it picks up the nearest object in
reach; while carrying, standing over another object swaps the two; and pressing it
with nothing underfoot uses what is held. Items do nothing yet — that is the next
step.

**Four worms.** The player drives one worm; three rivals crawl the maze on their
own, so the race continues whether or not you are in the room to watch it. A rival
is an ordinary worm — same body, same collision, same gravity — steered by a wander
policy instead of the touch controls: it picks a direction, keeps it for a moment,
turns when it feels a wall, and crosses doorways just like the player. Rivals never
die; a fatal fall drops them back on the last ledge they stood on. On screen the
worms are indistinguishable, exactly as in the original: yours is the one that
answers the controls.

**They crawl, they do not slide.** A worm bunches up and stretches out after its
head as it travels, easing in and out of the squirm and stopping dead when it stops.
The cycle is driven by distance covered rather than by the clock, so it keeps step
with the worm's real speed and survives any frame rate; a hop through a doorway is
not a crawl and is ignored. `WormCrawl` holds the maths, and the renderer snaps the
squash to whole source pixels so every frame stays crisp pixel art instead of a
smeared one.

**Falls and lives.** A fall longer than one screen kills the worm. It leaves a RIP
tombstone where it died, costs a life, and the worm reappears on the last patch of
solid ground it stood on — respawning at the top of the shaft it just fell down
would only repeat the fall. Three lives; the third death ends the run.

**Tiles** are `floor`, `brick`, `foliage`, `water` and `sign`. Only floor is
walkable.

## Room artwork

Screens are rebuilt from the original artwork rather than approximated. The map is
drawn from a small set of repeating 8x8 tiles, so `Scripts/build_room_art.py` sorts
every cell into "a tile I have seen before" or "something drawn on top":

- **331 tiles** reproduce **98.9%** of all 117,120 cells exactly, and are packed
  into a single atlas.
- Whatever covers the rest — creatures, flowers, the "START" lettering — comes back
  as a sprite with transparency, so the game can choose what to draw.
- Each room is composited once into a texture, then drawn at an integer scale with
  nearest-neighbour filtering: upscaled, never resampled down.

Sprites are categorised in `RoomArt/sprite-categories.json`; **anything unlisted is
treated as an enemy and not drawn**, which is what keeps the ants out of the start
room while the bug with the starting gun and the lettering stay. Screens get
classified as they are reviewed, so a room may look emptier than the original until
its sprites are listed.

**The worms are not decorations.** The original screens draw them in touching pairs,
so those shapes are categorised as `worm`: never painted into the background, but
used as spawn markers. The pair is cut at its horizontal seam, the top worm trimmed
out of it, and the result is the single sprite that every worm in the game — the
player's and the rivals' — is drawn from. Facing is the only variation: the sprite is
mirrored when the worm crawls left.

The artwork lives in [Sources/Wriggler/Resources/RoomArt](./Sources/Wriggler/Resources/RoomArt)
— a tile atlas, a sprite atlas and the per-room layouts. It is reconstructed from the
original map and remains the original authors' work; swap that folder to re-skin the
game. `make roomart` rebuilds it, and the game falls back to flat procedural tiles if
the folder is missing.

## Maze data

`Scripts/build_maze_data.py` writes [maze.json](./Sources/Wriggler/Resources/Maze/maze.json),
which the game loads at launch: 244 rooms of 30x16 cells, 670 doorways, 50 items,
and the spawn point on screen `3,13`. It is a *functional* description only —
characters like `.` and `#` say what a cell is, never what it looks like.

Walkability is derived from the map's colours, which vary by region: gardens have
green floors and red brick, caves have black floors and red rock. Rather than
hard-code a palette, each room's floor colour is learned from the cells at its
doorways — every doorway is walkable by definition, which makes it the one
reliable sample point. Creatures drawn over the floor are detected as "floor
colour plus a grey overlay" so they do not punch holes in the walkable area, and
the floor is then clamped to what is actually reachable from the doorways.

The game draws its own tiles at run time, keyed by tile kind and the room's floor
colour, so no artwork from the original is bundled.

## The maze graph

`extract_links.py` traces the white bands that the map draws between rooms.
Because the author routed every band through empty space, a band touches at most
two rooms — so connected-component analysis recovers the graph directly, with no
ambiguity: a band joining two rooms is a link, and a band touching one room is a
dangling exit.

Dangling exits are emitted as `?` rather than guessed at. Guessing was tried and
turned out to put plausible-looking links into the table that were simply wrong,
so the curated layer below exists instead.

Exits are written `row,col,slot`, with `0,0` at the top-left of the map and the
slot encoding the side and which of the three positions on it:

```
0 1 2   top, left to right      6 7 8   bottom, right to left
3 4 5   right, top to bottom    9 a b   left, bottom to top
```

So `0,0,8 -> 1,0,0` means "the bottom-left exit of the top-left room leads to the
top-left exit of the room below it". Current result: **244 rooms, 670 exits, all
670 resolved** — no dangling exits left, and every room is reachable from `0,0`.
335 links over 244 rooms means 92 loops beyond a spanning tree, so there are
genuinely multiple routes through the maze.

### Curated links

`Scripts/links-overrides.txt` holds hand-traced links and is applied after the
automatic pass, so it wins:

```
1,11,a  -> 8,15,4
33,28,9 -> 35,26,5
```

The reverse direction is filled in automatically, so a pair is written once. A
line starting with `-` drops an exit the trace produced which is not a real exit
(used when a hand-traced slot disagrees with the measured position). The script
prints any override that contradicts a traced link instead of silently
overwriting it.

Exit positions are bucketed into thirds of the frame measured from the play area,
which reproduces the reference notation; the raw centres are in the script if a
boundary needs moving.

## Tests

`make test` runs Swift Testing suites against `WrigglerCore`:

- maze data: the bundled maze decodes, doorways are symmetric, the spawn is on floor
- rooms: tile lookup, blocking, out-of-room cells
- movement: all eight directions, diagonal speed, wall collision, room edge holding
- doorways: leaving through one arrives at the partner's doorway, no exit where there is no door
- gravity: no fall on the surface, falling and landing underground, no crawling up, sideways crawling
- falls: a drop over one screen is fatal, leaves a tombstone, costs a life, respawns on solid ground, three deaths end the run
- items: pickup, swap, drop position, reach limit, use, restart
