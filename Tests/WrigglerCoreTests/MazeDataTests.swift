import Foundation
import Testing
import WrigglerCore

@Suite("Maze data")
struct MazeDataTests {
    @Test("The bundled maze decodes with every room and link")
    func bundledMaze() throws {
        let url = try #require(
            Bundle(for: BundleToken.self).url(
                forResource: "maze",
                withExtension: "json",
                subdirectory: "Maze"
            ),
            "maze.json missing from the test bundle"
        )
        let maze = try Maze(definition: try MazeDefinition.load(from: try Data(contentsOf: url)))

        #expect(maze.roomCount == 244)
        #expect(maze.columns == 30)
        #expect(maze.rows == 16)
        #expect(maze.spawnRoom == RoomID("3,13"))
        #expect(maze.exits.values.reduce(0) { $0 + $1.count } == 670)

        let start = try #require(maze.room(RoomID("3,13")!))
        #expect(start.kind(at: maze.spawnPosition) == .floor, "the player must spawn on floor")

        let exits = maze.exits(from: RoomID("3,13")!)
        #expect(exits.count == 1)
        #expect(exits.first?.doorway.side == .right)
        #expect(exits.first?.destination == RoomID("3,14"))
    }

    @Test("Every doorway leads to a room that leads back")
    func linksAreSymmetric() throws {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: "maze", withExtension: "json", subdirectory: "Maze")
        )
        let maze = try Maze(definition: try MazeDefinition.load(from: try Data(contentsOf: url)))

        for (room, exits) in maze.exits {
            for exit in exits {
                let back = maze.exits(from: exit.destination)
                #expect(
                    back.contains { $0.destination == room },
                    "\(room) -> \(exit.destination) has no way back"
                )
            }
        }
    }
}

@Suite("Rooms")
struct RoomTests {
    @Test("Tiles outside the room do not block, the edge is enforced elsewhere")
    func outOfBoundsIsNotBlocking() throws {
        let maze = try TestMaze.corridor()
        let room = try #require(maze.room(RoomID("0,0")!))

        #expect(!room.blocks(AABB(x: -1, y: 2, width: 0.5, height: 0.5)))
        #expect(!room.blocks(AABB(x: 9.8, y: 2, width: 0.5, height: 0.5)))
    }

    @Test("Brick blocks, floor does not")
    func blocking() throws {
        let maze = try TestMaze.blocked()
        let room = try #require(maze.room(RoomID("0,0")!))

        #expect(!room.blocks(AABB(x: 1, y: 1, width: 0.9, height: 0.9)))
        #expect(room.blocks(AABB(x: 4.5, y: 1, width: 0.9, height: 0.9)))
    }

    @Test("Kind lookup converts a position to its cell")
    func kindAtPosition() throws {
        let maze = try TestMaze.blocked()
        let room = try #require(maze.room(RoomID("0,0")!))

        #expect(room.kind(at: Vec2(x: 1.5, y: 1.5)) == .floor)
        #expect(room.kind(at: Vec2(x: 5.5, y: 1.5)) == .brick)
    }
}

private final class BundleToken {}
