import CoreGraphics
import SpriteKit
import UIKit
import WrigglerCore

/// Draws room tiles and actors at run time.
///
/// The maze's pixel art belongs to the original game's authors, so nothing is
/// bundled: tiles are generated from the tile kinds, which keeps the repo clean
/// and still gives every room its own floor colour and character.
@MainActor
enum TileArt {
    /// One tile is 8x8 pixels, the Spectrum character cell.
    static let cell: CGFloat = 8
    static let scale: CGFloat = 4

    private static var cache: [String: SKTexture] = [:]

    static func texture(for kind: TileKind, floor: FloorPalette, row: Int, column: Int) -> SKTexture {
        let key = "\(kind.rawValue)-\(floor.name)-\(row % 4)-\(column % 4)"
        if let cached = cache[key] { return cached }

        let size = CGSize(width: cell * scale, height: cell * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let ctx = context.cgContext
            let px = scale
            draw(kind: kind, floor: floor, row: row % 4, column: column % 4, in: ctx, px: px)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    private static func draw(kind: TileKind, floor: FloorPalette, row: Int, column: Int, in ctx: CGContext, px: CGFloat)
    {
        let full = CGRect(x: 0, y: 0, width: cell * px, height: cell * px)
        switch kind {
        case .floor:
            ctx.setFillColor(floor.background.cgColor)
            ctx.fill(full)
            // A sparse dot keeps large open areas from looking flat.
            ctx.setFillColor(floor.speckle.cgColor)
            let jitter = (row * 3 + column * 5) % 4
            if jitter == 0 {
                ctx.fill(CGRect(x: px * 2, y: px * 5, width: px, height: px))
            }
        case .brick:
            let width = cell * px
            ctx.setFillColor(floor.brick.cgColor)
            ctx.fill(full)
            ctx.setFillColor(floor.mortar.cgColor)
            let half = px * 4
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: px))
            ctx.fill(CGRect(x: 0, y: half, width: width, height: px))
            let offset: CGFloat = (row % 2 == 0) ? half : 0
            ctx.fill(CGRect(x: offset, y: 0, width: px, height: half))
            let second = offset + half
            ctx.fill(CGRect(x: second < width ? second : second - width, y: half, width: px, height: half))
        case .foliage:
            ctx.setFillColor(floor.foliage.cgColor)
            ctx.fill(full)
            ctx.setFillColor(floor.foliageDetail.cgColor)
            ctx.fillEllipse(in: CGRect(x: px, y: px, width: px * 2, height: px * 2))
            ctx.fillEllipse(in: CGRect(x: px * 5, y: px * 4, width: px * 2, height: px * 2))
        case .water:
            ctx.setFillColor(SKColor(red: 0, green: 0, blue: 0.72, alpha: 1).cgColor)
            ctx.fill(full)
            ctx.setFillColor(SKColor(red: 0.35, green: 0.55, blue: 1, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: px * 2, width: px * 3, height: px))
            ctx.fill(CGRect(x: px * 4, y: px * 5, width: px * 3, height: px))
        case .sign:
            ctx.setFillColor(SKColor(red: 0, green: 0, blue: 0, alpha: 1).cgColor)
            ctx.fill(full)
            ctx.setFillColor(SKColor(red: 0.8, green: 0.8, blue: 0, alpha: 1).cgColor)
            ctx.fill(CGRect(x: px, y: px * 2, width: px * 6, height: px * 4))
        }
    }

