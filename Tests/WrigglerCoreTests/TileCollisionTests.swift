import Testing
import WrigglerCore

@Suite("TileCollision")
struct TileCollisionTests {
    private func body(x: Double, y: Double, size: Double = 1) -> KinematicBody {
        KinematicBody(position: Vec2(x: x, y: y), size: Vec2(x: size, y: size))
    }

    @Test("Falls and lands exactly on the floor")
    func landsOnFloor() {
        let collision = TileCollision(
            map: TestMap.make([
                ".....",
                ".....",
                ".....",
                "#####",
            ]))

        var actor = body(x: 1, y: 0)
        let result = collision.step(&actor, by: Vec2(x: 0, y: 10))

        #expect(result.contains(.landed))
        #expect(actor.position.y == 2)
        #expect(actor.velocity.y == 0)
        #expect(actor.isOnGround)
    }

    @Test("Stops at a wall")
    func stopsAtWall() {
        let collision = TileCollision(
            map: TestMap.make([
                "....#",
                "....#",
                "#####",
            ]))

        var actor = body(x: 1, y: 1)
        let result = collision.step(&actor, by: Vec2(x: 5, y: 0))

        #expect(result.contains(.blockedHorizontally))
        #expect(actor.position.x == 3)
        #expect(actor.velocity.x == 0)
        #expect(actor.isOnGround)
    }

    @Test("Stops at the ceiling")
    func stopsAtCeiling() {
        let collision = TileCollision(
            map: TestMap.make([
                "#####",
                ".....",
                ".....",
            ]))

        var actor = body(x: 1, y: 1.5)
        let result = collision.step(&actor, by: Vec2(x: 0, y: -5))

        #expect(result.contains(.hitCeiling))
        #expect(actor.position.y == 1)
        #expect(actor.velocity.y == 0)
    }

    @Test("Level edges act as walls")
    func levelEdgesAreWalls() {
        let collision = TileCollision(
            map: TestMap.make([
                ".....",
                ".....",
                ".....",
            ]))

        var actor = body(x: 1, y: 1)
        let right = collision.step(&actor, by: Vec2(x: 10, y: 0))
        #expect(right.contains(.blockedHorizontally))
        #expect(actor.position.x == 4)

        let floor = collision.step(&actor, by: Vec2(x: 0, y: 10))
        #expect(floor.contains(.landed))
        #expect(actor.position.y == 2)
        #expect(actor.isOnGround)
    }

    @Test("One-way platforms stop a falling body")
    func oneWayStopsFall() {
        let collision = TileCollision(
            map: TestMap.make([
                ".....",
                "=====",
                ".....",
                "#####",
            ]))

        var actor = body(x: 1, y: -0.2)
        let result = collision.step(&actor, by: Vec2(x: 0, y: 1))

        #expect(result.contains(.landed))
        #expect(actor.position.y == 0)
        #expect(actor.isOnGround)
    }

    @Test("One-way platforms let a body pass through from below")
    func oneWayAllowsRise() {
        let collision = TileCollision(
            map: TestMap.make([
                ".....",
                "=====",
                ".....",
                "#####",
            ]))

        var actor = body(x: 1, y: 2)
        let result = collision.step(&actor, by: Vec2(x: 0, y: -1))

        #expect(!result.contains(.hitCeiling))
        #expect(isClose(actor.position.y, 1))
    }

    @Test("One-way platforms are ignored when already inside them")
    func oneWayIgnoresBodyBelow() {
        let collision = TileCollision(
            map: TestMap.make([
                ".....",
                "=====",
                ".....",
                "#####",
            ]))

        // Bottom edge is already past the platform, so it must not snap upwards.
        var actor = body(x: 1, y: 1.5)
        let result = collision.step(&actor, by: Vec2(x: 0, y: 0.5))

        #expect(!result.contains(.landed))
        #expect(isClose(actor.position.y, 2))
    }

    @Test("Ladders are never blocking")
    func ladderIsNotBlocking() {
        let collision = TileCollision(
            map: TestMap.make([
                ".....",
                "..H..",
                "..H..",
                "..H..",
                "#####",
            ]))

        var actor = body(x: 2, y: 1)
        collision.step(&actor, by: Vec2(x: 0, y: 1.5))

        #expect(isClose(actor.position.y, 2.5))
        #expect(collision.isTouchingLadder(actor))
    }

    @Test("Detects a wall ahead")
    func detectsWall() {
        let collision = TileCollision(
            map: TestMap.make([
                ".....#",
                ".....#",
                "..####",
            ]))

        let actor = body(x: 4, y: 0.5, size: 0.9)
        #expect(collision.isWallAhead(actor, direction: 1))
        #expect(collision.hasFloorAhead(actor, direction: 1))
        #expect(!collision.isWallAhead(actor, direction: -1))
    }

    @Test("Detects a ledge ahead")
    func detectsLedge() {
        let collision = TileCollision(
            map: TestMap.make([
                ".....",
                ".....",
                "..###",
            ]))

        let onLedge = body(x: 4, y: 0.5, size: 0.9)
        #expect(!collision.hasFloorAhead(onLedge, direction: 1))

        let onFloor = body(x: 1, y: 1, size: 0.9)
        #expect(collision.hasFloorAhead(onFloor, direction: 1))
        #expect(!collision.isWallAhead(onFloor, direction: 1))
    }
}
