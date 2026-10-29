import Foundation
import Observation
import SpriteKit
import WrigglerCore

/// Owns the running game: the maze simulation, the SpriteKit scene and the clock.
///
/// The scene only draws; this class advances `MazeWorld` and publishes the small
/// amount of state the HUD needs, so the SwiftUI layer does not re-render per frame.
@MainActor
@Observable
final class GameSession {
    let scene: GameScene
    let input = InputController()

    private(set) var roomID: RoomID
    private(set) var carried: ItemKind?
    private(set) var isPaused = false
    private(set) var notice: String?
    private(set) var roomsExplored = 1

    private let demo: Bool
    private var demoClock: Double = 0
    private var demoActionFired = false
    private var world: MazeWorld
    private var visited: Set<RoomID>
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var noticeFrames = 0

    init(maze: Maze, sceneSize: CGSize, demo: Bool = false) {
        self.demo = demo
        self.world = MazeWorld(maze: maze)
        self.roomID = maze.spawnRoom
        self.visited = [maze.spawnRoom]
        self.scene = GameScene(size: sceneSize)
        scene.prepare(room: world.room, viewport: sceneSize)
        scene.render(world: world, viewport: sceneSize)
    }

    var roomLabel: String { "ROOM \(roomID)" }

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

    func togglePause() { setPaused(!isPaused) }

    /// Re-lays out the scene after a size change, keeping the run intact.
    func restart(viewport: CGSize) {
        scene.prepare(room: world.room, viewport: viewport)
        scene.render(world: world, viewport: viewport)
    }

    func restart() {
        demoClock = 0
        demoActionFired = false
        world.restart()
        visited = [world.roomID]
        roomsExplored = 1
        roomID = world.roomID
        carried = nil
        notice = nil
        isPaused = false
        lastTimestamp = 0
        input.releaseAll()
        scene.prepare(room: world.room, viewport: scene.size)
        scene.render(world: world, viewport: scene.size)
    }

    // MARK: - Action button

    /// Pick up when empty handed, swap when standing over another object, and
    /// otherwise use what is held. What an object does is not defined yet.
    func act() {
        guard !isPaused else { return }
        switch world.interact() {
        case .pickedUp(let kind):
            show("PICKED UP \(kind.rawValue.uppercased())")
        case .swapped(let dropped, let picked):
            show("DROPPED \(dropped.rawValue.uppercased()) · TOOK \(picked.rawValue.uppercased())")
        case .used(let kind):
            show("USED \(kind.rawValue.uppercased())")
        case .nothingToDo, .enteredRoom:
            break
        }
        carried = world.player.carried?.kind
    }

    // MARK: - Frame loop

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let delta = lastTimestamp == 0 ? 0 : now - lastTimestamp
        lastTimestamp = now
        guard !isPaused else { return }

        var snapshot = input.snapshot()
        snapshot.consumeEdges()
        var wantsAction = snapshot.actionPressed
        if demo {
            demoClock += delta
            snapshot = Self.demoInput(at: demoClock)
            if !demoActionFired, demoClock >= 1.60 {
                demoActionFired = true
                snapshot.actionPressed = true
            }
            wantsAction = snapshot.actionPressed
        }

        handle(world.update(deltaTime: delta, input: snapshot))
        if wantsAction {
            act()
        }

        scene.render(world: world, viewport: scene.size)

        if noticeFrames > 0 {
            noticeFrames -= 1
            if noticeFrames == 0 { notice = nil }
        }
    }

    private func handle(_ events: [MazeEvent]) {
        for event in events {
            switch event {
            case .enteredRoom(let room):
                roomID = room
                if visited.insert(room).inserted {
                    roomsExplored = visited.count
                }
            case .pickedUp(let kind):
                show("PICKED UP \(kind.rawValue.uppercased())")
            case .swapped(let dropped, let picked):
                show("DROPPED \(dropped.rawValue.uppercased()) · TOOK \(picked.rawValue.uppercased())")
            case .used, .nothingToDo:
                break
            }
        }
        carried = world.player.carried?.kind
    }

    /// A fixed walk used to prove the build moves and changes rooms: up to the
    /// doorway, then right through it. Enabled with the `-demo` launch flag.
    private static func demoInput(at time: Double) -> GameInput {
        // Spawn is (9.5, 10.5), the key lies at (12.4, 4.0), the doorway is
        // centred on y = 7.88. The worm fetches the key, steps back down to the
        // doorway and walks out, which exercises pickup and room changes.
        switch time {
        case ..<1.05: GameInput(moveY: -1)
        case ..<1.60: GameInput(moveX: 1)
        case ..<2.30: GameInput(moveY: 1)
        case ..<9.0: GameInput(moveX: 1)
        default: GameInput.none
        }
    }

    private func show(_ text: String) {
        notice = text
        noticeFrames = 90
    }
}
