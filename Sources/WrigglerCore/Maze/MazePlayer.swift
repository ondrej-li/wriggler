import Foundation

/// The worm the player steers.
public struct MazePlayer: Sendable, Equatable {
    /// Centre of the body, in tiles.
    public var position: Vec2
    /// Width and height of the body's box, in tiles.
    public var bodySize: Double
    public var speed: Double

    public static let defaultBodySize: Double = 0.9
    public static let defaultWalkSpeed: Double = 6.0
    /// Gravity in the underground, in tiles per second squared.
    public static let gravity: Double = 34
    /// Terminal velocity, in tiles per second.
    public static let maxFallSpeed: Double = 26
    /// A fall longer than one screen kills the worm.
    public static let safeFallDistance: Double = 16
    /// What the worm is holding, if anything.
    public var carried: Item?
    /// Which way it last moved, used to face the sprite.
    public var facing: Facing
    /// Vertical speed in the underground, in tiles per second, positive downwards.
    public var fallSpeed: Double = 0
    /// Distance fallen since last standing on something. Falling more than one
    /// screen is fatal.
    public var fallDistance: Double = 0

    public init(
        position: Vec2,
        bodySize: Double = MazePlayer.defaultBodySize,
        speed: Double = MazePlayer.defaultWalkSpeed,
        facing: Facing = .right
    ) {
        self.position = position
        self.bodySize = bodySize
        self.speed = speed
        self.carried = nil
        self.facing = facing
    }

    var half: Double { bodySize / 2 }

    var bounds: AABB {
        AABB(
            x: position.x - half,
            y: position.y - half,
            width: bodySize,
            height: bodySize
        )
    }

    /// Distance at which an object on the floor can be reached.
    public var reach: Double { 1.0 }

    public var isOnGround: Bool { fallSpeed == 0 && fallDistance == 0 }
}

/// Moves the player around a room, in eight directions, with tile collision.
public struct MazeMovement: Sendable {
    public init() {}

    public struct Step: Sendable {
        public var position: Vec2
        public var facing: Facing
        public var fallSpeed: Double
        public var fallDistance: Double
    }

    /// Applies one frame of input.
    ///
    /// Returns the new state, the room exit the worm walked through, if any, and
    /// whether a long fall just became fatal.
    public func move(
        player: MazePlayer,
        input: GameInput,
        room: Room,
        exits: [RoomExit],
        dt: Double
    ) -> (Step, RoomExit?, Bool) {
        room.hasGravity
            ? undergroundMove(player: player, input: input, room: room, exits: exits, dt: dt)
            : surfaceMove(player: player, input: input, room: room, exits: exits, dt: dt)
    }

    /// Gardens: the worm crawls in any of eight directions, no gravity.
    private func surfaceMove(
        player: MazePlayer,
        input: GameInput,
        room: Room,
        exits: [RoomExit],
        dt: Double
    ) -> (Step, RoomExit?, Bool) {
        var step = Step(position: player.position, facing: player.facing, fallSpeed: 0, fallDistance: 0)

        var direction = Vec2(x: input.moveX, y: input.moveY)
        if direction.length > 1 {
            direction = direction / direction.length
        }
        if abs(direction.x) > 0.01 {
            step.facing = direction.x > 0 ? .right : .left
        }

        let delta = direction * (player.speed * dt)
        if delta.x != 0 {
            step.position.x = slidX(step.position, half: player.half, dx: delta.x, room: room, exits: exits)
        }
        if delta.y != 0 {
            step.position.y = slidY(step.position, half: player.half, dx: delta.y, room: room, exits: exits)
        }

        let exit = exitCrossed(at: step.position, half: player.half, room: room, exits: exits)
        return (step, exit, false)
    }

