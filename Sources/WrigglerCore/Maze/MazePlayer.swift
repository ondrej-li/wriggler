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
    /// What the worm is holding, if anything.
    public var carried: Item?
    /// Which way it last moved, used to face the sprite.
    public var facing: Facing

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
}

/// Moves the player around a room, in eight directions, with tile collision.
public struct MazeMovement: Sendable {
    public init() {}

    public struct Step: Sendable {
        public var position: Vec2
        public var facing: Facing
    }

    /// Applies one frame of input. Returns the new position and the room exit the
    /// player walked through, if any.
    public func move(player: MazePlayer, input: GameInput, room: Room, exits: [RoomExit], dt: Double) -> (
        Step, RoomExit?
    ) {
        var position = player.position
        var facing = player.facing

        var direction = Vec2(x: input.moveX, y: input.moveY)
        if direction.length > 1 {
            direction = direction / direction.length
        }

        if abs(direction.x) > 0.01 {
            facing = direction.x > 0 ? .right : .left
        }

        let delta = direction * (player.speed * dt)
        if delta.x != 0 {
            position.x = slidX(position, half: player.half, dx: delta.x, room: room, exits: exits)
        }
        if delta.y != 0 {
            position.y = slidY(position, half: player.half, dx: delta.y, room: room, exits: exits)
        }

        let exit = exitCrossed(at: position, half: player.half, room: room, exits: exits)
        return (Step(position: position, facing: facing), exit)
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
