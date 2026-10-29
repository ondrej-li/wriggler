import SpriteKit
import WrigglerCore

/// Draws the current room: tiles once per room change, actors every frame.
///
/// World units are tiles with the origin at the room's top-left corner and y
/// growing downwards, matching the maze data. Everything is converted to
/// SpriteKit's y-up space here, so the simulation never has to care.
@MainActor
final class RoomRenderer {
    private let roomNode = SKNode()
    private let actorNode = SKNode()
    private var renderedRoom: RoomID?
    private var itemSprites: [Int: SKSpriteNode] = [:]
    private var worm: SKSpriteNode?

    private let cellPixels: CGFloat

    init(cellPixels: CGFloat = 8) {
        self.cellPixels = cellPixels
        roomNode.zPosition = 0
        actorNode.zPosition = 10
    }

    func attach(to parent: SKNode) {
        parent.addChild(roomNode)
        parent.addChild(actorNode)
        worm = SKSpriteNode(texture: TileArt.worm())
        worm?.size = CGSize(width: cellPixels * 2.2, height: cellPixels * 1.8)
        worm?.zPosition = 2
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
        itemSprites.removeAll()

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

        // A frame around the play area marks the room boundary.
        let inset: CGFloat = 1
        let outline = SKShapeNode(
            rect: CGRect(
                x: inset,
                y: inset,
                width: CGFloat(room.columns) * cellPixels - inset * 2,
                height: CGFloat(room.rows) * cellPixels - inset * 2
            ))
        outline.strokeColor = SKColor(red: 0.8, green: 0.8, blue: 0, alpha: 0.85)
        outline.lineWidth = 2
        outline.zPosition = 3
        roomNode.addChild(outline)
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
            sprite.zPosition = 1
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
