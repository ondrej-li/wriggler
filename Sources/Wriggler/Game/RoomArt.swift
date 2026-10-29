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
        /// Part of a pair drawing of worms. The worms themselves are moving
        /// actors, so the drawing is only used as a spawn marker.
        case worm

        /// False for anything the room must not paint into its background.
        var isPainted: Bool {
            switch self {
            case .enemy, .worm: false
            case .actor, .prop: true
            }
        }
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
    private var spriteImages: [CGImage] = []
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
        spriteImages = wire.sprites.bounds.compactMap { bound in
            Self.crop(spritesImage, x: bound.x, y: bound.y, width: bound.w, height: bound.h)
        }
        spriteTextures = spriteImages.map(Self.texture)

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

    // MARK: - Worms

    /// A single worm, lifted out of the pair drawings the rooms use for them.
    struct WormSprite {
        let texture: SKTexture
        /// Size in the art's own pixels.
        let pixels: CGSize
    }

    private var wormSprites: [Int: WormSprite] = [:]
    private var wormCentres: [Int: [CGPoint]] = [:]

    /// The first shape the categories mark as a worm.
    private var wormShape: Int? {
        categories.filter { $0.value == .worm }.keys.min()
    }

    /// The worm sprite. The rooms draw worms in touching pairs, so the pair is
    /// cut at its horizontal seam and the top worm trimmed out of it.
    func wormSprite() -> WormSprite? {
        guard let shape = wormShape else { return nil }
        return wormSprite(shape)
    }

    private func wormSprite(_ shape: Int) -> WormSprite? {
        if let cached = wormSprites[shape] { return cached }
        guard let image = spriteImage(shape), let halves = wormHalves(of: image),
            let top = Self.trim(halves.0)
        else {
            return nil
        }
        let sprite = WormSprite(
            texture: Self.texture(top),
            pixels: CGSize(width: top.width, height: top.height)
        )
        wormSprites[shape] = sprite
        return sprite
    }

    /// Where the worms a room draws stand, in tiles from its top-left corner.
    func wormSpawns(for room: GridPoint) -> [Vec2] {
        guard let layout = layout(for: room) else { return [] }
        var spawns: [Vec2] = []
        for marker in layout.sprites where category(of: marker.shape) == .worm {
            for centre in wormCentres(marker.shape) {
                spawns.append(
                    Vec2(
                        x: marker.x + Double(centre.x) * marker.width,
                        y: marker.y + Double(centre.y) * marker.height
                    )
                )
            }
        }
        return spawns
    }

    /// Centre of each worm inside a pair drawing, as a fraction of its box.
    private func wormCentres(_ shape: Int) -> [CGPoint] {
        if let cached = wormCentres[shape] { return cached }
        guard let image = spriteImage(shape), let halves = wormHalves(of: image) else { return [] }
        let halfHeight = image.height / 2
        var centres: [CGPoint] = []
        for (index, half) in [halves.0, halves.1].enumerated() {
            guard let bounds = Self.alphaBounds(half) else { continue }
            centres.append(
                CGPoint(
                    x: (bounds.midX) / CGFloat(image.width),
                    y: (CGFloat(index * halfHeight) + bounds.midY) / CGFloat(image.height)
                )
            )
        }
        wormCentres[shape] = centres
        return centres
    }

    private func spriteImage(_ shape: Int) -> CGImage? {
        guard shape >= 0, shape < spriteImages.count else { return nil }
        return spriteImages[shape]
    }

    private func wormHalves(of image: CGImage) -> (CGImage, CGImage)? {
        let halfHeight = image.height / 2
        guard
            let top = Self.crop(image, x: 0, y: 0, width: image.width, height: halfHeight),
            let bottom = Self.crop(
                image, x: 0, y: halfHeight, width: image.width, height: image.height - halfHeight)
        else {
            return nil
        }
        return (top, bottom)
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
            // UIKit hands us a y-down context, but CGImage drawing expects y-up, so
            // without this flip every tile lands upside down.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            for row in 0..<rows {
                for column in 0..<columns {
                    let index = Int(layout.tiles[row * columns + column])
                    guard index >= 0, index < tileImages.count else { continue }
                    ctx.draw(
                        tileImages[index],
                        in: CGRect(
                            x: column * cellPixels,
                            y: (rows - row - 1) * cellPixels,
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

    /// Bounding box of the opaque pixels, in the image's own top-left space.
    private static func alphaBounds(_ image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        // The buffer's first row is the image's bottom row, but cropping counts
        // from the top, so flip the vertical extent.
        return CGRect(x: minX, y: height - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func trim(_ image: CGImage) -> CGImage? {
        guard let bounds = alphaBounds(image) else { return nil }
        return crop(
            image,
            x: Int(bounds.minX),
            y: Int(bounds.minY),
            width: Int(bounds.width),
            height: Int(bounds.height)
        )
    }

    private static func texture(_ image: CGImage) -> SKTexture {
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }
}
