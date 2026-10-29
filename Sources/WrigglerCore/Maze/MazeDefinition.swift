import Foundation

/// The wire format produced by `Scripts/build_maze_data.py`.
///
/// It is a functional description of the maze: which cells are walkable, where
/// the doorways are and where the pickups lie. No pixel data - the game draws its
/// own tiles.
public struct MazeDefinition: Sendable, Decodable {
    public struct RoomShape: Sendable, Decodable {
        public let columns: Int
        public let rows: Int
    }

    public struct Spawn: Sendable, Decodable {
        public let room: String
        public let x: Double
        public let y: Double
    }

    public struct ItemDefinition: Sendable, Decodable {
        public let kind: String
        public let x: Double
        public let y: Double
    }

    public struct RoomDefinition: Sendable, Decodable {
        /// One string per row; each character is a tile, see `tiles`.
        public let rows: [String]
        public let floor: String?
        public let items: [ItemDefinition]?
    }

    public struct LinkDefinition: Sendable, Decodable {
        public let to: String
        public let side: String
        public let at: Double
        public let width: Double
    }

    public let version: Int
    public let cell: Int
    public let room: RoomShape
    /// Maps a character used in `RoomDefinition.rows` to a tile name.
    public let tiles: [String: String]
    public let spawn: Spawn
    public let rooms: [String: RoomDefinition]
    public let links: [String: LinkDefinition]
}

public enum MazeDefinitionError: Error, CustomStringConvertible {
    case unreadable(String)

    public var description: String {
        switch self {
        case .unreadable(let detail): "unreadable maze data: \(detail)"
        }
    }
}

extension MazeDefinition {
    public static func load(from data: Data) throws -> MazeDefinition {
        do {
            return try JSONDecoder().decode(MazeDefinition.self, from: data)
        } catch {
            throw MazeDefinitionError.unreadable(String(describing: error))
        }
    }
}

/// `"row,column"` as used throughout the maze data.
public struct RoomID: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ",")
        guard parts.count == 2, let row = Int(parts[0]), let column = Int(parts[1]) else { return nil }
        self.init(row: row, column: column)
    }

    public var description: String { "\(row),\(column)" }
    public var point: GridPoint { GridPoint(x: column, y: row) }

    public static func < (lhs: RoomID, rhs: RoomID) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }
}

/// `"row,column,slot"` - one exit of one room.
struct ExitID: Hashable, Sendable {
    let room: RoomID
    let slot: Int

    init?(room: RoomID, slot: String) {
        let slots = "0123456789ab"
        guard let index = slots.firstIndex(of: Character(slot)) else { return nil }
        self.room = room
        self.slot = slots.distance(from: slots.startIndex, to: index)
    }

    init?(text: String) {
        let parts = text.split(separator: ",")
        guard parts.count == 3, let room = RoomID("\(parts[0]),\(parts[1])") else { return nil }
        self.init(room: room, slot: String(parts[2]))
    }
}
