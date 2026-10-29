import Foundation
import WrigglerCore

/// Small mazes for the tests, built through the same JSON path the game uses.
enum TestMaze {
    static let allFloor = Array(repeating: String(repeating: ".", count: 10), count: 6)

    /// Two rooms side by side, joined by a doorway in the middle of the shared edge.
    static func corridor() throws -> Maze {
        try build(
            rooms: [
                "0,0": rows(allFloor),
                "0,1": rows(allFloor),
            ],
            links: [
                "0,0,4": Link(to: "0,1,a", side: "right", at: 3, width: 2),
                "0,1,a": Link(to: "0,0,4", side: "left", at: 3, width: 2),
            ])
    }

    /// One room with a wall down the middle at column 5, and a doorway on the right.
    static func blocked() throws -> Maze {
        let walled = (0..<6).map { _ in ".....#...." }
        return try build(rooms: ["0,0": rows(walled)], links: [:])
    }

    struct Link {
        let to: String
        let side: String
        let at: Double
        let width: Double
    }

    static func rows(_ lines: [String]) -> [String] { lines }

    static func build(rooms: [String: [String]], links: [String: Link]) throws -> Maze {
        let roomJSON = rooms.map { key, lines in
            "\"\(key)\":{\"rows\":[\(lines.map { "\"\($0)\"" }.joined(separator: ","))]}"
        }
        let linkJSON = links.map { key, link in
            """
            "\(key)":{"to":"\(link.to)","side":"\(link.side)","at":\(link.at),"width":\(link.width)}
            """
        }
        let json = """
            {
              "version": 1,
              "cell": 8,
              "room": {"columns": 10, "rows": 6},
              "tiles": {".": "floor", "#": "brick", "v": "foliage", "w": "water", "s": "sign"},
              "spawn": {"room": "0,0", "x": 2, "y": 3},
              "rooms": {\(roomJSON.joined(separator: ","))},
              "links": {\(linkJSON.joined(separator: ","))}
            }
            """
        return try Maze(definition: try MazeDefinition.load(from: Data(json.utf8)))
    }
}

extension MazeWorld {
    /// Runs the world at 60 Hz for a number of frames.
    mutating func run(frames: Int, input: GameInput) -> [MazeEvent] {
        var events: [MazeEvent] = []
        for _ in 0..<frames {
            events.append(contentsOf: update(deltaTime: 1.0 / 60.0, input: input))
        }
        return events
    }
}
