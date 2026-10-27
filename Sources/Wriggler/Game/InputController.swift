import Foundation
import SwiftUI
import WrigglerCore

/// Collects input from every source (touch, hardware keyboard, game controller) into a
/// single press-state model and hands the simulation an edge-triggered snapshot per frame.
@MainActor
final class InputController {
    enum Button {
        case left
        case right
        case up
        case down
        case jump
    }

    private var pressed: Set<Button> = []
    private var jumpEdge = false

    var moveX: Double {
        (pressed.contains(.right) ? 1 : 0) - (pressed.contains(.left) ? 1 : 0)
    }

    var moveY: Double {
        (pressed.contains(.down) ? 1 : 0) - (pressed.contains(.up) ? 1 : 0)
    }

    var isJumpHeld: Bool { pressed.contains(.jump) }

    func set(_ button: Button, pressed isPressed: Bool) {
        if isPressed {
            if button == .jump, !pressed.contains(.jump) { jumpEdge = true }
            pressed.insert(button)
        } else {
            pressed.remove(button)
        }
    }

    /// Returns the input for the current frame and clears one-shot edges.
    func snapshot() -> GameInput {
        defer { jumpEdge = false }
        return GameInput(
            moveX: moveX,
            moveY: moveY,
            jumpPressed: jumpEdge,
            jumpHeld: isJumpHeld
        )
    }

    func releaseAll() {
        pressed.removeAll()
        jumpEdge = false
    }
}

extension InputController.Button {
    init?(key: KeyEquivalent) {
        switch key {
        case .leftArrow, "a", "A": self = .left
        case .rightArrow, "d", "D": self = .right
        case .upArrow, "w", "W": self = .up
        case .downArrow, "s", "S": self = .down
        case .space, "z", "Z", "k", "K": self = .jump
        default: return nil
        }
    }
}
