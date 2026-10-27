import Foundation

/// Kinds of enemy the simulation knows about.
public enum EnemyKind: String, Sendable, Codable, CaseIterable {
    case crawler
}

/// Where an enemy starts, in tile coordinates.
public struct EnemySpawn: Sendable, Equatable {
    public var cell: GridPoint
    public var kind: EnemyKind

    public init(cell: GridPoint, kind: EnemyKind = .crawler) {
        self.cell = cell
        self.kind = kind
    }
}

/// A playable level: the maze grid plus spawn points.
public struct Level: Sendable, Equatable {
    public var name: String
    /// Name of the sprite set used to draw this level's tiles.
    public var tileset: String
    public var map: TileMap
    public var playerSpawn: GridPoint
    public var enemySpawns: [EnemySpawn]

    public init(
        name: String,
        tileset: String = "default",
        map: TileMap,
        playerSpawn: GridPoint,
        enemySpawns: [EnemySpawn] = []
    ) {
        self.name = name
        self.tileset = tileset
        self.map = map
        self.playerSpawn = playerSpawn
        self.enemySpawns = enemySpawns
    }
}

/// On-disk representation of a level.
public struct LevelDocument: Sendable, Codable {
    public var name: String
    public var tileset: String?
    /// Rows of the ASCII maze. See `LevelLoader` for the glyph legend.
    public var rows: [String]

    public init(name: String, tileset: String? = nil, rows: [String]) {
        self.name = name
        self.tileset = tileset
        self.rows = rows
    }
}

public enum LevelError: Error, Equatable, CustomStringConvertible {
    case noRows
    case rowTooShort(row: Int)
    case missingPlayerSpawn
    case unknownGlyph(Character, row: Int, column: Int)

    public var description: String {
        switch self {
        case .noRows:
            "Level contains no rows"
        case .rowTooShort(let row):
            "Row \(row) is empty"
        case .missingPlayerSpawn:
            "Level has no player spawn ('P')"
        case .unknownGlyph(let glyph, let row, let column):
            "Unknown level glyph '\(glyph)' at row \(row), column \(column)"
        }
    }
}
