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

    /// A vertical shaft: four underground rooms stacked, joined top to bottom,
    /// with nothing to stand on until the floor of the last one. Each room adds
    /// about five tiles of fall, so the drop is a little over one screen - enough
    /// to be fatal without any room being unreasonably deep.
    static func shaft(rooms count: Int = 4) throws -> Maze {
        let open = rows(Array(repeating: String(repeating: ".", count: 10), count: 6))
        let floor = rows(Array(repeating: String(repeating: ".", count: 10), count: 5) + ["##########"])
        var rooms: [String: ([String], String)] = [:]
        var links: [String: Link] = [:]
        for index in 0..<count {
            rooms["\(index),0"] = (index == count - 1 ? floor : open, "underground")
            guard index < count - 1 else { continue }
            links["\(index),0,7"] = Link(
                to: "\(index + 1),0,1", side: "bottom", at: 5, width: 4
            )
            links["\(index + 1),0,1"] = Link(
                to: "\(index),0,7", side: "top", at: 5, width: 4
            )
        }
        return try build(rooms: rooms, links: links, spawn: (room: "0,0", x: 5, y: 1))
    }

    /// One underground room with a ledge to land on.
    static func ledge() throws -> Maze {
        let rowsWithLedge = [
            "..........",
            "..........",
            "..........",
            "....######",
            "..........",
            "##########",
        ]
        return try build(
            rooms: ["0,0": (rows(rowsWithLedge), "underground")], links: [:],
            spawn: (room: "0,0", x: 6, y: 0.5))
    }

    struct Link {
        let to: String
        let side: String
        let at: Double
        let width: Double
    }

    static func rows(_ lines: [String]) -> [String] { lines }

    static func build(rooms: [String: [String]], links: [String: Link]) throws -> Maze {
        try build(rooms: rooms.mapValues { ($0, "surface") }, links: links, spawn: nil)
    }

    static func build(
        rooms: [String: ([String], String)],
        links: [String: Link],
        spawn: (room: String, x: Double, y: Double)?
    ) throws -> Maze {
        let roomJSON = rooms.map { key, value in
            let lines = value.0
            return
                "\"\(key)\":{\"region\":\"\(value.1)\",\"rows\":[\(lines.map { "\"\($0)\"" }.joined(separator: ","))]}"
        }
        let linkJSON = links.map { key, link in
            """
            "\(key)":{"to":"\(link.to)","side":"\(link.side)","at":\(link.at),"width":\(link.width)}
            """
        }
        let spawnEntry =
            spawn.map { "\"room\":\"\($0.room)\",\"x\":\($0.x),\"y\":\($0.y)" }
            ?? "\"room\":\"0,0\",\"x\":2,\"y\":3"
        let json = """
            {
              "version": 1,
              "cell": 8,
              "room": {"columns": 10, "rows": 6},
              "tiles": {".": "floor", "#": "brick", "v": "foliage", "w": "water", "s": "sign"},
              "spawn": {\(spawnEntry)},
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
