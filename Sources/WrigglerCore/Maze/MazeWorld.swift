import Foundation

public enum MazeEvent: Sendable, Equatable {
    case enteredRoom(RoomID)
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

    private let movement = MazeMovement()
    /// The state `restart()` returns to.
    private let startingItems: [RoomID: [Item]]

    public init(maze: Maze) {
        self.init(maze: maze, items: maze.initialItems)
    }

    /// Starts with a given set of floor objects, which is what the tests use.
    public init(maze: Maze, items: [RoomID: [Item]]) {
        self.maze = maze
        self.roomID = maze.spawnRoom
        self.player = MazePlayer(position: maze.spawnPosition)
        self.startingItems = items
        self.items = items
        self.steps = 0
    }

    public var room: Room {
        guard let room = maze.rooms[roomID] else {
            preconditionFailure("current room \(roomID) is missing from the maze")
        }
        return room
    }

    public var itemsInRoom: [Item] { items[roomID] ?? [] }

    /// Advances the simulation and reports anything that happened.
    public mutating func update(deltaTime: Double, input: GameInput) -> [MazeEvent] {
        guard deltaTime > 0 else { return [] }
        var events: [MazeEvent] = []

        let (step, exit) = movement.move(
            player: player,
            input: input,
            room: room,
            exits: maze.exits(from: roomID),
            dt: min(deltaTime, 1.0 / 30.0)
        )
        player.position = step.position
        player.facing = step.facing

        if let exit {
            enter(exit, events: &events)
        }
        steps += 1
        return events
    }

    private mutating func enter(_ exit: RoomExit, events: inout [MazeEvent]) {
        guard let destination = maze.rooms[exit.destination] else { return }
        roomID = exit.destination
        player.position = movement.arrivalPosition(for: exit.arrival, room: destination, player: player)
        events.append(.enteredRoom(exit.destination))
    }

    /// The single action button: pick up when empty handed, otherwise swap, and
    /// if there is nothing to swap, try to use what is held.
    @discardableResult
    public mutating func interact() -> MazeEvent {
        let nearest =
            itemsInRoom
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

    /// Puts the level back to its opening state.
    public mutating func restart() {
        roomID = maze.spawnRoom
        player = MazePlayer(position: maze.spawnPosition)
        items = startingItems
        steps = 0
    }
}

extension ItemKind {
    /// Larger objects are easier to reach than small ones.
    var reachBonus: Double {
        switch self {
        case .tombstone: 0.35
        case .key: 0.15
        case .mug, .bottle, .skull: 0.2
        }
    }
}
