import SpriteKit
import WrigglerCore

/// Shows one room of the maze at an integer pixel scale.
///
/// The scene is deliberately dumb: it never mutates the simulation, it only draws
/// the snapshot it is handed. `GameSession` owns the clock.
final class GameScene: SKScene {
    /// One tile is one Spectrum character cell.
    static let tilePixels: CGFloat = 8

    private let worldNode = SKNode()
    private let renderer = RoomRenderer()
    private var pixelScale: CGFloat = 1

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = ZXPalette.black
        addChild(worldNode)
        renderer.attach(to: worldNode)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Sizes the scene to a whole room and centres it in the given viewport.
    func prepare(room: Room, viewport: CGSize) {
        layout(viewport: viewport, room: room)
    }

    func render(world: MazeWorld, viewport: CGSize, deltaTime: Double = 0) {
        layout(viewport: viewport, room: world.room)
        renderer.sync(world: world, deltaTime: deltaTime)
    }

    private func layout(viewport: CGSize, room: Room) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        if size != viewport {
            size = viewport
        }
        let roomWidth = CGFloat(room.columns) * Self.tilePixels
        let roomHeight = CGFloat(room.rows) * Self.tilePixels
        let fit = min(viewport.width / roomWidth, viewport.height / roomHeight)
        let scale = max(1, fit.rounded(.down))
        if scale != pixelScale {
            pixelScale = scale
            worldNode.setScale(scale)
        }
        // The room occupies [0, width] x [0, height] in the node's space, so
        // placing the node centres it in the viewport.
        worldNode.position = CGPoint(
            x: ((viewport.width - roomWidth * scale) / 2).rounded(),
            y: ((viewport.height - roomHeight * scale) / 2).rounded()
        )
    }
}
