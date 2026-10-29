import Foundation
import SwiftUI
import WrigglerCore

/// Collects input from every source (touch, hardware keyboard, controller) into a
/// single press-state model, and hands the simulation an edge-triggered snapshot.
@MainActor
final class InputController {
    enum Button {
        case left
        case right
        case up
        case down
        case action
    }

    private var pressed: Set<Button> = []
    private var actionEdge = false

    var moveX: Double {
        (pressed.contains(.right) ? 1 : 0) - (pressed.contains(.left) ? 1 : 0)
    }

    var moveY: Double {
        (pressed.contains(.down) ? 1 : 0) - (pressed.contains(.up) ? 1 : 0)
    }

    func set(_ button: Button, pressed isPressed: Bool) {
        if isPressed {
            if button == .action, !pressed.contains(.action) { actionEdge = true }
            pressed.insert(button)
        } else {
            pressed.remove(button)
        }
    }

    /// Trigger the action button once, for on-screen buttons that fire on tap.
    func pressAction() {
        actionEdge = true
    }

    /// Returns the input for the current frame and clears one-shot edges.
    func snapshot() -> GameInput {
        defer { actionEdge = false }
        return GameInput(moveX: moveX, moveY: moveY, actionPressed: actionEdge)
    }

    func releaseAll() {
        pressed.removeAll()
        actionEdge = false
    }
}

extension InputController.Button {
    init?(key: KeyEquivalent) {
        switch key {
        case .leftArrow, "a", "A": self = .left
        case .rightArrow, "d", "D": self = .right
        case .upArrow, "w", "W": self = .up
        case .downArrow, "s", "S": self = .down
        case .space, "e", "E", "z", "Z": self = .action
        default: return nil
        }
    }
}
