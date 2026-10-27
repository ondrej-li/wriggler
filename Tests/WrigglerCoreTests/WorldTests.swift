import Testing
import WrigglerCore

@Suite("World")
struct WorldTests {
    @Test("Fixed-step updates accumulate real time")
    func elapsedTime() {
        var world = World(
            level: TestMap.level([
                ".....",
                ".....",
                "#####",
            ]))

        world.run(seconds: 1.0)
        #expect(abs(world.elapsed - 1.0) < 0.02)
    }

    @Test("A single huge frame cannot tunnel the player through the floor")
    func noTunneling() {
        var world = World(
            level: TestMap.level(
                [
                    ".....",
                    ".....",
                    ".....",
                    ".....",
                    ".....",
                    ".....",
                    ".....",
                    "#####",
                ], spawn: GridPoint(x: 1, y: 1)))

        world.run(seconds: 2.0)
        #expect(world.player.body.feet == 7)
        #expect(world.status == .playing)
    }

    @Test("Hazards kill the player")
    func hazardKills() {
        var world = World(
            level: TestMap.level(
                [
                    "........",
                    "........",
                    "....^...",
                    "########",
                ], spawn: GridPoint(x: 1, y: 2)))

        world.run(seconds: 0.1)
        #expect(world.status == .playing)

        var events: [WorldEvent] = []
        var remaining = 0.8
        while remaining > 0, world.status == .playing {
            events.append(contentsOf: world.advance(deltaTime: 1.0 / 60.0, input: GameInput(moveX: 1)))
            remaining -= 1.0 / 60.0
        }

        #expect(world.status == .died)
        #expect(events.contains(.playerDied))
        #expect(!world.player.isAlive)
    }

    @Test("Reaching the exit completes the level")
    func goalCompletes() {
        var world = World(
            level: TestMap.level(
                [
                    "........",
                    "...*....",
                    "########",
                ], spawn: GridPoint(x: 1, y: 1)))

        var remaining = 2.0
        while remaining > 0, world.status == .playing {
            _ = world.advance(deltaTime: 1.0 / 60.0, input: GameInput(moveX: 1))
            remaining -= 1.0 / 60.0
        }

        #expect(world.status == .completed)
    }

    @Test("Restart resets the level state")
    func restart() {
        var world = World(
            level: TestMap.level(
                [
                    "........",
                    "........",
                    "....^...",
                    "########",
                ], spawn: GridPoint(x: 1, y: 2)))

        world.run(seconds: 1.0, input: GameInput(moveX: 1))
        #expect(world.status == .died)

        world.restart()
        #expect(world.status == .playing)
        #expect(world.elapsed == 0)
        #expect(world.player.isAlive)
        #expect(world.player.body.feet == 3)
    }

    @Test("Enemies patrol and reverse at walls")
    func enemyPatrol() {
        var world = World(
            level: Level(
                name: "patrol",
                map: TestMap.make([
                    "##########",
                    "..e..#....",
                    "##########",
                ]),
                playerSpawn: GridPoint(x: 7, y: 1),
                enemySpawns: [EnemySpawn(cell: GridPoint(x: 2, y: 1))]
            ))

        var directions: Set<Double> = []
        for _ in 0..<300 {
            _ = world.advance(deltaTime: 1.0 / 60.0, input: .none)
            if let enemy = world.enemies.first {
                directions.insert(enemy.direction)
                #expect(enemy.body.position.x >= 0)
                #expect(enemy.body.position.x + enemy.body.size.x <= 10)
            }
        }

        #expect(directions == [-1, 1], "crawler should bounce between the walls")
    }

    @Test("Enemies stay near their spawn point")
    func patrolRange() {
        var world = World(
            level: Level(
                name: "range",
                map: TestMap.make([
                    "################",
                    "..e.............",
                    "################",
                ]),
                playerSpawn: GridPoint(x: 14, y: 1),
                enemySpawns: [EnemySpawn(cell: GridPoint(x: 2, y: 1))]
            ))

        var furthest: Double = 0
        for _ in 0..<400 {
            _ = world.advance(deltaTime: 1.0 / 60.0, input: .none)
            guard let enemy = world.enemies.first else { continue }
            furthest = max(furthest, abs(enemy.body.center.x - enemy.origin.x))
        }

        #expect(furthest <= EnemyConfig.default.patrolRange + 0.5)
    }

    @Test("Enemies turn around at ledges")
    func enemyAvoidsLedge() throws {
        var world = World(
            level: Level(
                name: "ledge",
                map: TestMap.make([
                    "........",
                    "..e.....",
                    "####....",
                    "########",
                ]),
                playerSpawn: GridPoint(x: 6, y: 2),
                enemySpawns: [EnemySpawn(cell: GridPoint(x: 2, y: 1))]
            ))

        for _ in 0..<240 {
            _ = world.advance(deltaTime: 1.0 / 60.0, input: .none)
        }

        let enemy = try #require(world.enemies.first)
        #expect(enemy.body.feet == 2, "crawler must stay on the platform")
    }
}
