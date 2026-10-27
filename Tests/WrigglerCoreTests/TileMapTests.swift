import Testing
import WrigglerCore

@Suite("TileMap")
struct TileMapTests {
    private let map = TestMap.make([
        "....",
        ".##.",
        "....",
    ])

    @Test("Reads tiles by cell and by world position")
    func reading() {
        #expect(map.tile(x: 0, y: 0) == .empty)
        #expect(map.tile(x: 1, y: 1) == .solid)
        #expect(map.tile(at: Vec2(x: 2.7, y: 1.2)) == .solid)
        #expect(map.tile(at: Vec2(x: 0.1, y: 2.9)) == .empty)
    }

    @Test("Out-of-bounds cells read as solid")
    func outOfBounds() {
        #expect(map.tile(x: -1, y: 0) == .solid)
        #expect(map.tile(x: 0, y: -1) == .solid)
        #expect(map.tile(x: 4, y: 0) == .solid)
        #expect(map.tile(x: 0, y: 3) == .solid)
    }

    @Test("Cells overlapped by a rect are clamped to the grid")
    func overlappingCells() {
        let cells = map.cells(overlapping: AABB(x: -5, y: -5, width: 100, height: 100))
        #expect(cells.columns == 0..<4)
        #expect(cells.rows == 0..<3)

        let empty = map.cells(overlapping: AABB(x: 10, y: 10, width: 1, height: 1))
        #expect(empty.columns.isEmpty)
        #expect(empty.rows.isEmpty)
    }

    @Test("Rect overlap queries detect tiles")
    func rectOverlap() {
        let wall = AABB(x: 1, y: 1, width: 1, height: 1)
        #expect(map.rect(wall, overlaps: .solid))
        #expect(!map.rect(AABB(x: 0, y: 0, width: 1, height: 1), overlaps: .solid))
        // Touching the boundary of a tile must not count as overlapping it.
        #expect(!map.rect(AABB(x: 0, y: 1, width: 1, height: 1), overlaps: .solid))
    }
}