    /// The underground: walk left and right, gravity does the rest.
    ///
    /// Upward input is ignored - the worm cannot crawl up, it can only fall into
    /// shafts and walk along whatever it lands on.
    private func undergroundMove(
        player: MazePlayer,
        input: GameInput,
        room: Room,
        exits: [RoomExit],
        dt: Double
    ) -> (Step, RoomExit?, Bool) {
        var position = player.position
        var facing = player.facing
        var fallSpeed = player.fallSpeed
        var fallDistance = player.fallDistance
        var died = false

        if input.moveX != 0 {
            facing = input.moveX > 0 ? .right : .left
            let dx = input.moveX * player.speed * dt
            position.x = slidX(position, half: player.half, dx: dx, room: room, exits: exits)
        }

        fallSpeed = min(fallSpeed + MazePlayer.gravity * dt, MazePlayer.maxFallSpeed)
        let dy = fallSpeed * dt
        let feet = position.y + player.half
        let targetFeet = feet + dy

        if let floorTop = room.floorBelow(
            x: position.x - player.half,
            width: player.bodySize,
            feet: feet,
            limit: targetFeet
        ) {
            // Land on the ledge: the fall ends here.
            position.y = floorTop - player.half
            fallSpeed = 0
            fallDistance = 0
        } else {
            position.y += dy
            fallDistance += dy
            if fallDistance > MazePlayer.safeFallDistance {
                died = true
            }
        }

        let exit = exitCrossed(at: position, half: player.half, room: room, exits: exits)
        let step = Step(position: position, facing: facing, fallSpeed: fallSpeed, fallDistance: fallDistance)
        return (step, exit, died)
    }

    /// Where the player lands when arriving through `doorway` of a room.
    public func arrivalPosition(for doorway: Doorway, room: Room, player: MazePlayer) -> Vec2 {
        let inset = player.half + 0.05
        switch doorway.side {
        case .left: return Vec2(x: inset, y: doorway.at)
        case .right: return Vec2(x: Double(room.columns) - inset, y: doorway.at)
        case .top: return Vec2(x: doorway.at, y: inset)
        case .bottom: return Vec2(x: doorway.at, y: Double(room.rows) - inset)
        }
    }

    // MARK: - Horizontal

    private func slidX(_ position: Vec2, half: Double, dx: Double, room: Room, exits: [RoomExit]) -> Double {
        let target = position.x + dx
        let rect = AABB(x: target - half, y: position.y - half, width: half * 2, height: half * 2)
        if !room.blocks(rect) {
            return clampToRoom(Vec2(x: target, y: position.y), half: half, room: room, exits: exits).x
        }
        return position.x
    }

    // MARK: - Vertical

    private func slidY(_ position: Vec2, half: Double, dx: Double, room: Room, exits: [RoomExit]) -> Double {
        let target = position.y + dx
        let rect = AABB(x: position.x - half, y: target - half, width: half * 2, height: half * 2)
        if !room.blocks(rect) {
            return clampToRoom(Vec2(x: position.x, y: target), half: half, room: room, exits: exits).y
        }
        return position.y
    }

    /// Keeps the body inside the room, except where a doorway lets it out.
    private func clampToRoom(_ position: Vec2, half: Double, room: Room, exits: [RoomExit]) -> Vec2 {
        var point = position
        let inside = DoorwayInset(half: half, room: room)

        let onLeftExit = doorwayExit(exits, side: .left)?.doorway.contains(point.y, slack: -half) ?? false
        let onRightExit = doorwayExit(exits, side: .right)?.doorway.contains(point.y, slack: -half) ?? false
        let onTopExit = doorwayExit(exits, side: .top)?.doorway.contains(point.x, slack: -half) ?? false
        let onBottomExit = doorwayExit(exits, side: .bottom)?.doorway.contains(point.x, slack: -half) ?? false

        if !onLeftExit { point.x = max(point.x, inside.minX) }
        if !onRightExit { point.x = min(point.x, inside.maxX) }
        if !onTopExit { point.y = max(point.y, inside.minY) }
        if !onBottomExit { point.y = min(point.y, inside.maxY) }
        return point
    }

    private struct DoorwayInset {
        let minX: Double
        let maxX: Double
        let minY: Double
        let maxY: Double

        init(half: Double, room: Room) {
            minX = half
            maxX = Double(room.columns) - half
            minY = half
            maxY = Double(room.rows) - half
        }
    }

    private func doorwayExit(_ exits: [RoomExit], side: Side) -> RoomExit? {
        exits.first { $0.doorway.side == side }
    }

    /// Did the body's centre pass out of the room through a doorway?
    private func exitCrossed(at position: Vec2, half: Double, room: Room, exits: [RoomExit]) -> RoomExit? {
        for exit in exits {
            switch exit.doorway.side {
            case .left where position.x - half < 0 && exit.doorway.contains(position.y, slack: half):
                return exit
            case .right
            where position.x + half > Double(room.columns) && exit.doorway.contains(position.y, slack: half):
                return exit
            case .top where position.y - half < 0 && exit.doorway.contains(position.x, slack: half):
                return exit
            case .bottom where position.y + half > Double(room.rows) && exit.doorway.contains(position.x, slack: half):
                return exit
            default:
                continue
            }
        }
        return nil
    }
}
