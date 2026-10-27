import Foundation

/// Abstract input snapshot consumed by the simulation.
///
/// Touch controls, a hardware keyboard and a game controller all funnel into this
/// single value, so gameplay code never has to know where the input came from.
public struct GameInput: Sendable, Equatable {
    /// Horizontal intent, `-1` (left) ... `1` (right).
    public var moveX: Double
    /// Vertical intent, `-1` (up) ... `1` (down). Only used on ladders.
    public var moveY: Double
    /// True on the frame the jump control went down.
    public var jumpPressed: Bool
    /// True while the jump control is held (drives variable jump height).
    public var jumpHeld: Bool

    public init(moveX: Double = 0, moveY: Double = 0, jumpPressed: Bool = false, jumpHeld: Bool = false) {
        self.moveX = moveX
        self.moveY = moveY
        self.jumpPressed = jumpPressed
        self.jumpHeld = jumpHeld
    }

    public static let none = GameInput()

    /// Clears edge-triggered fields so a fixed-step loop consumes them only once.
    public mutating func consumeEdges() {
        jumpPressed = false
    }
}
