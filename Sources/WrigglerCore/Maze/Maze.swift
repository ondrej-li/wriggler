import Foundation

/// A doorway out of a room, and where it leads.
public struct RoomExit: Sendable, Equatable {
    public let doorway: Doorway
    /// The room on the other side.
    public let destination: RoomID
    /// The doorway you arrive through, which is on the destination's edge.
    public let arrival: Doorway

    public init(doorway: Doorway, destination: RoomID, arrival: Doorway) {
        self.doorway = doorway
        self.destination = destination
        self.arrival = arrival
    }
}

/// The whole maze: every room, the doorways between them, and the starting point.
public struct Maze: Sendable {
    public let rooms: [RoomID: Room]
    public let exits: [RoomID: [RoomExit]]
    public let spawnRoom: RoomID
    public let spawnPosition: Vec2
    public let initialItems: [RoomID: [Item]]
    public let columns: Int
    public let rows: Int

    public var roomCount: Int { rooms.count }

    public func room(_ id: RoomID) -> Room? { rooms[id] }

    public func exits(from id: RoomID) -> [RoomExit] { exits[id] ?? [] }

    /// Builds a maze from the JSON description.
    public init(definition: MazeDefinition) throws {
        let columns = definition.room.columns
        let rows = definition.room.rows
        self.columns = columns
        self.rows = rows

        var rooms: [RoomID: Room] = [:]
        var items: [RoomID: [Item]] = [:]
        var nextItemID = 0

        for (key, value) in definition.rooms {
            guard let id = RoomID(key) else {
                throw MazeDefinitionError.unreadable("bad room key \(key)")
            }
            guard value.rows.count == rows else {
                throw MazeDefinitionError.unreadable("room \(key) has \(value.rows.count) rows, expected \(rows)")
            }

            var kinds: [TileKind] = []
            kinds.reserveCapacity(columns * rows)
            for line in value.rows {
                guard line.count == columns else {
                    throw MazeDefinitionError.unreadable("room \(key) row has \(line.count) cells, expected \(columns)")
                }
                for character in line {
                    guard let name = definition.tiles[String(character)],
                        let kind = TileKind(rawValue: name)
                    else {
                        throw MazeDefinitionError.unreadable("room \(key) uses unknown tile \(character)")
                    }
                    kinds.append(kind)
                }
            }

            rooms[id] = Room(
                id: id.point,
                columns: columns,
                rows: rows,
                floor: value.floor ?? "green",
                region: value.region.flatMap(Region.init(rawValue:)) ?? .surface,
                kinds: kinds
            )

            if let placed = value.items {
                items[id] = placed.compactMap { item in
                    guard let kind = ItemKind(rawValue: item.kind) else { return nil }
                    defer { nextItemID += 1 }
                    return Item(id: nextItemID, kind: kind, position: Vec2(x: item.x, y: item.y))
                }
            }
        }

        var exits: [RoomID: [RoomExit]] = [:]
        for (key, link) in definition.links {
            guard let exitID = ExitID(text: key),
                let destination = ExitID(text: link.to),
                let side = Side(rawValue: link.side),
                // The reverse link carries the destination's own doorway geometry.
                let back = definition.links[link.to],
                let backSide = Side(rawValue: back.side)
            else { continue }

            exits[exitID.room, default: []].append(
                RoomExit(
                    doorway: Doorway(side: side, at: link.at, width: link.width),
                    destination: destination.room,
                    arrival: Doorway(side: backSide, at: back.at, width: back.width)
                )
            )
        }

        guard let spawnRoom = RoomID(definition.spawn.room), rooms[spawnRoom] != nil else {
            throw MazeDefinitionError.unreadable("spawn room \(definition.spawn.room) does not exist")
        }

        self.rooms = rooms
        self.exits = exits
        self.spawnRoom = spawnRoom
        self.spawnPosition = Vec2(x: definition.spawn.x, y: definition.spawn.y)
        self.initialItems = items
    }
}
