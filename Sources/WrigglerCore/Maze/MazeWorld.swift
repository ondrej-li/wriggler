import Foundation

public enum DeathCause: Sendable, Equatable {
    /// Fell further than one screen.
    case fall
}

public enum MazeEvent: Sendable, Equatable {
    case enteredRoom(RoomID)
    /// The worm died, a tombstone was left behind and a life was spent.
    case died(DeathCause)
    /// Spawned again after a death.
    case respawned(room: RoomID)
    case gameOver
    case pickedUp(ItemKind)
    case swapped(dropped: ItemKind, picked: ItemKind)
    /// Holding something and pressing the button with nothing underfoot.
    /// What an item does is not defined yet, so the object stays in hand.
    case used(ItemKind)
    case nothingToDo
}

/// The running game: one worm, one maze, items on the floor.
///
/// Everything here is a plain value type with no rendering dependencies, so the
/// rules stay testable and the scene stays a dumb view of this state.
public struct MazeWorld: Sendable {
    public private(set) var maze: Maze
    public private(set) var roomID: RoomID
    public private(set) var player: MazePlayer
    /// Items lying in each room, keyed by room. Rooms without entries are empty.
    public private(set) var items: [RoomID: [Item]]
    public private(set) var steps: Int
    public private(set) var lives: Int = 3
    public private(set) var isGameOver = false
    /// The other worms in the race. They are simulated everywhere, so a worm the
    /// player has left behind keeps crawling.
    public private(set) var rivals: [RivalWorm]
    /// Where the worm reappears after a death: the last spot it stood safely.
    /// Respawning at the top of the shaft it just fell down would only repeat
    /// the fall, so this follows solid ground instead of room entrances.
    private var respawnRoom: RoomID
    private var respawnPosition: Vec2
    private var nextTombstoneID = 100_000

    private let movement = MazeMovement()
    /// The state `restart()` returns to.
    private let startingItems: [RoomID: [Item]]
    private let startingRivals: [WormSpawn]
    private let startingPlayer: WormSpawn

    public init(maze: Maze, rivals: [WormSpawn] = []) {
        self.init(maze: maze, items: maze.initialItems, start: nil, rivals: rivals)
    }

    public init(maze: Maze, start: WormSpawn?, rivals: [WormSpawn]) {
        self.init(maze: maze, items: maze.initialItems, start: start, rivals: rivals)
    }

    /// Starts with a given set of floor objects, which is what the tests use.
    ///
    /// `start` overrides where the player's worm begins, which the app uses to
    /// put it on the worm the original screen draws for it.
    public init(
        maze: Maze,
        items: [RoomID: [Item]],
        start: WormSpawn? = nil,
        rivals: [WormSpawn] = []
    ) {
        self.maze = maze
        let origin = start ?? WormSpawn(room: maze.spawnRoom, position: maze.spawnPosition)
        self.startingPlayer = origin
        self.roomID = origin.room
        self.player = MazePlayer(position: origin.position)
        self.startingItems = items
        self.items = items
        self.startingRivals = rivals
        self.rivals = rivals.enumerated().map { RivalWorm(id: $0.offset, spawn: $0.element) }
        self.steps = 0
        self.respawnRoom = origin.room
        self.respawnPosition = origin.position
    }

    public var room: Room {
        guard let room = maze.rooms[roomID] else {
            preconditionFailure("current room \(roomID) is missing from the maze")
        }
        return room
    }

    public var itemsInRoom: [Item] { items[roomID] ?? [] }

    /// The rivals the player can see right now.
    public var rivalsInRoom: [RivalWorm] { rivals.filter { $0.room == roomID } }

    /// Advances the simulation and reports anything that happened.
    public mutating func update(deltaTime: Double, input: GameInput) -> [MazeEvent] {
        guard deltaTime > 0 else { return [] }
        var events: [MazeEvent] = []

        guard !isGameOver else { return [] }

        advanceRivals(deltaTime: deltaTime)

        let (step, exit, fellTooFar) = movement.move(
            player: player,
            input: input,
            room: room,
            exits: maze.exits(from: roomID),
            dt: min(deltaTime, 1.0 / 30.0)
        )
        player.position = step.position
        player.facing = step.facing
        player.fallSpeed = step.fallSpeed
        player.fallDistance = step.fallDistance

        if fellTooFar {
            die(.fall, events: &events)
            return events
        }

        if let exit {
            enter(exit, events: &events)
        }

        if !room.hasGravity || player.isOnGround {
            respawnRoom = roomID
            respawnPosition = player.position
        }
        steps += 1
        return events
    }

