# CLAUDE.md — Wriggler

The map, not the manual. The [README](README.md) explains the game, the maze
pipeline and the artwork rules; [`CONTRIBUTING.md`](CONTRIBUTING.md) has the branch
and formatting rules; [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md) covers shipping;
[`SECURITY.md`](SECURITY.md) says where to report a vulnerability.

## What this is

An iOS game: a ZX Spectrum port of *Wriggler*, SwiftUI shell over a SpriteKit view,
with a simulation core that has no business knowing about either. Ported from the
original tape — `Scripts/` holds the extraction tooling.

## Layout

```
Sources/Wriggler/          rendering: SpriteKit, input, audio
Sources/WrigglerCore/      the game: maze data, rooms, movement, gravity, items, lives
Tests/WrigglerCoreTests/   Swift Testing suites over the core
Scripts/                   tape extraction, maze/room-art/icon generators, simulator runner
Extracted/                 what came out of the original tape (source of truth for the maze)
Support/                   ExportOptions.plist, other build inputs
resources/                 room artwork and audio
docs/TESTFLIGHT.md         shipping, secrets, testers
project.yml                XcodeGen spec — Wriggler.xcodeproj is generated, not committed
.github/workflows/         ci.yml (lint + build + test); nothing publishes from CI
local.mk                   your team ID and device name; not committed
```

## Building and testing

**CI is the builder.** `.github/workflows/ci.yml` runs on `macos-26` for every push
and PR: `swift format lint --strict` and `make test`.

```sh
gh workflow run ci.yml
gh run watch
```

Required checks on `main`: **Lint**, **Build & Test**.

Locally, with a full Xcode:

```sh
make open       # generate the project and open Xcode
make build      # simulator build
make test       # Swift Testing suites
make lint       # swift-format lint
make run        # build, install, launch on a simulator
make icon       # regenerate AppIcon-1024.png (opaque RGB — alpha is rejected)
```

Formatting before a PR: `swift format format --in-place --recursive Sources Tests`.
Nothing here builds on Linux.

## Shipping

**Publishing is manual; CI does not upload anything** and no Apple credential is
stored in this repository.

```sh
make archive          # signed .xcarchive, then .ipa in build/export
make upload           # needs an App Store Connect API key in the environment
make upload-xcode     # or: via the Apple ID signed into Xcode, no key needed
```

[`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md) has the detail, including the store
checklist that is easy to lose.

## Conventions

- `main` is protected: branch → PR → **Lint** and **Build & Test** green → merge.
  The pull request template asks what changed and what you ran.
- The core (`Sources/WrigglerCore`) must not import SpriteKit or UIKit; rendering
  stays in `Sources/Wriggler`. Behaviour changes in the core come with tests.
- The maze is generated from `Extracted/`, not hand-edited. If a maze value looks
  wrong, fix the generator or the curated links, not the generated file.
- Room artwork has an established look (see *Room artwork* in the README); new
  rooms follow it rather than introducing a style.
- The app is landscape on iPhone and open on iPad; iPad orientation rules have
  already caused one App Store rejection — read that paragraph in `docs/TESTFLIGHT.md`
  before touching orientations.
