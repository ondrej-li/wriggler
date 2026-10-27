import Foundation

public enum Facing: Sendable, Equatable {
    case left
    case right

    public var sign: Double { self == .left ? -1 : 1 }
}

public enum PlayerState: String, Sendable, Equatable {
    case idle
    case running
    case jumping
    case falling
    case climbing
    case dead
}

/// Movement tuning for the player. All values are in tiles and seconds.
public struct PlayerConfig: Sendable, Equatable {
    public var size = Vec2(x: 1.75, y: 1.9)
    public var moveSpeed: Double = 8
    public var groundAcceleration: Double = 90
    public var groundFriction: Double = 110
    public var airAcceleration: Double = 55
    public var jumpVelocity: Double = 21
    public var jumpCutVelocity: Double = 8
    public var gravity: Double = 62
    public var maxFallSpeed: Double = 30
    public var climbSpeed: Double = 5
    public var coyoteTime: Double = 0.09
    public var jumpBufferTime: Double = 0.1

    public init() {}

    public static let `default` = PlayerConfig()
}

public struct Player: Sendable, Equatable {
    public var body: KinematicBody
    public var facing: Facing = .right
    public var state: PlayerState = .idle
    public var isAlive = true

    var coyoteTimer: Double = 0
    var jumpBufferTimer: Double = 0

    public var config: PlayerConfig

    public init(spawnCell: GridPoint, config: PlayerConfig = .default) {
        self.config = config
        self.body = KinematicBody(
            position: Self.spawnPosition(cell: spawnCell, size: config.size),
            size: config.size
        )
    }

    /// Places the body horizontally centred in `cell` with its feet on the cell's bottom edge.
    public static func spawnPosition(cell: GridPoint, size: Vec2) -> Vec2 {
        Vec2(
            x: Double(cell.x) + (1 - size.x) / 2,
            y: Double(cell.y + 1) - size.y
        )
    }
}

/// Applies input to the player and integrates it against the tile map.
public struct PlayerController: Sendable {
    public init() {}

    public func update(player: inout Player, input: GameInput, collision: TileCollision, dt: Double) {
        guard player.isAlive else {
            player.state = .dead
            return
        }

        let config = player.config
        let wasOnGround = player.body.isOnGround

        // Timers: coyote time for forgiving edges, jump buffer for early presses.
        player.jumpBufferTimer =
            input.jumpPressed
            ? config.jumpBufferTime
            : max(0, player.jumpBufferTimer - dt)
        player.coyoteTimer =
            wasOnGround
            ? config.coyoteTime
            : max(0, player.coyoteTimer - dt)

        let onLadder = collision.isTouchingLadder(player.body)
        if !onLadder {
            player.body.isClimbing = false
        } else if abs(input.moveY) > 0.1 || player.body.isClimbing {
            player.body.isClimbing = true
        }

        if player.body.isClimbing {
            if onLadder {
                player.body.velocity.y = input.moveY * config.climbSpeed
                player.body.velocity.x = input.moveX * config.climbSpeed * 0.75
            } else {
                player.body.isClimbing = false
            }

            // Jumping off a ladder keeps the horizontal intent.
            if player.jumpBufferTimer > 0 {
                player.body.isClimbing = false
                player.body.velocity.y = -config.jumpVelocity * 0.85
                player.jumpBufferTimer = 0
            }
        } else {
            let targetSpeed = input.moveX * config.moveSpeed
            let acceleration: Double
            if abs(input.moveX) > 0.01 {
                acceleration = wasOnGround ? config.groundAcceleration : config.airAcceleration
            } else {
                acceleration = wasOnGround ? config.groundFriction : config.airAcceleration * 0.25
            }
            player.body.velocity.x = moveTowards(player.body.velocity.x, targetSpeed, acceleration * dt)

            player.body.velocity.y = min(player.body.velocity.y + config.gravity * dt, config.maxFallSpeed)

            if player.jumpBufferTimer > 0, player.coyoteTimer > 0 {
                player.body.velocity.y = -config.jumpVelocity
                player.jumpBufferTimer = 0
                player.coyoteTimer = 0
                player.body.isOnGround = false
            }

            // Releasing jump early shortens the arc.
            if !input.jumpHeld, player.body.velocity.y < -config.jumpCutVelocity {
                player.body.velocity.y = -config.jumpCutVelocity
            }
        }

        if abs(input.moveX) > 0.1 {
            player.facing = input.moveX > 0 ? .right : .left
        }

        collision.move(
            &player.body,
            by: Vec2(x: player.body.velocity.x * dt, y: player.body.velocity.y * dt)
        )

        player.state = Self.state(for: player, wasOnGround: wasOnGround, input: input)
    }

    private static func state(for player: Player, wasOnGround: Bool, input: GameInput) -> PlayerState {
        if player.body.isClimbing { return .climbing }
        if !player.body.isOnGround {
            return player.body.velocity.y < 0 ? .jumping : .falling
        }
        if !wasOnGround { return .idle }
        return abs(player.body.velocity.x) > 0.2 ? .running : .idle
    }
}
