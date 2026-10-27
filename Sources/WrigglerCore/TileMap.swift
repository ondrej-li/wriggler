import Foundation

/// A 2D grid of tiles in row-major order.
///
/// Coordinates are `(column, row)` with the origin in the top-left corner.
/// Sampling outside the grid returns `.solid`, so levels are implicitly walled in.
public struct TileMap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    private var storage: [Tile]

    public init(width: Int, height: Int, fill: Tile = .empty) {
        precondition(width > 0 && height > 0, "TileMap must have a positive size")
        self.width = width
        self.height = height
        self.storage = Array(repeating: fill, count: width * height)
    }

    public init(rows: [[Tile]]) {
        let height = rows.count
        let width = rows.map(\.count).max() ?? 0
        precondition(width > 0 && height > 0, "TileMap must have a positive size")
        self.width = width
        self.height = height
        var storage = Array(repeating: Tile.empty, count: width * height)
        for (y, row) in rows.enumerated() {
            for (x, tile) in row.enumerated() {
                storage[y * width + x] = tile
            }
        }
        self.storage = storage
    }

    public var bounds: AABB {
        AABB(x: 0, y: 0, width: Double(width), height: Double(height))
    }

    public func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    /// Tile at the given cell. Out-of-bounds cells read as `.solid`.
    public func tile(x: Int, y: Int) -> Tile {
        guard contains(x: x, y: y) else { return .solid }
        return storage[y * width + x]
    }

    /// Tile at a world position (in tile units).
    public func tile(at position: Vec2) -> Tile {
        tile(x: Int(position.x.rounded(.down)), y: Int(position.y.rounded(.down)))
    }

    public mutating func set(_ tile: Tile, x: Int, y: Int) {
        guard contains(x: x, y: y) else { return }
        storage[y * width + x] = tile
    }

    public func isBlocking(x: Int, y: Int) -> Bool {
        tile(x: x, y: y).blocksMovement
    }

    /// Every cell overlapped by `rect`, clamped to the grid.
    public func cells(overlapping rect: AABB) -> (columns: Range<Int>, rows: Range<Int>) {
        let minColumn = max(0, Int(rect.minX.rounded(.down)))
        let maxColumn = min(width - 1, Int((rect.maxX - Self.epsilon).rounded(.down)))
        let minRow = max(0, Int(rect.minY.rounded(.down)))
        let maxRow = min(height - 1, Int((rect.maxY - Self.epsilon).rounded(.down)))

        guard minColumn <= maxColumn, minRow <= maxRow else {
            return (0..<0, 0..<0)
        }
        return (minColumn..<(maxColumn + 1), minRow..<(maxRow + 1))
    }

    /// True if any cell overlapped by `rect` is of the given kind.
    public func rect(_ rect: AABB, overlaps tile: Tile) -> Bool {
        let cells = cells(overlapping: rect)
        for y in cells.rows {
            for x in cells.columns where self.tile(x: x, y: y) == tile {
                return true
            }
        }
        return false
    }

    static let epsilon = 1e-6
}
