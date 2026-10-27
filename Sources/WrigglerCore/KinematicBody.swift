import Foundation

/// A tile-colliding body driven by velocity (no rotational physics).
///
/// `position` is the top-left corner and `size` is the full extent, both in world units.
/// The y axis points downwards, matching the tile grid.
public struct KinematicBody: Sendable, Equatable {
    public var position: Vec2
    public var velocity: Vec2
    public var size: Vec2
    public var isOnGround: Bool
    public var isClimbing: Bool

    public init(position: Vec2, size: Vec2, velocity: Vec2 = .zero) {
        self.position = position
        self.velocity = velocity
        self.size = size
        self.isOnGround = false
        self.isClimbing = false
    }

    public var bounds: AABB { AABB(origin: position, size: size) }
    public var center: Vec2 { bounds.center }

    /// The bottom edge of the body.
    public var feet: Double { position.y + size.y }
}

/// Bit set returned by `TileCollision.move`.
public struct MoveResult: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let blockedHorizontally = MoveResult(rawValue: 1 << 0)
    public static let blockedVertically = MoveResult(rawValue: 1 << 1)
    public static let landed = MoveResult(rawValue: 1 << 2)
    public static let hitCeiling = MoveResult(rawValue: 1 << 3)
}

/// Swept, axis-separated collision against a `TileMap`.
///
/// Movement is resolved one axis at a time (X first, then Y), which is the standard
/// approach for tile platformers: it makes wall sliding and corner handling predictable.
public struct TileCollision: Sendable {
    private static let skin = 1e-4

    public var map: TileMap

    public init(map: TileMap) {
        self.map = map
    }

    /// Moves `body` by `delta`, stopping at blocking tiles, and updates `isOnGround`.
    @discardableResult
    public func move(_ body: inout KinematicBody, by delta: Vec2) -> MoveResult {
        var result: MoveResult = []

        if delta.x != 0 {
            if resolveHorizontal(&body, dx: delta.x) {
                result.insert(.blockedHorizontally)
            }
        }

        if delta.y != 0 {
            let vertical = resolveVertical(&body, dy: delta.y)
            if vertical.hitCeiling { result.insert(.hitCeiling) }
            if vertical.landed { result.insert(.landed) }
            if vertical.hitCeiling || vertical.landed { result.insert(.blockedVertically) }
        }

        body.isOnGround = isStanding(body)
        return result
    }

    /// True when something is immediately under the body's feet.
    public func isStanding(_ body: KinematicBody) -> Bool {
        let probe = AABB(
            x: body.position.x + Self.skin,
            y: body.feet,
            width: max(Self.skin, body.size.x - 2 * Self.skin),
            height: Self.skin * 4
        )
        let cells = map.cells(overlapping: probe)
        for y in cells.rows {
            for x in cells.columns {
                let tile = map.tile(x: x, y: y)
                if tile.blocksMovement { return true }
                if tile.isOneWay, abs(Double(y) - body.feet) < 0.05 { return true }
            }
        }
        // Resting on the implicit floor below the last row.
        return body.feet >= Double(map.height) - Self.skin
    }

    /// True when the body overlaps a ladder, used to start climbing.
    public func isTouchingLadder(_ body: KinematicBody) -> Bool {
        let centre = AABB(
            x: body.position.x + body.size.x / 2,
            y: body.position.y + body.size.y / 2,
            width: 1e-3,
            height: 1e-3
        )
        if map.rect(centre, overlaps: .ladder) { return true }
        let feet = AABB(
            x: body.position.x + body.size.x / 2,
            y: body.feet - 0.1,
            width: 1e-3,
            height: 1e-3
        )
        return map.rect(feet, overlaps: .ladder)
    }

    /// True when the body overlaps a tile of the given kind.
    public func isTouching(_ body: KinematicBody, tile: Tile) -> Bool {
        map.rect(body.bounds, overlaps: tile)
    }

    /// True when there is a wall directly in front of the body.
    public func isWallAhead(_ body: KinematicBody, direction: Double) -> Bool {
        guard direction != 0 else { return false }
        let probeWidth = 0.2
        let x = direction > 0 ? body.position.x + body.size.x : body.position.x - probeWidth
        let probe = AABB(
            x: x,
            y: body.position.y + 0.1,
            width: probeWidth,
            height: max(0.1, body.size.y - 0.2)
        )
        return map.rect(probe, overlaps: .solid)
    }

    /// True when there is floor directly in front of the body's feet.
    public func hasFloorAhead(_ body: KinematicBody, direction: Double) -> Bool {
        guard direction != 0 else { return true }
        let x = direction > 0 ? body.position.x + body.size.x : body.position.x - 0.2
        let probe = AABB(x: x, y: body.feet, width: 0.2, height: 0.2)
        let cells = map.cells(overlapping: probe)
        for y in cells.rows {
            for x in cells.columns where map.tile(x: x, y: y).blocksFall(fromAbove: true) {
                return true
            }
        }
        return false
    }

    // MARK: - Resolution

    private func resolveHorizontal(_ body: inout KinematicBody, dx: Double) -> Bool {
        let target = body.position.x + dx
        let rect = AABB(x: target, y: body.position.y, width: body.size.x, height: body.size.y)
        let cells = map.cells(overlapping: rect)

        var limit: Double?
        for y in cells.rows {
            for x in cells.columns where map.tile(x: x, y: y).blocksMovement {
                if dx > 0 {
                    limit = min(limit ?? .infinity, Double(x) - body.size.x)
                } else {
                    limit = max(limit ?? -.infinity, Double(x + 1))
                }
            }
        }

        // The level edges behave like walls even though they are not stored as tiles.
        if dx > 0, target + body.size.x > Double(map.width) {
            limit = min(limit ?? .infinity, Double(map.width) - body.size.x)
        } else if dx < 0, target < 0 {
            limit = max(limit ?? -.infinity, 0)
        }

        if let limit, dx > 0 ? target > limit : target < limit {
            body.position.x = limit
            body.velocity.x = 0
            return true
        }

        body.position.x = target
        return false
    }

    private func resolveVertical(_ body: inout KinematicBody, dy: Double) -> (landed: Bool, hitCeiling: Bool) {
        let target = body.position.y + dy
        let rect = AABB(x: body.position.x, y: target, width: body.size.x, height: body.size.y)
        let cells = map.cells(overlapping: rect)
        let previousFeet = body.feet

        var landed = false
        var hitCeiling = false

        if dy > 0 {
            var limit = Double.infinity
            for y in cells.rows {
                for x in cells.columns {
                    let tile = map.tile(x: x, y: y)
                    guard tile.blocksFall(fromAbove: true) else { continue }
                    // One-way tiles only support bodies that were above them last frame.
                    if tile.isOneWay, previousFeet > Double(y) + Self.skin { continue }
                    limit = min(limit, Double(y) - body.size.y)
                    landed = true
                }
            }
            if target + body.size.y > Double(map.height) {
                limit = min(limit, Double(map.height) - body.size.y)
                landed = true
            }
            if landed, target > limit {
                body.position.y = limit
                body.velocity.y = 0
                return (true, false)
            }
        } else {
            var limit = -Double.infinity
            for y in cells.rows {
                for x in cells.columns where map.tile(x: x, y: y).blocksMovement {
                    limit = max(limit, Double(y + 1))
                    hitCeiling = true
                }
            }
            if target < 0 {
                limit = max(limit, 0)
                hitCeiling = true
            }
            if hitCeiling, target < limit {
                body.position.y = limit
                body.velocity.y = 0
                return (false, true)
            }
        }

        body.position.y = target
        return (landed, hitCeiling)
    }
}
