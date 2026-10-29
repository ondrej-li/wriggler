import Foundation

/// A place to put a worm: the room it is in and its centre, in tiles.
public struct WormSpawn: Sendable, Equatable {
    public let room: RoomID
    public let position: Vec2

    public init(room: RoomID, position: Vec2) {
        self.room = room
        self.position = position
    }
}

/// One of the worms the game steers instead of the player.
///
/// A rival is an ordinary worm - same body, same collision, same gravity - that
/// gets its input from a wander policy instead of the touch controls, so it
/// crawls the maze on its own and can be met in any room.
public struct RivalWorm: Sendable, Equatable {
    public let id: Int
    public private(set) var room: RoomID
    public private(set) var body: MazePlayer

    /// Direction of travel. Zero means the worm has stopped.
    private var heading: Vec2
    /// Seconds left before it picks a new direction.
    private var decisionDelay: Double
    private var seed: UInt64
    /// The last spot it stood on solid ground. A fatal fall puts it back here
    /// instead of killing it, so the race never loses a competitor for good.
    private var resting: WormSpawn

    /// Rivals crawl a little slower than the player, so the race stays winnable.
    private static let rivalSpeed: Double = MazePlayer.defaultWalkSpeed * 0.65
    /// How far ahead the worm checks for walls, in tiles.
    private static let feeler: Double = 0.35
    /// Shortest and longest a rival keeps a direction before thinking again.
    private static let minDecision: Double = 0.35
    private static let maxDecision: Double = 1.25
    /// How often a rival that could keep going actually does.
    private static let keepGoingChance: Double = 0.6

    public init(id: Int, spawn: WormSpawn, seed: UInt64 = 0x2545_F491_4F6C_DD1D) {
        self.id = id
        self.room = spawn.room
        self.body = MazePlayer(position: spawn.position, speed: Self.rivalSpeed)
        self.heading = Vec2(x: 1, y: 0)
        self.decisionDelay = 0
        self.seed = seed
        self.resting = spawn
    }

    public var position: Vec2 { body.position }
    public var facing: Facing { body.facing }

    /// Applies one frame of its own steering. Returns the doorway it walked
    /// through, if it left the room; the caller moves it to the other side.
    public mutating func advance(
        deltaTime: Double,
        room: Room,
        exits: [RoomExit],
        movement: MazeMovement
    ) -> RoomExit? {
        let dt = min(deltaTime, 1.0 / 30.0)
        decisionDelay -= dt
        if decisionDelay <= 0 || blocked(ahead: heading, in: room) {
            chooseHeading(in: room)
            decisionDelay = Self.minDecision + nextRandom() * (Self.maxDecision - Self.minDecision)
        }

        let input = GameInput(moveX: heading.x, moveY: heading.y)
        let (step, exit, fellTooFar) = movement.move(
            player: body,
            input: input,
            room: room,
            exits: exits,
            dt: dt
        )
        body.position = step.position
        body.facing = step.facing
        body.fallSpeed = step.fallSpeed
        body.fallDistance = step.fallDistance

        if fellTooFar {
            self.room = resting.room
            body.position = resting.position
            body.fallSpeed = 0
            body.fallDistance = 0
            heading = Vec2(x: 0, y: 0)
            return nil
        }

        if !room.hasGravity || body.isOnGround {
            resting = WormSpawn(room: self.room, position: body.position)
        }
        return exit
    }

    /// Puts the worm on the far side of a doorway it just crawled through.
    public mutating func enter(_ destination: RoomID, at position: Vec2, hasGravity: Bool) {
        room = destination
        body.position = position
        if !hasGravity {
            body.fallSpeed = 0
            body.fallDistance = 0
        }
    }

    // MARK: - Steering

    private mutating func chooseHeading(in room: Room) {
        // Gardens are crawled in eight directions; the underground is walked
        // left and right and left to gravity, the same rules the player has.
        let candidates =
            room.hasGravity
            ? [Vec2(x: -1, y: 0), Vec2(x: 1, y: 0)]
            : Self.surfaceDirections
        let open = candidates.filter { !blocked(ahead: $0, in: room) }
        guard !open.isEmpty else {
            heading = Vec2(x: 0, y: 0)
            return
        }
        let canKeepGoing = open.contains { $0 == heading }
        if canKeepGoing, nextRandom() < Self.keepGoingChance {
            return
        }
        heading = open[Int(nextRandom() * Double(open.count))]
    }

    private func blocked(ahead direction: Vec2, in room: Room) -> Bool {
        let centre = body.position + direction * Self.feeler
        let half = body.bodySize / 2
        return room.blocks(
            AABB(
                x: centre.x - half,
                y: centre.y - half,
                width: body.bodySize,
                height: body.bodySize
            )
        )
    }

    private static let surfaceDirections: [Vec2] = {
        var directions: [Vec2] = []
        for x in -1...1 {
            for y in -1...1 where !(x == 0 && y == 0) {
                let direction = Vec2(x: Double(x), y: Double(y))
                directions.append(direction / direction.length)
            }
        }
        return directions
    }()

    private mutating func nextRandom() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 11) / Double(UInt64(1) << 53)
    }
}
