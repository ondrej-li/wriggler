import Testing

@testable import WrigglerCore

@Suite("Geometry")
struct GeometryTests {
    @Test("Vec2 arithmetic")
    func vectorMath() {
        let a = Vec2(x: 1, y: 2)
        let b = Vec2(x: 3, y: -1)

        #expect(a + b == Vec2(x: 4, y: 1))
        #expect(b - a == Vec2(x: 2, y: -3))
        #expect(a * 2 == Vec2(x: 2, y: 4))
        #expect(-a == Vec2(x: -1, y: -2))
        #expect(a.dot(b) == 1)
        #expect(Vec2(x: 3, y: 4).length == 5)
    }

    @Test("AABB intersection excludes touching edges")
    func intersection() {
        let unit = AABB(x: 0, y: 0, width: 1, height: 1)

        #expect(unit.intersects(AABB(x: 0.5, y: 0.5, width: 1, height: 1)))
        #expect(!unit.intersects(AABB(x: 1, y: 0, width: 1, height: 1)))
        #expect(!unit.intersects(AABB(x: 0, y: 2, width: 1, height: 1)))
    }

    @Test("AABB edges and centre")
    func bounds() {
        let box = AABB(x: 2, y: 3, width: 4, height: 2)

        #expect(box.minX == 2)
        #expect(box.maxX == 6)
        #expect(box.maxY == 5)
        #expect(box.center == Vec2(x: 4, y: 4))
        #expect(box.contains(Vec2(x: 2, y: 3)))
        #expect(!box.contains(Vec2(x: 6, y: 3)))
    }

    @Test("moveTowards clamps to the target")
    func approach() {
        #expect(moveTowards(0, 10, 3) == 3)
        #expect(moveTowards(9, 10, 3) == 10)
        #expect(moveTowards(5, 0, 2) == 3)
    }
}