    /// Steps every rival, whether or not the player is in the room to see it.
    private mutating func advanceRivals(deltaTime: Double) {
        for index in rivals.indices {
            let current = rivals[index].room
            guard let room = maze.rooms[current] else { continue }
            let exit = rivals[index].advance(
                deltaTime: deltaTime,
                room: room,
                exits: maze.exits(from: current),
                movement: movement
            )
            guard let exit, let destination = maze.rooms[exit.destination] else { continue }
            let landing = movement.arrivalPosition(
                for: exit.arrival,
                room: destination,
                player: rivals[index].body
            )
            rivals[index].enter(exit.destination, at: landing, hasGravity: destination.hasGravity)
        }
    }

    /// Leaves a tombstone where the worm died and spends a life.
    private mutating func die(_ cause: DeathCause, events: inout [MazeEvent]) {
        items[roomID, default: []].append(
            Item(id: nextTombstoneID, kind: .tombstone, position: player.position)
        )
        nextTombstoneID += 1

        lives -= 1
        events.append(.died(cause))

        guard lives > 0 else {
            isGameOver = true
            events.append(.gameOver)
            return
        }

        roomID = respawnRoom
        player.position = respawnPosition
        player.fallSpeed = 0
        player.fallDistance = 0
        events.append(.respawned(room: respawnRoom))
    }

    private mutating func enter(_ exit: RoomExit, events: inout [MazeEvent]) {
        guard let destination = maze.rooms[exit.destination] else { return }
        roomID = exit.destination
        player.position = movement.arrivalPosition(for: exit.arrival, room: destination, player: player)
        // Falling into the room below keeps the momentum and the tally, so a
        // shaft that spans rooms keeps counting towards the fatal distance.
        if !destination.hasGravity {
            player.fallSpeed = 0
            player.fallDistance = 0
        }
        events.append(.enteredRoom(exit.destination))
    }

    /// The single action button: pick up when empty handed, otherwise swap, and
    /// if there is nothing to swap, try to use what is held.
    @discardableResult
    public mutating func interact() -> MazeEvent {
        let nearest =
            itemsInRoom
            .filter(\.kind.isCarryable)
            .map { ($0, $0.position.distance(to: player.position)) }
            .filter { $0.1 <= player.reach + $0.0.kind.reachBonus }
            .min { $0.1 < $1.1 }

        guard let (target, _) = nearest else {
            if let carried = player.carried {
                return .used(carried.kind)  // no effect yet
            }
            return .nothingToDo
        }

        items[roomID]?.removeAll { $0.id == target.id }

        if let carried = player.carried {
            var dropped = carried
            dropped.position = target.position
            items[roomID, default: []].append(dropped)
            player.carried = target
            return .swapped(dropped: carried.kind, picked: target.kind)
        }

        player.carried = target
        return .pickedUp(target.kind)
    }

    /// Drops the worm into a room without walking there. Used by the debug
    /// launch flag and useful for checking a room in isolation.
    public mutating func teleport(to room: RoomID, at position: Vec2? = nil) {
        guard let destination = maze.rooms[room] else { return }
        roomID = room
        var landing = position
        if landing == nil {
            // Centre of the room, or the first walkable cell on that row.
            let middle = GridPoint(x: destination.columns / 2, y: destination.rows / 2)
            if destination.isPassable(x: middle.x, y: middle.y) {
                landing = Vec2(x: Double(middle.x) + 0.5, y: Double(middle.y) + 0.5)
            } else {
                for row in 0..<destination.rows {
                    if let column = (0..<destination.columns).first(where: { destination.isPassable(x: $0, y: row) }) {
                        landing = Vec2(x: Double(column) + 0.5, y: Double(row) + 0.5)
                        break
                    }
                }
            }
        }
        player.position = landing ?? maze.spawnPosition
        player.fallSpeed = 0
        player.fallDistance = 0
        respawnRoom = room
        respawnPosition = player.position
    }

    /// Puts the maze back to its opening state.
    public mutating func restart() {
        roomID = startingPlayer.room
        player = MazePlayer(position: startingPlayer.position)
        items = startingItems
        rivals = startingRivals.enumerated().map { RivalWorm(id: $0.offset, spawn: $0.element) }
        steps = 0
        lives = 3
        isGameOver = false
        respawnRoom = startingPlayer.room
        respawnPosition = startingPlayer.position
    }
}

extension ItemKind {
    /// Tombstones mark where a worm died; they are scenery, not luggage.
    public var isCarryable: Bool { self != .tombstone }

    /// Larger objects are easier to reach than small ones.
    var reachBonus: Double {
        switch self {
        case .tombstone: 0.35
        case .key: 0.15
        case .mug, .bottle, .skull: 0.2
        }
    }
}
