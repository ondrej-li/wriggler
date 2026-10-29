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

    @Test("The same seed produces the same race")
    func rivalsAreDeterministic() throws {
        let maze = try TestMaze.corridor()
        var first = world(maze, spawns: [Vec2(x: 2, y: 2)])
        var second = world(maze, spawns: [Vec2(x: 2, y: 2)])

        first.run(frames: 200, input: .none)
        second.run(frames: 200, input: .none)

        #expect(first.rivals == second.rivals)
    }

    @Test("A rival walks through a doorway into the next room")
    func rivalCrossesDoorways() throws {
        let maze = try TestMaze.corridor()
        var world = world(maze, spawns: [Vec2(x: 2, y: 3)])

        var crossed = false
        for _ in 0..<1800 where !crossed {
            world.update(deltaTime: 1.0 / 60.0, input: .none)
            crossed = world.rivals.contains { $0.room == RoomID("0,1") }
        }
        #expect(crossed, "the rival never found the doorway")
        // The worm it left behind is not drawn any more.
        #expect(world.rivalsInRoom.isEmpty)
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
