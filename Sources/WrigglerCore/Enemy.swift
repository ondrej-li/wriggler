import Foundation

public struct Enemy: Sendable, Equatable {
    public var body: KinematicBody
    public var kind: EnemyKind
    /// `-1` walking left, `1` walking right.
    public var direction: Double
    public var isAlive: Bool
    /// Centre of the spawn cell, used as the anchor for the patrol range.
    public let origin: Vec2

    public var config: EnemyConfig

    public init(spawnCell: GridPoint, kind: EnemyKind, config: EnemyConfig = .default) {
        let position = Player.spawnPosition(cell: spawnCell, size: config.size)
        self.kind = kind
        self.config = config
        self.direction = -1
        self.isAlive = true
        self.body = KinematicBody(position: position, size: config.size)
        self.origin = position + config.size / 2
    }
}

public struct EnemyConfig: Sendable, Equatable {
    public var size: Vec2
    public var speed: Double
    public var gravity: Double
    public var maxFallSpeed: Double
    /// How far the enemy wanders from its spawn point before turning back, in tiles.
    public var patrolRange: Double

    public init(
        size: Vec2 = Vec2(x: 1.5, y: 1.4),
        speed: Double = 2.5,
        gravity: Double = 62,
        maxFallSpeed: Double = 30,
        patrolRange: Double = 5
    ) {
        self.size = size
        self.speed = speed
        self.gravity = gravity
        self.maxFallSpeed = maxFallSpeed
        self.patrolRange = patrolRange
    }

    public static let `default` = EnemyConfig()
}

/// Simple ground patrol: walks until it meets a wall, a ledge or the end of its
/// patrol range, then turns around.
///
/// This is the seam where richer behaviour (chasing, path finding over the maze graph)
/// plugs in later — swap `EnemyController` for another implementation of the same shape.
public struct EnemyController: Sendable {
    public init() {}

    public func update(enemy: inout Enemy, collision: TileCollision, dt: Double) {
        guard enemy.isAlive else { return }

        if enemy.body.isOnGround {
            let travelled = enemy.body.center.x - enemy.origin.x
            let outOfRange =
                enemy.direction > 0
                ? travelled > enemy.config.patrolRange
                : travelled < -enemy.config.patrolRange

            if outOfRange
                || collision.isWallAhead(enemy.body, direction: enemy.direction)
                || !collision.hasFloorAhead(enemy.body, direction: enemy.direction)
            {
                enemy.direction = -enemy.direction
            }
        }

        enemy.body.velocity.x = enemy.direction * enemy.config.speed
        enemy.body.velocity.y = min(enemy.body.velocity.y + enemy.config.gravity * dt, enemy.config.maxFallSpeed)

        collision.move(
            &enemy.body,
            by: Vec2(x: enemy.body.velocity.x * dt, y: enemy.body.velocity.y * dt)
        )
    }
}
