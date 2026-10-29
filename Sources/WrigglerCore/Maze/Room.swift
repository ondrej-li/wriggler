import Foundation

/// Which edge of a room a doorway sits on.
public enum Side: String, Sendable, Codable, CaseIterable {
    case top
    case right
    case bottom
    case left

    /// Unit normal pointing out of the room.
    public var outward: Vec2 {
        switch self {
        case .top: Vec2(x: 0, y: -1)
        case .right: Vec2(x: 1, y: 0)
        case .bottom: Vec2(x: 0, y: 1)
        case .left: Vec2(x: -1, y: 0)
        }
    }

    public var isHorizontal: Bool { self == .top || self == .bottom }
}

/// A gap in a room's edge that leads somewhere.
///
/// `at` is the centre of the gap measured along the side in tiles - an x
/// coordinate for the top and bottom edges, a y coordinate for the left and
/// right ones. `width` is how wide the gap is, also in tiles.
public struct Doorway: Sendable, Equatable {
    public var side: Side
    public var at: Double
    public var width: Double

    public init(side: Side, at: Double, width: Double) {
        self.side = side
        self.at = at
        self.width = width
    }

    /// True when `value` (x for top/bottom, y for left/right) falls inside the gap.
    public func contains(_ value: Double, slack: Double = 0) -> Bool {
        let half = width / 2 + slack
        return value >= at - half && value <= at + half
    }
}

/// How a room behaves underfoot.
public enum Region: String, Sendable, Codable {
    /// Gardens: the worm crawls over the floor in any direction.
    case surface
    /// The underground: gravity applies, the worm walks and falls down shafts.
    case underground

    public var hasGravity: Bool { self == .underground }
}

/// A room's grid of tiles, in row-major order with the origin top-left.
public struct Room: Sendable, Equatable {
    public let id: GridPoint
    public let columns: Int
    public let rows: Int
    /// The floor colour this room's map region uses, kept for rendering.
    public let floor: String
    public let region: Region
    private let kinds: [TileKind]

    public init(
        id: GridPoint,
        columns: Int,
        rows: Int,
        floor: String = "green",
        region: Region = .surface,
        kinds: [TileKind]
    ) {
        precondition(kinds.count == columns * rows, "tile count does not match room size")
        self.id = id
        self.columns = columns
        self.rows = rows
        self.floor = floor
        self.region = region
        self.kinds = kinds
    }

    public var hasGravity: Bool { region.hasGravity }

    /// Tiles outside the room read as brick, so the room is implicitly walled in.
    public func kind(x: Int, y: Int) -> TileKind {
        guard x >= 0, y >= 0, x < columns, y < rows else { return .brick }
        return kinds[y * columns + x]
    }

    public func kind(at position: Vec2) -> TileKind {
        kind(x: Int(position.x.rounded(.down)), y: Int(position.y.rounded(.down)))
    }

    public func isPassable(x: Int, y: Int) -> Bool {
        kind(x: x, y: y).isPassable
    }

    /// Top edge of the first blocking tile strictly below `feet`, within the
    /// horizontal span of the body. Used to land the worm exactly on a ledge.
    public func floorBelow(x: Double, width: Double, feet: Double, limit: Double) -> Double? {
        let minColumn = max(0, Int(x.rounded(.down)))
        let maxColumn = min(columns - 1, Int((x + width - 1e-6).rounded(.down)))
        guard minColumn <= maxColumn else { return nil }
        let firstRow = max(0, Int(feet.rounded(.down)))
        let lastRow = min(rows - 1, Int(limit.rounded(.up)))
        guard firstRow <= lastRow else { return nil }
        for row in firstRow...lastRow {
            for column in minColumn...maxColumn where !isPassable(x: column, y: row) {
                let top = Double(row)
                if top >= feet - 1e-9, top <= limit + 1e-9 {
                    return top
                }
            }
        }
        return nil
    }

    /// True when the rectangle overlaps any blocking tile.
    ///
    /// Cells outside the room are ignored: the room edge is enforced by the
    /// movement code, which needs to let the body walk out through a doorway.
    public func blocks(_ rect: AABB) -> Bool {
        let minColumn = max(0, Int(rect.minX.rounded(.down)))
        let maxColumn = min(columns - 1, Int((rect.maxX - 1e-6).rounded(.down)))
        let minRow = max(0, Int(rect.minY.rounded(.down)))
        let maxRow = min(rows - 1, Int((rect.maxY - 1e-6).rounded(.down)))
        guard minColumn <= maxColumn, minRow <= maxRow else { return false }
        for y in minRow...maxRow {
            for x in minColumn...maxColumn where !isPassable(x: x, y: y) {
                return true
            }
        }
        return false
    }
}
