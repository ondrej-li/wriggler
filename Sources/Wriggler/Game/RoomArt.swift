import CoreGraphics
import SpriteKit
import UIKit
import WrigglerCore

/// The reconstructed room artwork: a tile atlas, a sprite atlas, and per-room
/// layouts.
///
/// The rooms are drawn from 331 repeating 8x8 tiles, which reproduce 98.9% of the
/// original cells exactly. Whatever was pasted over a tile - creatures, flowers,
/// the "START" lettering - comes back as a sprite, so the game can decide what to
/// draw and, in particular, leave enemies out.
@MainActor
final class RoomArt {
    struct Layout {
        /// 30x16 atlas indices, row-major. Negative means "nothing here".
        let tiles: [Int16]
        let sprites: [Sprite]
    }

    struct Sprite {
        let shape: Int
        /// Top-left corner and size, in tiles.
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    enum Category: String {
        case enemy
        case actor
        case prop
    }

    private struct Wire: Decodable {
        struct Tiles: Decodable {
            let columns: Int
            let count: Int
            let stride: Int
        }

        struct Sprites: Decodable {
            struct Bound: Decodable {
                let x: Int
                let y: Int
                let w: Int
                let h: Int
            }

            let cell: Int
            let columns: Int
            let count: Int
            let bounds: [Bound]
        }

        struct Room: Decodable {
            /// Base64 of little-endian uint16 indices.
            let tiles: String
            let sprites: [RoomSprite]
        }

        struct RoomSprite: Decodable {
            let shape: Int
            let x: Double
            let y: Double
            let w: Double
            let h: Double
        }

        let cell: Int
        let columns: Int
        let rows: Int
        let tiles: Tiles
        let sprites: Sprites
        let rooms: [String: Room]
    }

    static let shared = RoomArt()

    // Overwritten from the art file; the defaults keep the type usable when the
    // artwork is missing.
    private(set) var columns = 30
    private(set) var rows = 16
    private(set) var cellPixels = 8

    /// Shape index to category. Anything unlisted is treated as an enemy, so new
    /// or unclassified artwork never appears by accident.
    private(set) var categories: [Int: Category] = [:]
    private(set) var tileTextures: [[SKTexture]] = []
    private(set) var spriteTextures: [SKTexture] = []
    private var layouts: [String: Layout] = [:]
    private var roomTextures: [String: SKTexture] = [:]
    private var tileImages: [CGImage] = []

    private init() {
        guard let url = Bundle.main.url(forResource: "roomart", withExtension: "json", subdirectory: "RoomArt"),
            let data = try? Data(contentsOf: url),
            let wire = try? JSONDecoder().decode(Wire.self, from: data),
            let tilesImage = Self.loadImage("tiles", in: "RoomArt"),
            let spritesImage = Self.loadImage("sprites", in: "RoomArt")
        else {
            return
        }

        columns = wire.columns
        rows = wire.rows
        cellPixels = wire.cell

        tileImages = Self.sliceTiles(image: tilesImage, wire: wire.tiles)
        // Each atlas tile is one SKTexture, grouped by atlas row for slicing below.
        tileTextures = [tileImages.map(Self.texture)]
        spriteTextures = wire.sprites.bounds.compactMap { bound in
            Self.crop(spritesImage, x: bound.x, y: bound.y, width: bound.w, height: bound.h).map(Self.texture)
        }

        for (key, room) in wire.rooms {
            guard let raw = Data(base64Encoded: room.tiles) else { continue }
            let tiles: [Int16] = raw.withUnsafeBytes { buffer in
                buffer.bindMemory(to: UInt16.self).map { Int16(bitPattern: $0) }
            }
            layouts[key] = Layout(
                tiles: tiles,
                sprites: room.sprites.map {
                    Sprite(shape: $0.shape, x: $0.x, y: $0.y, width: $0.w, height: $0.h)
                }
            )
        }

        loadCategories()
    }

    var isLoaded: Bool { !tileTextures.isEmpty }

    func layout(for room: GridPoint) -> Layout? {
        layouts["\(room.y),\(room.x)"]
    }

    func category(of shape: Int) -> Category {
        categories[shape] ?? .enemy
    }

    func spriteTexture(_ shape: Int) -> SKTexture? {
        guard shape >= 0, shape < spriteTextures.count else { return nil }
        return spriteTextures[shape]
    }

    /// The whole room's tiles composited into one texture, built once per room.
    func backgroundTexture(for room: GridPoint) -> SKTexture? {
        let key = "\(room.y),\(room.x)"
        if let cached = roomTextures[key] { return cached }
        guard let layout = layouts[key] else { return nil }

        let width = columns * cellPixels
        let height = rows * cellPixels
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let ctx = context.cgContext
            for row in 0..<rows {
                for column in 0..<columns {
                    let index = Int(layout.tiles[row * columns + column])
                    guard index >= 0, index < tileImages.count else { continue }
                    ctx.draw(
                        tileImages[index],
                        in: CGRect(
                            x: column * cellPixels,
                            y: row * cellPixels,
                            width: cellPixels,
                            height: cellPixels
                        )
                    )
                }
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        roomTextures[key] = texture
        return texture
    }

    // MARK: - Loading helpers

    private func loadCategories() {
        guard
            let url = Bundle.main.url(forResource: "sprite-categories", withExtension: "json", subdirectory: "RoomArt"),
            let data = try? Data(contentsOf: url),
            let table = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return
        }
        for (key, value) in table {
            if let shape = Int(key), let category = Category(rawValue: value) {
                categories[shape] = category
            }
        }
    }

    private static func loadImage(_ name: String, in folder: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: folder),
            let image = UIImage(contentsOfFile: url.path)
        else {
            return nil
        }
        return image.cgImage
    }

    private static func sliceTiles(image: CGImage, wire: Wire.Tiles) -> [CGImage] {
        (0..<wire.count).compactMap { index in
            let x = (index % wire.columns) * wire.stride
            let y = (index / wire.columns) * wire.stride
            return crop(image, x: x, y: y, width: wire.stride, height: wire.stride)
        }
    }

    private static func crop(_ image: CGImage, x: Int, y: Int, width: Int, height: Int) -> CGImage? {
        image.cropping(to: CGRect(x: x, y: y, width: width, height: height))
    }

    private static func texture(_ image: CGImage) -> SKTexture {
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }
}
