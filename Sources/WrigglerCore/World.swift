import Foundation

public enum GameStatus: Sendable, Equatable {
    case playing
    case died
    case completed

    public var isPlaying: Bool { self == .playing }
}

public enum WorldEvent: Sendable, Equatable {
    case playerDied
    case levelCompleted
}

/// The whole simulation: one maze, one player, some enemies, fixed-step updates.
///
/// `World` is a plain value type with no rendering or platform dependencies, so it is
/// cheap to snapshot, deterministic to test and safe to step off the main actor later.
public struct World: Sendable {
    /// Simulation runs at a fixed rate regardless of display refresh rate.
    public static let fixedTimeStep = 1.0 / 120.0
    /// Upper bound for a single frame delta, guards against long stalls (backgrounding, breakpoints).
    public static let maxFrameTime = 0.25

    public let level: Level
    public private(set) var map: TileMap
    public private(set) var player: Player
    public private(set) var enemies: [Enemy]
    public private(set) var status: GameStatus
    public private(set) var elapsed: Double

    private var collision: TileCollision
    private let playerController = PlayerController()
    private let enemyController = EnemyController()
    private let enemyConfig: EnemyConfig
    private var accumulator: Double

    public init(level: Level, playerConfig: PlayerConfig = .default, enemyConfig: EnemyConfig = .default) {
        self.level = level
        self.map = level.map
        self.player = Player(spawnCell: level.playerSpawn, config: playerConfig)
        self.enemies = level.enemySpawns.map { Enemy(spawnCell: $0.cell, kind: $0.kind, config: enemyConfig) }
        self.status = .playing
        self.elapsed = 0
        self.accumulator = 0
        self.enemyConfig = enemyConfig
        self.collision = TileCollision(map: level.map)
    }

    /// Advances the simulation by `deltaTime` seconds in fixed steps.
    /// - Returns: events produced during this frame, in order.
    public mutating func advance(deltaTime: Double, input: GameInput) -> [WorldEvent] {
        guard status.isPlaying else { return [] }

        var events: [WorldEvent] = []
        accumulator += min(max(deltaTime, 0), Self.maxFrameTime)

        var stepInput = input
        while accumulator >= Self.fixedTimeStep {
            accumulator -= Self.fixedTimeStep
            step(dt: Self.fixedTimeStep, input: stepInput, events: &events)
            stepInput.consumeEdges()
            if !status.isPlaying { break }
        }

        if !status.isPlaying {
            accumulator = 0
        }
        return events
    }

    /// Puts the level back to its initial state.
    public mutating func restart() {
        player = Player(spawnCell: level.playerSpawn, config: player.config)
        enemies = level.enemySpawns.map { Enemy(spawnCell: $0.cell, kind: $0.kind, config: enemyConfig) }
        status = .playing
        elapsed = 0
        accumulator = 0
    }

    // MARK: - Fixed step

    private mutating func step(dt: Double, input: GameInput, events: inout [WorldEvent]) {
        elapsed += dt

        playerController.update(player: &player, input: input, collision: collision, dt: dt)
        for index in enemies.indices {
            enemyController.update(enemy: &enemies[index], collision: collision, dt: dt)
        }

        resolveCollisions(events: &events)
    }

    private mutating func resolveCollisions(events: inout [WorldEvent]) {
        let playerBounds = player.body.bounds.insetBy(dx: 0.25, dy: 0.25)

        if map.rect(playerBounds, overlaps: .goal) {
            status = .completed
            events.append(.levelCompleted)
            return
        }

        if map.rect(playerBounds, overlaps: .hazard) {
            killPlayer(events: &events)
            return
        }

        for enemy in enemies where enemy.isAlive {
            if enemy.body.bounds.insetBy(dx: 0.2, dy: 0.2).intersects(playerBounds) {
                killPlayer(events: &events)
                return
            }
        }
    }

    private mutating func killPlayer(events: inout [WorldEvent]) {
        player.isAlive = false
        player.state = .dead
        status = .died
        events.append(.playerDied)
    }
}
