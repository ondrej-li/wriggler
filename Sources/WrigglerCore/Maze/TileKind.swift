import Foundation

/// What a maze cell is made of.
public enum TileKind: String, Sendable, Codable, CaseIterable {
    case floor
    case brick
    case foliage
    case water
    case sign

    /// Only floor can be walked on. Everything else is scenery or solid.
    public var isPassable: Bool { self == .floor }
}
