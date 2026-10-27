import SpriteKit
import WrigglerCore

/// Renders a `World` with pixel-perfect scaling, and owns the scroll camera.
///
/// The scene is deliberately dumb: it never mutates the simulation, it only draws the
/// snapshot it is handed. `GameSession` drives the fixed-step loop.
final class GameScene: SKScene {
    /// One tile is one Spectrum character cell: 8×8 pixels.
    static let tilePixels: CGFloat = 8
    /// The Spectrum's 256×192 screen, used as the pixel-perfect reference resolution.
    static let referenceSize = CGSize(width: 256, height: 192)

    private let worldNode = SKNode()
    private var renderer: WorldRenderer?
    private var pixelScale: CGFloat = 1

    override init(size: CGSize = GameScene.referenceSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = ZXPalette.black
        addChild(worldNode)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func prepare(with world: World) {
        renderer?.detach()
        let renderer = WorldRenderer()
        renderer.attach(to: worldNode, world: world)
        self.renderer = renderer

        updatePixelScale()
        updateCamera(for: world)
    }

    func render(world: World) {
        guard let renderer else { return }
        updatePixelScale()
        renderer.sync(world: world, time: world.elapsed)
        updateCamera(for: world)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updatePixelScale()
    }

    // MARK: - Scaling

    /// Largest integer factor that fits the 256×192 reference screen, so every virtual
    /// pixel covers a whole number of device pixels.
    private func updatePixelScale() {
        guard size.width > 1, size.height > 1 else { return }
        let fit = min(size.width / Self.referenceSize.width, size.height / Self.referenceSize.height)
        pixelScale = max(1, fit.rounded(.down))
        worldNode.setScale(pixelScale)
    }

    // MARK: - Camera

    private func updateCamera(for world: World) {
        let scale = Self.tilePixels * pixelScale
        let viewport = Vec2(
            x: Double(size.width / (Self.tilePixels * pixelScale)),
            y: Double(size.height / (Self.tilePixels * pixelScale))
        )
        let level = Vec2(x: Double(world.map.width), y: Double(world.map.height))

        let focus = Vec2(
            x: clamp(world.player.body.center.x, viewport: viewport.x, level: level.x),
            y: clamp(world.player.body.center.y, viewport: viewport.y, level: level.y)
        )

        worldNode.position = CGPoint(
            x: (size.width / 2 - CGFloat(focus.x) * scale).rounded(),
            y: (size.height / 2 + CGFloat(focus.y) * scale).rounded()
        )
    }

    private func clamp(_ value: Double, viewport: Double, level: Double) -> Double {
        guard level > viewport else { return level / 2 }
        let half = viewport / 2
        return min(max(value, half), level - half)
    }
}