    /// The worm, drawn facing right; the sprite is flipped for the other direction.
    static func worm(scaleFactor: CGFloat = scale) -> SKTexture {
        let key = "worm-\(scaleFactor)"
        if let cached = cache[key] { return cached }
        let columns = 16
        let rows = 10
        let size = CGSize(width: CGFloat(columns) * scaleFactor, height: CGFloat(rows) * scaleFactor)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let ctx = context.cgContext
            let s = scaleFactor
            let body = SKColor(red: 0.86, green: 0.92, blue: 0.86, alpha: 1)
            let shade = SKColor(red: 0.45, green: 0.58, blue: 0.45, alpha: 1)
            let dark = SKColor(red: 0, green: 0, blue: 0, alpha: 1)

            // Segments from tail (left) to head (right), each a rounded cell.
            let segments: [(CGFloat, CGFloat, CGFloat)] = [
                (1, 4, 2), (3, 3, 4), (5, 2.5, 5), (7.5, 2, 6), (10, 1.5, 7),
            ]
            for (x, y, height) in segments {
                let rect = CGRect(x: x * s, y: y * s, width: s * 3, height: height * s)
                ctx.setFillColor(body.cgColor)
                ctx.fill(rect)
                ctx.setFillColor(shade.cgColor)
                ctx.fill(CGRect(x: rect.minX, y: rect.maxY - s, width: rect.width, height: s))
            }
            // Head.
            ctx.setFillColor(body.cgColor)
            ctx.fill(CGRect(x: s * 12, y: s * 2, width: s * 3, height: s * 6))
            // Eyes.
            ctx.setFillColor(dark.cgColor)
            ctx.fill(CGRect(x: s * 13, y: s * 3, width: s, height: s))
            ctx.fill(CGRect(x: s * 13, y: s * 6, width: s, height: s))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    /// A pickup, drawn as a variant of the object's silhouette.
    static func item(_ kind: ItemKind, scaleFactor: CGFloat = scale) -> SKTexture {
        let key = "item-\(kind.rawValue)-\(scaleFactor)"
        if let cached = cache[key] { return cached }
        let w = 10
        let h = 10
        let size = CGSize(width: CGFloat(w) * scaleFactor, height: CGFloat(h) * scaleFactor)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let ctx = context.cgContext
            let s = scaleFactor
            let light = SKColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
            ctx.setFillColor(light.cgColor)
            switch kind {
            case .key:
                ctx.fill(CGRect(x: s * 2, y: s * 3, width: s * 3, height: s * 3))
                ctx.fill(CGRect(x: s * 5, y: s * 4, width: s * 4, height: s))
                ctx.fill(CGRect(x: s * 7, y: s * 5, width: s, height: s * 2))
            case .mug:
                ctx.fill(CGRect(x: s * 2, y: s * 3, width: s * 5, height: s * 5))
                ctx.fill(CGRect(x: s * 7, y: s * 4, width: s * 2, height: s * 2))
            case .bottle:
                ctx.fill(CGRect(x: s * 4, y: s * 1, width: s * 2, height: s * 2))
                ctx.fill(CGRect(x: s * 3, y: s * 3, width: s * 4, height: s * 6))
            case .skull:
                ctx.fill(CGRect(x: s * 2, y: s * 2, width: s * 6, height: s * 5))
                ctx.setFillColor(SKColor(red: 0, green: 0, blue: 0, alpha: 1).cgColor)
                ctx.fill(CGRect(x: s * 3, y: s * 4, width: s * 2, height: s * 2))
                ctx.fill(CGRect(x: s * 5, y: s * 4, width: s * 2, height: s * 2))
            case .tombstone:
                ctx.fill(CGRect(x: s * 2, y: s * 2, width: s * 6, height: s * 7))
                ctx.setFillColor(SKColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1).cgColor)
                ctx.fill(CGRect(x: s * 4, y: s * 4, width: s * 2, height: s))
                ctx.fill(CGRect(x: s * 3, y: s * 6, width: s * 4, height: s))
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }
}

/// Colours for one room's region of the maze.
struct FloorPalette: Sendable {
    let name: String
    let background: SKColor
    let speckle: SKColor
    let brick: SKColor
    let mortar: SKColor
    let foliage: SKColor
    let foliageDetail: SKColor

    static func palette(named name: String) -> FloorPalette {
        switch name {
        case "black":  // caves: dark floor, red rock
            FloorPalette(
                name: name,
                background: SKColor(red: 0, green: 0, blue: 0, alpha: 1),
                speckle: SKColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1),
                brick: SKColor(red: 0.8, green: 0, blue: 0, alpha: 1),
                mortar: SKColor(red: 0.35, green: 0, blue: 0, alpha: 1),
                foliage: SKColor(red: 0, green: 0.3, blue: 0, alpha: 1),
                foliageDetail: SKColor(red: 0, green: 0.5, blue: 0, alpha: 1)
            )
        case "blue":
            FloorPalette(
                name: name,
                background: SKColor(red: 0.1, green: 0.15, blue: 0.55, alpha: 1),
                speckle: SKColor(red: 0.3, green: 0.35, blue: 0.8, alpha: 1),
                brick: SKColor(red: 0.8, green: 0, blue: 0, alpha: 1),
                mortar: SKColor(red: 0.35, green: 0, blue: 0, alpha: 1),
                foliage: SKColor(red: 0, green: 0.5, blue: 0.5, alpha: 1),
                foliageDetail: SKColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1)
            )
        default:
            FloorPalette(
                name: "green",
                background: SKColor(red: 0, green: 0.8, blue: 0, alpha: 1),
                speckle: SKColor(red: 0, green: 0.6, blue: 0, alpha: 1),
                brick: SKColor(red: 0.8, green: 0, blue: 0, alpha: 1),
                mortar: SKColor(red: 0.1, green: 0, blue: 0, alpha: 1),
                foliage: SKColor(red: 0.1, green: 0.45, blue: 0.1, alpha: 1),
                foliageDetail: SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
            )
        }
    }
}
