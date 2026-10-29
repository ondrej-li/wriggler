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
    private var wormSprites: [Int: SKSpriteNode] = [:]
    private var crawls: [Int: WormCrawl] = [:]
    private var lastPositions: [Int: Vec2] = [:]

    /// The player is drawn from the same atlas as the rivals, so it gets an id
    /// outside the range the rivals use.
    private static let playerWormID = -1

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
    }

    func sync(world: MazeWorld, deltaTime: Double = 0) {
        if renderedRoom != world.roomID {
            buildRoom(world.room)
            renderedRoom = world.roomID
        }
        syncItems(world)
        syncWorms(world, deltaTime: deltaTime)
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
        for sprite in layout.sprites where art.category(of: sprite.shape).isPainted {
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

    /// Places the player's worm and every rival that is in this room.
    private func syncWorms(_ world: MazeWorld, deltaTime: Double) {
        guard let art = art.wormSprite() else { return }
        let scale = cellPixels / CGFloat(RoomArt.shared.cellPixels)
        let size = CGSize(
            width: art.pixels.width * scale,
            height: art.pixels.height * scale
        )

        var worms: [Int: (position: Vec2, facing: Facing)] = [
            Self.playerWormID: (world.player.position, world.player.facing)
        ]
        for rival in world.rivalsInRoom {
            worms[rival.id] = (rival.position, rival.facing)
        }

        for (id, sprite) in wormSprites where worms[id] == nil {
            sprite.removeFromParent()
            wormSprites.removeValue(forKey: id)
            crawls.removeValue(forKey: id)
            lastPositions.removeValue(forKey: id)
        }

        for (id, worm) in worms {
            let sprite =
                wormSprites[id]
                ?? {
                    let node = SKSpriteNode(texture: art.texture)
                    node.size = size
                    node.zPosition = 3
                    actorNode.addChild(node)
                    wormSprites[id] = node
                    return node
                }()
            var crawl = crawls[id] ?? WormCrawl()
            crawl.advance(
                distance: (worm.position - (lastPositions[id] ?? worm.position)).length,
                deltaTime: deltaTime
            )
            crawls[id] = crawl
            lastPositions[id] = worm.position

            // Bunched up the worm is shorter, so slide it forward by the amount it
            // lost behind its head: that end stays planted and the tail catches up,
            // the way an inchworm walks.
            let sign: CGFloat = worm.facing == .left ? -1 : 1
            // Snap the squash to whole source pixels, so the crawl cycles through
            // a handful of crisp frames instead of smearing every edge.
            let stretch = quantized(crawl.stretch, pixels: art.pixels.width)
            let thickness = quantized(crawl.thickness, pixels: art.pixels.height)
            let anchor = scenePoint(worm.position, roomHeight: world.room.rows)
            sprite.position = CGPoint(
                x: anchor.x + sign * size.width * (1 - stretch) / 2,
                y: anchor.y
            )
            sprite.xScale = sign * stretch
            sprite.yScale = thickness
        }
    }

    /// Rounds a scale so the sprite covers a whole number of its own pixels.
    private func quantized(_ scale: Double, pixels: Double) -> CGFloat {
        guard pixels > 0 else { return CGFloat(scale) }
        return CGFloat((scale * pixels).rounded() / pixels)
    }

    /// Snaps to whole virtual pixels so the upscale stays crisp.
    private func scenePoint(_ world: Vec2, roomHeight: Int) -> CGPoint {
        CGPoint(
            x: (world.x * cellPixels).rounded(),
            y: (-world.y * cellPixels + CGFloat(roomHeight) * cellPixels).rounded()
        )
    }
}
