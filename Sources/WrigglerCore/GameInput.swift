import Foundation

/// Abstract input snapshot consumed by the simulation.
///
/// Touch controls, a hardware keyboard and a game controller all funnel into this
/// single value, so gameplay code never has to know where the input came from.
public struct GameInput: Sendable, Equatable {
    /// Horizontal intent, `-1` (left) ... `1` (right).
    public var moveX: Double
    /// Vertical intent, `-1` (up) ... `1` (down).
    public var moveY: Double
    /// True on the frame the action button went down: pick up, swap or use.
    public var actionPressed: Bool

    public init(moveX: Double = 0, moveY: Double = 0, actionPressed: Bool = false) {
        self.moveX = moveX
        self.moveY = moveY
        self.actionPressed = actionPressed
    }

    public static let none = GameInput()

    /// Clears edge-triggered fields so a value is only acted on once.
    public mutating func consumeEdges() {
        actionPressed = false
    }
}
