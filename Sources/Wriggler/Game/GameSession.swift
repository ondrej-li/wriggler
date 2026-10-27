import Foundation
import Observation
import QuartzCore
import SpriteKit
import WrigglerCore

/// Owns the running game: the simulation, the SpriteKit scene and the display link.
///
/// The scene only draws; this class advances `World` on a fixed timestep and publishes a
/// small amount of state for the SwiftUI HUD (so the HUD does not re-render every frame).
@MainActor
@Observable
final class GameSession {
    let level: Level
    let scene: GameScene
    let input = InputController()

    private(set) var status: GameStatus = .playing
    private(set) var isPaused = false
    /// Elapsed play time in tenths of a second, published only when it changes.
    private(set) var elapsedTenths = 0

    private var world: World
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    init(level: Level) {
        self.level = level
        self.world = World(level: level)
        self.scene = GameScene()
        scene.prepare(with: world)
    }

    var elapsedSeconds: Double { Double(elapsedTenths) / 10 }

    var isRunning: Bool { displayLink != nil && !isPaused }

    // MARK: - Lifecycle

    func start() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
        input.releaseAll()
    }

    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        lastTimestamp = 0
        input.releaseAll()
    }

    func togglePause() {
        setPaused(!isPaused)
    }

    func restart() {
        world.restart()
        scene.prepare(with: world)
        status = .playing
        elapsedTenths = 0
        isPaused = false
        lastTimestamp = 0
        input.releaseAll()
    }

    // MARK: - Frame loop

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let delta = lastTimestamp == 0 ? 0 : now - lastTimestamp
        lastTimestamp = now

        guard !isPaused else { return }

        _ = world.advance(deltaTime: delta, input: input.snapshot())
        scene.render(world: world)

        if status != world.status { status = world.status }
        let tenths = Int((world.elapsed * 10).rounded(.down))
        if tenths != elapsedTenths { elapsedTenths = tenths }
    }
}
