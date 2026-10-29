import Testing
import WrigglerCore

@Suite("Movement")
struct MovementTests {
    @Test("Moves in all eight directions")
    func eightDirections() throws {
        let maze = try TestMaze.corridor()
        let cases: [(Double, Double)] = [
            (1, 0), (-1, 0), (0, 1), (0, -1),
            (1, 1), (1, -1), (-1, 1), (-1, -1),
        ]
        for (dx, dy) in cases {
            var world = MazeWorld(maze: maze)
            let start = world.player.position
            _ = world.run(frames: 10, input: GameInput(moveX: dx, moveY: dy))
            let moved = world.player.position - start
            #expect(moved.length > 0.3, "expected movement for (\(dx), \(dy))")
            if dx == 0 { #expect(abs(moved.x) < 1e-9) } else { #expect(moved.x * dx > 0) }
            if dy == 0 { #expect(abs(moved.y) < 1e-9) } else { #expect(moved.y * dy > 0) }
        }
    }

    @Test("Diagonal speed matches cardinal speed")
    func diagonalIsNormalised() throws {
        let maze = try TestMaze.corridor()

        var cardinal = MazeWorld(maze: maze)
        _ = cardinal.run(frames: 12, input: GameInput(moveX: 1))

        var diagonal = MazeWorld(maze: maze)
        _ = diagonal.run(frames: 12, input: GameInput(moveX: 1, moveY: 1))

        let a = cardinal.player.position - Vec2(x: 2, y: 3)
        let b = diagonal.player.position - Vec2(x: 2, y: 3)
        #expect(abs(a.length - b.length) < 0.02, "diagonal should not be faster")
    }

    @Test("Facing follows horizontal input")
    func facing() throws {
        var world = MazeWorld(maze: try TestMaze.corridor())
        _ = world.run(frames: 5, input: GameInput(moveX: -1))
        #expect(world.player.facing == .left)
        _ = world.run(frames: 5, input: GameInput(moveX: 1))
        #expect(world.player.facing == .right)
    }

    @Test("Walls stop the player")
    func wallsBlock() throws {
        var world = MazeWorld(maze: try TestMaze.blocked())
        _ = world.run(frames: 120, input: GameInput(moveX: 1))

        #expect(world.player.position.x < 5, "player should be stopped by the wall")
        #expect(world.player.position.x > 3.5, "player should reach the wall")
    }

    @Test("The room edge holds the player in where there is no door")
    func edgeHolds() throws {
        var world = MazeWorld(maze: try TestMaze.corridor())
        _ = world.run(frames: 200, input: GameInput(moveX: -1))

        #expect(world.roomID == RoomID("0,0"))
        #expect(world.player.position.x >= world.player.bodySize / 2 - 0.001)
    }

    @Test("Walking into a doorway leads to the next room, arriving at its doorway")
    func doorwayLeadsSomewhere() throws {
        let maze = try TestMaze.corridor()
        // The spawn is already level with the doorway, which is centred at y = 3.
        var world = MazeWorld(maze: maze)
        var events: [MazeEvent] = []
        var arrival: Vec2?
        for _ in 0..<200 {
            let frameEvents = world.update(deltaTime: 1.0 / 60.0, input: GameInput(moveX: 1))
            if frameEvents.contains(where: { if case .enteredRoom = $0 { true } else { false } }) {
                arrival = world.player.position
                events.append(contentsOf: frameEvents)
                break
            }
            events.append(contentsOf: frameEvents)
        }

        #expect(world.roomID == RoomID("0,1"))
        #expect(events.contains(.enteredRoom(RoomID("0,1")!)))
        let position = try #require(arrival)
        #expect(position.x < 1.5, "should arrive just inside the left edge")
        #expect(abs(position.y - 3) < 0.1, "should arrive level with the doorway")
        #expect(world.room.kind(at: position) == .floor)
    }

    @Test("The player cannot walk out where there is no doorway")
    func wallWhereNoDoor() throws {
        let maze = try TestMaze.corridor()
        var world = MazeWorld(maze: maze)
        // Walk to the top of the room, above the doorway, then push right.
        _ = world.run(frames: 120, input: GameInput(moveY: -1))
        let events = world.run(frames: 200, input: GameInput(moveX: 1))

        #expect(world.roomID == RoomID("0,0"))
        #expect(!events.contains { if case .enteredRoom = $0 { true } else { false } })
    }
}
