import Foundation

/// A point/vector in world units. One world unit is exactly one tile.
public struct Vec2: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2()

    public var length: Double { (x * x + y * y).squareRoot() }

    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }

    public func distance(to other: Vec2) -> Double { (self - other).length }

    public static prefix func - (v: Vec2) -> Vec2 { Vec2(x: -v.x, y: -v.y) }
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x - b.x, y: a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(x: a.x * s, y: a.y * s) }
    public static func * (s: Double, a: Vec2) -> Vec2 { Vec2(x: a.x * s, y: a.y * s) }
    public static func / (a: Vec2, s: Double) -> Vec2 { Vec2(x: a.x / s, y: a.y / s) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public static func -= (a: inout Vec2, b: Vec2) { a = a - b }
    public static func *= (a: inout Vec2, s: Double) { a = a * s }
}

/// Integer tile coordinate.
public struct GridPoint: Hashable, Sendable, Codable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Axis-aligned bounding box. Origin is the top-left corner, y grows downwards.
public struct AABB: Hashable, Sendable {
    public var origin: Vec2
    public var size: Vec2

    public init(origin: Vec2, size: Vec2) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: Vec2(x: x, y: y), size: Vec2(x: width, y: height))
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.x }
    public var maxY: Double { origin.y + size.y }
    public var center: Vec2 { Vec2(x: origin.x + size.x / 2, y: origin.y + size.y / 2) }

    public func intersects(_ other: AABB) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }

    public func contains(_ point: Vec2) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func insetBy(dx: Double, dy: Double) -> AABB {
        AABB(
            x: origin.x + dx,
            y: origin.y + dy,
            width: max(0, size.x - 2 * dx),
            height: max(0, size.y - 2 * dy)
        )
    }

    public func translated(by delta: Vec2) -> AABB {
        AABB(origin: origin + delta, size: size)
    }
}

/// Moves `value` towards `target` by at most `maxDelta`.
@inlinable
public func moveTowards(_ value: Double, _ target: Double, _ maxDelta: Double) -> Double {
    let delta = target - value
    if abs(delta) <= maxDelta { return target }
    return value + (delta < 0 ? -maxDelta : maxDelta)
}
