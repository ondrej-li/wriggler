import SpriteKit
import WrigglerCore

/// Draws a `World`: the static maze once, and the moving actors every frame.
///
/// All coordinates are converted from world units (y down, top-left origin) into the
/// scene's y-up space here, so the simulation never has to care about SpriteKit.
@MainActor
final class WorldRenderer {
    private let tileLayer = SKNode()
    private let actorLayer = SKNode()

    private var playerSprite: SKSpriteNode?
    private var enemySprites: [SKSpriteNode] = []
    private var currentPlayerTexture: String?

    private let tilePixels = GameScene.tilePixels
    private let actorSize: CGSize

    init(actorSize: CGSize = CGSize(width: 16, height: 16)) {
        self.actorSize = actorSize
        tileLayer.zPosition = 0
        actorLayer.zPosition = 10
    }

    func attach(to parent: SKNode, world: World) {
        tileLayer.removeFromParent()
        actorLayer.removeFromParent()
        tileLayer.removeAllChildren()
        actorLayer.removeAllChildren()

        parent.addChild(tileLayer)
        parent.addChild(actorLayer)
        buildTiles(from: world.map)
        buildActors(for: world)
    }

    func detach() {
        tileLayer.removeFromParent()
        actorLayer.removeFromParent()
        playerSprite = nil
        enemySprites.removeAll()
        currentPlayerTexture = nil
    }

    func sync(world: World, time: Double) {
        syncPlayer(world: world, time: time)
        syncEnemies(world: world)
    }

    // MARK: - Static maze

    private func buildTiles(from map: TileMap) {
        tileLayer.removeAllChildren()

        for row in 0..<map.height {
            for column in 0..<map.width {
                let tile = map.tile(x: column, y: row)
                guard let appearance = TileAppearance.appearance(for: tile) else { continue }

                let size = CGSize(width: tilePixels, height: tilePixels)
                let node =
                    PixelArt.sprite(named: appearance.textureName, size: size)
                    ?? SKSpriteNode(color: appearance.color, size: size)
                node.position = centerOfTile(column: column, row: row)
                tileLayer.addChild(node)
            }
        }
    }

    // MARK: - Actors

    private func buildActors(for world: World) {
        playerSprite =
            PixelArt.sprite(named: SpriteName.playerIdle, size: actorSize)
            ?? SKSpriteNode(color: ZXPalette.brightGreen, size: actorSize)
        playerSprite?.zPosition = 2
        playerSprite.map(actorLayer.addChild)

        enemySprites = world.enemies.map { _ in
            let sprite =
                PixelArt.sprite(named: SpriteName.enemyCrawler, size: actorSize)
                ?? SKSpriteNode(color: ZXPalette.brightMagenta, size: actorSize)
            sprite.zPosition = 1
            actorLayer.addChild(sprite)
            return sprite
        }
    }

    private func syncPlayer(world: World, time: Double) {
        guard let sprite = playerSprite else { return }
        let player = world.player

        sprite.position = scenePoint(for: player.body.center)
        sprite.isHidden = !player.isAlive
        sprite.xScale = player.facing == .left ? -1 : 1

        let textureName = Self.textureName(for: player.state, time: time)
        if textureName != currentPlayerTexture, PixelArt.texture(named: textureName) != nil {
            sprite.texture = PixelArt.texture(named: textureName)
            sprite.size = actorSize
            currentPlayerTexture = textureName
        }
    }

    private func syncEnemies(world: World) {
        for (index, enemy) in world.enemies.enumerated() where index < enemySprites.count {
            let sprite = enemySprites[index]
            sprite.isHidden = !enemy.isAlive
            sprite.position = scenePoint(for: enemy.body.center)
            sprite.xScale = enemy.direction < 0 ? -1 : 1
        }
    }

    // MARK: - Helpers

    private func centerOfTile(column: Int, row: Int) -> CGPoint {
        CGPoint(
            x: (CGFloat(column) + 0.5) * tilePixels,
            y: -(CGFloat(row) + 0.5) * tilePixels
        )
    }

    /// Snaps to whole virtual pixels so upscaling stays pixel-perfect.
    private func scenePoint(for worldPoint: Vec2) -> CGPoint {
        CGPoint(
            x: (worldPoint.x * tilePixels).rounded(),
            y: -(worldPoint.y * tilePixels).rounded()
        )
    }

    private static func textureName(for state: PlayerState, time: Double) -> String {
        switch state {
        case .running:
            let frame = Int(time / 0.12) % 2
            return frame == 0 ? SpriteName.playerWalkA : SpriteName.playerWalkB
        case .jumping, .falling:
            return SpriteName.playerJump
        case .idle, .climbing, .dead:
            return SpriteName.playerIdle
        }
    }
}
