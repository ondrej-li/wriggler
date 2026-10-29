import Foundation

/// Kinds of object the worm can pick up.
public enum ItemKind: String, Sendable, Codable, CaseIterable {
    case key
    case mug
    case bottle
    case skull
    case tombstone
}

/// An object lying in a room. `position` is the centre, in tiles.
public struct Item: Sendable, Equatable, Identifiable {
    public let id: Int
    public let kind: ItemKind
    public var position: Vec2

    public init(id: Int, kind: ItemKind, position: Vec2) {
        self.id = id
        self.kind = kind
        self.position = position
    }
}
