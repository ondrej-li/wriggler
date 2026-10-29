import SpriteKit
import WrigglerCore

/// Draws the current room: the reconstructed artwork as one background node,
/// then whatever the room has pasted on top.
///
/// World units are tiles with the origin at the room's top-left corner and y
/// growing downwards, matching the maze data. Everything is converted to
/// SpriteKit's y-up space here, so the simulation never has to care.
@MainActor
final class RoomRenderer {
    private let roomNode = SKNode()
    private let actorNode = SKNode()
    private var renderedRoom: RoomID?
    private var background: SKSpriteNode?
    private var decoration: [SKSpriteNode] = []
    private var itemSprites: [Int: SKSpriteNode] = [:]
    private var worm: SKSpriteNode?

    private let cellPixels: CGFloat
    private let art = RoomArt.shared

    init(cellPixels: CGFloat = 8) {
        self.cellPixels = cellPixels
        roomNode.zPosition = 0
        actorNode.zPosition = 10
    }

    func attach(to parent: SKNode) {
        parent.addChild(roomNode)
        parent.addChild(actorNode)
        worm = SKSpriteNode(texture: PlayerArt.worm())
        worm?.size = CGSize(width: cellPixels * 3.75, height: cellPixels * 2.1)
        worm?.zPosition = 3
        worm.map(actorNode.addChild)
    }

    func sync(world: MazeWorld) {
        if renderedRoom != world.roomID {
            buildRoom(world.room)
            renderedRoom = world.roomID
        }
        syncItems(world)
        syncWorm(world)
    }

    // MARK: - Room

    private func buildRoom(_ room: Room) {
        roomNode.removeAllChildren()
        decoration.removeAll()
        itemSprites.removeAll()

        if let texture = art.backgroundTexture(for: room.id) {
            let node = SKSpriteNode(texture: texture)
            node.size = CGSize(
                width: CGFloat(art.columns) * cellPixels,
                height: CGFloat(art.rows) * cellPixels
            )
            node.anchorPoint = CGPoint.zero
            node.position = CGPoint(x: 0, y: 0)
            node.zPosition = 0
            roomNode.addChild(node)
            background = node
        } else {
            buildFallbackRoom(room)
        }

        addDecoration(room)
    }

    /// Painted only when the extracted artwork is unavailable, so the game still
    /// runs on a machine without it.
    private func buildFallbackRoom(_ room: Room) {
        background = nil
        let palette = FloorPalette.palette(named: room.floor)
        for row in 0..<room.rows {
            for column in 0..<room.columns {
                let kind = room.kind(x: column, y: row)
                let node = SKSpriteNode(texture: TileArt.texture(for: kind, floor: palette, row: row, column: column))
                node.size = CGSize(width: cellPixels, height: cellPixels)
                node.position = scenePoint(
                    Vec2(x: Double(column) + 0.5, y: Double(row) + 0.5),
                    roomHeight: room.rows
                )
                roomNode.addChild(node)
            }
        }
    }

    /// Creatures and props that the original room had drawn over its tiles.
    /// Enemies are skipped, which is what keeps the ants out.
    private func addDecoration(_ room: Room) {
        guard let layout = art.layout(for: room.id) else { return }
        for sprite in layout.sprites where art.category(of: sprite.shape) != .enemy {
            guard let texture = art.spriteTexture(sprite.shape) else { continue }
            let node = SKSpriteNode(texture: texture)
            node.size = CGSize(
                width: CGFloat(sprite.width) * cellPixels,
                height: CGFloat(sprite.height) * cellPixels
            )
            node.position = scenePoint(
                Vec2(x: sprite.x + sprite.width / 2, y: sprite.y + sprite.height / 2),
                roomHeight: room.rows
            )
            node.zPosition = 1
            roomNode.addChild(node)
            decoration.append(node)
        }
    }

    private func syncItems(_ world: MazeWorld) {
        let items = world.itemsInRoom
        let visible = Set(items.map(\.id))
        for (id, sprite) in itemSprites where !visible.contains(id) {
            sprite.removeFromParent()
            itemSprites.removeValue(forKey: id)
        }
        for item in items where itemSprites[item.id] == nil {
            let sprite = SKSpriteNode(texture: TileArt.item(item.kind))
            sprite.size = CGSize(width: cellPixels * 2, height: cellPixels * 2)
            sprite.position = scenePoint(item.position, roomHeight: world.room.rows)
            sprite.zPosition = 2
            actorNode.addChild(sprite)
            itemSprites[item.id] = sprite
        }
    }

    private func syncWorm(_ world: MazeWorld) {
        guard let worm else { return }
        worm.position = scenePoint(world.player.position, roomHeight: world.room.rows)
        let flip: CGFloat = world.player.facing == .left ? -1 : 1
        worm.xScale = abs(worm.xScale) * flip
    }

    /// Snaps to whole virtual pixels so the upscale stays crisp.
    private func scenePoint(_ world: Vec2, roomHeight: Int) -> CGPoint {
        CGPoint(
            x: (world.x * cellPixels).rounded(),
            y: (-world.y * cellPixels + CGFloat(roomHeight) * cellPixels).rounded()
        )
    }
}

/// The player's worm: same palette and scale as the originals, drawn rather than
/// cropped so it reads as "yours" against the room's decoration.
@MainActor
enum PlayerArt {
    private static var cached: SKTexture?

    static func worm() -> SKTexture {
        if let cached { return cached }
        let width = 30
        let height = 17
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let ctx = context.cgContext
            let body = SKColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
            let shade = SKColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1)

            // Four humps with gaps, like the worms on the original screens.
            let humps: [(CGFloat, CGFloat, CGFloat)] = [
                (21, 1, 11), (14, 2, 13), (7, 3, 12), (0, 6, 9),
            ]
            ctx.setFillColor(body.cgColor)
            for (x, y, h) in humps {
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: 9, height: h))
            }
            // A thin belly joining them, so it reads as one creature.
            ctx.fill(CGRect(x: 1, y: 12, width: 27, height: 3))

            ctx.setFillColor(shade.cgColor)
            for (x, y, h) in humps.dropLast() {
                ctx.fill(CGRect(x: x + 8, y: y + 2, width: 1, height: h - 4))
            }
            ctx.setFillColor(SKColor.black.cgColor)
            ctx.fill(CGRect(x: 25, y: 5, width: 2, height: 2))
        }
        let texture: SKTexture = SKTexture(image: image)
        texture.filteringMode = SKTextureFilteringMode.nearest
        cached = texture
        return texture
    }
}
