import Foundation
import Testing
import WrigglerCore

@Suite("Rival worms")
struct RivalWormTests {
    private func world(_ maze: Maze, spawns: [Vec2]) -> MazeWorld {
        MazeWorld(
            maze: maze,
            rivals: spawns.map { WormSpawn(room: maze.spawnRoom, position: $0) }
        )
    }

    @Test("Rivals start where they are put and crawl on their own")
    func rivalsMove() throws {
        let maze = try TestMaze.corridor()
        var world = world(maze, spawns: [Vec2(x: 2, y: 2), Vec2(x: 7, y: 4)])
        let start = world.rivals.map(\.position)

        world.run(frames: 120, input: .none)

        for (index, rival) in world.rivals.enumerated() {
            let travelled = (rival.position - start[index]).length
            #expect(travelled > 1.0, "rival \(index) never moved")
        }
    }

    @Test("Rivals only ever stand on room they can crawl on")
    func rivalsStayOnTheFloor() throws {
        let maze = try TestMaze.blocked()
        var world = world(maze, spawns: [Vec2(x: 2, y: 2), Vec2(x: 2, y: 4)])

        for _ in 0..<600 {
            world.update(deltaTime: 1.0 / 60.0, input: .none)
            for rival in world.rivals {
                let room = try #require(maze.room(rival.room))
                #expect(
                    room.isPassable(x: Int(rival.position.x), y: Int(rival.position.y)),
                    "rival \(rival.id) crawled into a wall at \(rival.position)"
                )
            }
        }
    }

    @Test("A rival does not grind against the room edge")
    func rivalsDoNotStallAtTheEdge() throws {
        let url = try #require(
            Bundle(for: Token.self).url(forResource: "maze", withExtension: "json", subdirectory: "Maze")
        )
        let maze = try Maze(definition: try MazeDefinition.load(from: try Data(contentsOf: url)))
        let spawns = [Vec2(x: 9.5, y: 9), Vec2(x: 14.5, y: 9), Vec2(x: 9.7, y: 6.9)]
        var world = MazeWorld(
            maze: maze,
            rivals: spawns.map { WormSpawn(room: maze.spawnRoom, position: $0) }
        )
        var last = spawns
        var motionless = 0
        let frames = 3000

        for _ in 0..<frames {
            world.update(deltaTime: 1.0 / 60.0, input: .none)
            for (index, rival) in world.rivals.enumerated() where (rival.position - last[index]).length < 0.001 {
                motionless += 1
            }
            last = world.rivals.map { $0.position }
        }

        // An eighth of the frames would be a rival stuck at the edge for a second.
        #expect(motionless < frames / 40, "rivals spent \(motionless) frames standing still")
    }

    @Test("The same seed produces the same race")
    func rivalsAreDeterministic() throws {
        let maze = try TestMaze.corridor()
        var first = world(maze, spawns: [Vec2(x: 2, y: 2)])
        var second = world(maze, spawns: [Vec2(x: 2, y: 2)])

        first.run(frames: 200, input: .none)
        second.run(frames: 200, input: .none)

        #expect(first.rivals == second.rivals)
    }

    @Test("Rivals do not all wander in lockstep")
    func rivalsWanderIndependently() throws {
        let maze = try TestMaze.corridor()
        var world = world(maze, spawns: [Vec2(x: 2, y: 2), Vec2(x: 2, y: 2), Vec2(x: 2, y: 2)])

        world.run(frames: 240, input: .none)

        let headings = Set(world.rivals.map { "\($0.heading.x),\($0.heading.y)" })
        #expect(headings.count > 1, "every rival chose the same path")
    }

    @Test("Rivals walk through doorways into the next room")
    func rivalsCrossDoorways() throws {
        let maze = try TestMaze.corridor()
        // The door is in the middle of the shared right edge, but a wanderer only
        // finds it by luck, so send a crowd and let them bump into it.
        let spawns = (0..<8).map { Vec2(x: 2 + Double($0 % 3), y: 1 + Double($0)) }
        var world = world(maze, spawns: spawns)

        var crossed = false
        for _ in 0..<3600 where !crossed {
            world.update(deltaTime: 1.0 / 60.0, input: .none)
            crossed = world.rivals.contains { $0.room == RoomID("0,1") }
        }

        #expect(crossed, "no rival ever found the doorway")
        // The worm that left is not drawn in the room it left behind.
        #expect(world.rivalsInRoom.count == world.rivals.filter { $0.room == world.roomID }.count)
        #expect(world.rivalsInRoom.count < world.rivals.count)
    }

    @Test("A fatal fall puts a rival back on its last ledge")
    func rivalSurvivesAFatalFall() throws {
        let maze = try TestMaze.shaft()
        var world = world(maze, spawns: [Vec2(x: 5, y: 0.5)])
        let start = try #require(world.rivals.first)

        var deepest = 0.0
        for _ in 0..<600 {
            world.update(deltaTime: 1.0 / 60.0, input: .none)
            let rival = try #require(world.rivals.first)
            #expect(
                rival.body.fallDistance <= MazePlayer.safeFallDistance + 1,
                "the rival fell without ever being put back on a ledge"
            )
            deepest = max(deepest, rival.position.y)
        }

        let rival = try #require(world.rivals.first)
        #expect(rival.body.fallDistance == 0, "the rival is still falling")
        #expect(maze.rooms[rival.room] != nil)
        #expect(deepest > start.position.y, "the rival never fell at all")
    }

    @Test("The player's worm is the bottom-left one on the opening screen")
    func playerIsTheBottomLeftWorm() throws {
        let maze = try TestMaze.corridor()
        let spawns = [Vec2(x: 2, y: 2), Vec2(x: 2, y: 4), Vec2(x: 7, y: 2), Vec2(x: 7, y: 4)]
        let player = spawns.max { left, right in
            (left.y, -left.x) < (right.y, -right.x)
        }

        #expect(player == Vec2(x: 2, y: 4))
        let world = MazeWorld(
            maze: maze,
            start: player.map { WormSpawn(room: maze.spawnRoom, position: $0) },
            rivals: spawns.filter { $0 != player }.map { WormSpawn(room: maze.spawnRoom, position: $0) }
        )
        #expect(world.player.position == Vec2(x: 2, y: 4))
        #expect(world.rivals.count == 3)
    }
}

private final class Token {}
