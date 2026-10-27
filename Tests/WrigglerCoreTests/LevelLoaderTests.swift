import Foundation
import Testing
import WrigglerCore

@Suite("LevelLoader")
struct LevelLoaderTests {
    @Test("Parses tiles, spawns and enemies")
    func parsesLevel() throws {
        let level = try LevelLoader.parse(
            rows: [
                "#####",
                "#P.e#",
                "#^=*#",
                "#####",
            ], name: "Inline")

        #expect(level.name == "Inline")
        #expect(level.map.width == 5)
        #expect(level.map.height == 4)
        #expect(level.playerSpawn == GridPoint(x: 1, y: 1))
        #expect(level.enemySpawns.count == 1)
        #expect(level.enemySpawns.first?.cell == GridPoint(x: 3, y: 1))
        #expect(level.enemySpawns.first?.kind == .crawler)
        #expect(level.map.tile(x: 1, y: 2) == .hazard)
        #expect(level.map.tile(x: 2, y: 2) == .platform)
        #expect(level.map.tile(x: 3, y: 2) == .goal)
    }

    @Test("Pads ragged rows with empty cells")
    func padsRaggedRows() throws {
        let level = try LevelLoader.parse(
            rows: [
                "#####",
                "#P",
                "#####",
            ], name: "Ragged")

        #expect(level.map.width == 5)
        #expect(level.map.tile(x: 4, y: 1) == .empty)
    }

    @Test("Requires a player spawn")
    func requiresPlayer() {
        #expect(throws: LevelError.missingPlayerSpawn) {
            try LevelLoader.parse(rows: ["###", "#.#", "###"], name: "NoPlayer")
        }
    }

    @Test("Rejects unknown glyphs")
    func rejectsUnknownGlyph() {
        #expect(throws: LevelError.self) {
            try LevelLoader.parse(rows: ["#P#", "#?#", "###"], name: "Bad")
        }
    }

    @Test("Decodes JSON documents")
    func decodesJSON() throws {
        let json = """
            { "name": "From JSON", "tileset": "spectrum", "rows": ["#P#", "###"] }
            """.data(using: .utf8)!

        let level = try LevelLoader.parse(json: json)
        #expect(level.name == "From JSON")
        #expect(level.tileset == "spectrum")
        #expect(level.playerSpawn == GridPoint(x: 1, y: 0))
    }

    @Test("The bundled demo level is valid")
    func demoLevelIsValid() throws {
        let url = try #require(
            Bundle(for: BundleToken.self).url(
                forResource: "demo-maze",
                withExtension: "json",
                subdirectory: "Levels"
            ),
            "demo-maze.json missing from the test bundle"
        )
        let level = try LevelLoader.parse(json: Data(contentsOf: url))

        #expect(level.map.width == 80)
        #expect(level.map.height == 36)
        #expect(level.enemySpawns.count == 11)
        #expect(level.map.rect(level.map.bounds, overlaps: .goal), "demo level has no exit")
        #expect(
            level.map.tile(
                at: Vec2(
                    x: Double(level.playerSpawn.x) + 0.5,
                    y: Double(level.playerSpawn.y) + 0.5)) == .empty,
            "player spawn is inside a wall")
    }
}

private final class BundleToken {}
