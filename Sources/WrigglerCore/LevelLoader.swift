import Foundation

/// Turns the compact ASCII maze format into a `Level`.
///
/// Glyph legend:
/// ```
/// #  solid wall            =  one-way platform
/// H  ladder                ^  hazard (spikes)
/// *  level exit            .  empty
/// P  player spawn          e  crawler enemy spawn
/// ```
/// Rows may be ragged; they are padded with empty tiles on the right.
public enum LevelLoader {
    public static func parse(document: LevelDocument) throws -> Level {
        try parse(rows: document.rows, name: document.name, tileset: document.tileset ?? "default")
    }

    public static func parse(rows: [String], name: String, tileset: String = "default") throws -> Level {
        guard !rows.isEmpty else { throw LevelError.noRows }

        let width = rows.map(\.count).max() ?? 0
        guard width > 0 else { throw LevelError.rowTooShort(row: 0) }

        var grid = [[Tile]](
            repeating: Array(repeating: .empty, count: width),
            count: rows.count
        )
        var playerSpawn: GridPoint?
        var enemies: [EnemySpawn] = []

        for (y, row) in rows.enumerated() {
            for (x, glyph) in row.enumerated() {
                switch glyph {
                case "#":
                    grid[y][x] = .solid
                case "=":
                    grid[y][x] = .platform
                case "H":
                    grid[y][x] = .ladder
                case "^":
                    grid[y][x] = .hazard
                case "*":
                    grid[y][x] = .goal
                case ".", " ":
                    grid[y][x] = .empty
                case "P":
                    playerSpawn = GridPoint(x: x, y: y)
                case "e":
                    enemies.append(EnemySpawn(cell: GridPoint(x: x, y: y), kind: .crawler))
                default:
                    throw LevelError.unknownGlyph(glyph, row: y, column: x)
                }
            }
        }

        guard let playerSpawn else { throw LevelError.missingPlayerSpawn }

        return Level(
            name: name,
            tileset: tileset,
            map: TileMap(rows: grid),
            playerSpawn: playerSpawn,
            enemySpawns: enemies
        )
    }

    /// Decodes a `LevelDocument` from JSON data and converts it to a `Level`.
    public static func parse(json data: Data) throws -> Level {
        let decoder = JSONDecoder()
        let document = try decoder.decode(LevelDocument.self, from: data)
        return try parse(document: document)
    }
}
