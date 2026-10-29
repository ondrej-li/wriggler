import Testing
import WrigglerCore

@Suite("Gravity")
struct GravityTests {
    @Test("Surface rooms have no gravity")
    func surfaceDoesNotFall() throws {
        var world = MazeWorld(maze: try TestMaze.corridor())
        let start = world.player.position

        _ = world.run(frames: 120, input: .none)

        #expect(world.player.position.y == start.y, "the worm should hover where it was left")
        #expect(world.room.region == .surface)
    }

    @Test("Underground rooms pull the worm down")
    func undergroundFalls() throws {
        var world = MazeWorld(maze: try TestMaze.ledge())
        let start = world.player.position.y

        _ = world.run(frames: 60, input: .none)

        #expect(world.player.position.y > start)
        #expect(world.room.region == .underground)
    }

    @Test("The worm lands on a ledge and stops there")
    func landsOnLedge() throws {
        var world = MazeWorld(maze: try TestMaze.ledge())
        _ = world.run(frames: 120, input: .none)

        // The ledge occupies rows 3..3 from column 4, and the body is 0.9 tall.
        #expect(abs(world.player.position.y + 0.45 - 3) < 0.01, "landed at \(world.player.position)")
        #expect(world.player.fallSpeed == 0)
        #expect(world.player.fallDistance == 0)
    }

    @Test("The worm cannot crawl up in the underground")
    func noCrawlingUp() throws {
        var world = MazeWorld(maze: try TestMaze.ledge())
        _ = world.run(frames: 120, input: .none)  // settle on the ledge
        let settled = world.player.position

        _ = world.run(frames: 60, input: GameInput(moveY: -1))

        #expect(world.player.position.y >= settled.y - 0.001, "up input must not lift the worm")
    }

    @Test("The worm can still crawl sideways underground")
    func crawlsSideways() throws {
        var world = MazeWorld(maze: try TestMaze.ledge())
        _ = world.run(frames: 120, input: .none)
        let start = world.player.position

        _ = world.run(frames: 20, input: GameInput(moveX: -1))

        #expect(world.player.position.x < start.x - 0.5)
    }

    @Test("Falling further than one screen kills the worm")
    func fatalFall() throws {
        var world = MazeWorld(maze: try TestMaze.shaft())

        var events: [MazeEvent] = []
        for _ in 0..<600 {
            events.append(contentsOf: world.update(deltaTime: 1.0 / 60.0, input: .none))
            if events.contains(where: { if case .died = $0 { true } else { false } }) { break }
        }

        #expect(events.contains(.died(.fall)))
        #expect(world.lives == 2)
        #expect(!world.isGameOver)
    }

    @Test("A death leaves a tombstone behind")
    func tombstoneAppears() throws {
        var world = MazeWorld(maze: try TestMaze.shaft())
        _ = world.run(frames: 200, input: .none)

        let tombstones = world.itemsInRoom.filter { $0.kind == .tombstone }
        #expect(tombstones.count >= 1, "a RIP marker should be left where the worm fell")
    }

    @Test("Tombstones are scenery, not pickups")
    func tombstoneIsNotCarryable() throws {
        var world = MazeWorld(maze: try TestMaze.shaft())
        _ = world.run(frames: 200, input: .none)

        #expect(world.interact() != .pickedUp(.tombstone))
        #expect(world.player.carried == nil)
    }

    @Test("After a fatal fall the worm respawns on the last solid ground")
    func respawnsOnSolidGround() throws {
        var world = MazeWorld(maze: try TestMaze.shaft())
        let spawn = world.player.position

        // Stop at the moment of death: respawning at the top of a shaft puts the
        // worm straight back into free fall, so a later sample proves nothing.
        var positionAtRespawn: Vec2?
        for _ in 0..<300 {
            let events = world.update(deltaTime: 1.0 / 60.0, input: .none)
            if events.contains(.died(.fall)) {
                positionAtRespawn = world.player.position
                break
            }
        }

        let landed = try #require(positionAtRespawn)
        #expect(world.roomID == RoomID("0,0"))
        #expect(abs(landed.x - spawn.x) < 0.01)
        #expect(abs(landed.y - spawn.y) < 0.01)
    }

    @Test("Three deaths end the game")
    func threeLives() throws {
        var world = MazeWorld(maze: try TestMaze.shaft())

        for _ in 0..<3 {
            _ = world.run(frames: 300, input: .none)
        }

        #expect(world.lives == 0)
        #expect(world.isGameOver)
    }

    @Test("Restart hands back three lives")
    func restartRestoresLives() throws {
        var world = MazeWorld(maze: try TestMaze.shaft())
        _ = world.run(frames: 200, input: .none)
        #expect(world.lives < 3)

        world.restart()

        #expect(world.lives == 3)
        #expect(!world.isGameOver)
        #expect(world.roomID == RoomID("0,0"))
    }
}
