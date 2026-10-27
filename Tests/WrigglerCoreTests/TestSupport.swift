import Testing
import WrigglerCore

/// Compares doubles that are the result of accumulated steps.
func isClose(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-6) -> Bool {
    abs(lhs - rhs) <= tolerance
}

/// Small helpers shared by the tests.
enum TestMap {
    static func make(_ rows: [String]) -> TileMap {
        let grid: [[Tile]] = rows.map { row in
            row.map { character in
                switch character {
                case "#": .solid
                case "=": .platform
                case "H": .ladder
                case "^": .hazard
                case "*": .goal
                default: .empty
                }
            }
        }
        return TileMap(rows: grid)
    }

    static func level(_ rows: [String], spawn: GridPoint = GridPoint(x: 1, y: 1)) -> Level {
        Level(name: "test", map: make(rows), playerSpawn: spawn)
    }
}

extension World {
    /// Advances the world for `seconds` using the same fixed-step path as the game.
    mutating func run(seconds: Double, input: GameInput = .none) {
        var remaining = seconds
        let frame = 1.0 / 60.0
        while remaining > 0 {
            _ = advance(deltaTime: min(frame, remaining), input: input)
            remaining -= frame
        }
    }
}

extension TileCollision {
    /// Moves in sub-tile steps, mirroring the fixed-step loop the game uses.
    ///
    /// `move` resolves a single short step; larger teleports would skip tiles.
    @discardableResult
    func step(_ body: inout KinematicBody, by delta: Vec2, steps: Int = 20) -> MoveResult {
        var result: MoveResult = []
        for _ in 0..<steps {
            result.formUnion(move(&body, by: delta / Double(steps)))
        }
        return result
    }
}
