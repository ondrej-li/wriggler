import Foundation

/// The kinds of cells a level grid can contain.
public enum Tile: Int, Sendable, Hashable, CaseIterable, Codable {
    case empty = 0
    /// Fully blocking wall/floor.
    case solid
    /// One-way platform: only blocks bodies moving downwards.
    case platform
    /// Climbable. Never blocks movement.
    case ladder
    /// Kills the player on contact.
    case hazard
    /// Finishes the level on contact.
    case goal

    /// Blocks movement in every direction.
    public var blocksMovement: Bool { self == .solid }

    /// Blocks movement only from above.
    public var isOneWay: Bool { self == .platform }

    /// Blocks a body that is falling onto it.
    public func blocksFall(fromAbove: Bool) -> Bool {
        blocksMovement || (isOneWay && fromAbove)
    }

    /// Glyph used by the ASCII level format. Spawn glyphs are handled by `LevelLoader`.
    public var glyph: Character {
        switch self {
        case .empty: "."
        case .solid: "#"
        case .platform: "="
        case .ladder: "H"
        case .hazard: "^"
        case .goal: "*"
        }
    }
}
