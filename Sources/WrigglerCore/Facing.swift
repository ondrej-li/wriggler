import Foundation

public enum Facing: Sendable, Equatable {
    case left
    case right

    public var sign: Double { self == .left ? -1 : 1 }
}
