import SpriteKit
import UIKit
import WrigglerCore

/// Loads pixel art from the asset catalog with nearest-neighbour filtering so the
/// original 8×8 Spectrum artwork stays crisp when upscaled.
@MainActor
enum PixelArt {
    private static var cache: [String: SKTexture] = [:]

    static func texture(named name: String) -> SKTexture? {
        if let cached = cache[name] { return cached }
        guard let image = UIImage(named: name) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        cache[name] = texture
        return texture
    }

    static func sprite(named name: String, size: CGSize) -> SKSpriteNode? {
        guard let texture = texture(named: name) else { return nil }
        return SKSpriteNode(texture: texture, size: size)
    }
}

/// How a tile kind is drawn: a sprite if one exists, otherwise a flat colour.
struct TileAppearance {
    let textureName: String
    let color: SKColor

    static func appearance(for tile: Tile) -> TileAppearance? {
        switch tile {
        case .empty:
            nil
        case .solid:
            TileAppearance(textureName: "tile_wall", color: ZXPalette.cyan)
        case .platform:
            TileAppearance(textureName: "tile_platform", color: ZXPalette.yellow)
        case .ladder:
            TileAppearance(textureName: "tile_ladder", color: ZXPalette.green)
        case .hazard:
            TileAppearance(textureName: "tile_spike", color: ZXPalette.magenta)
        case .goal:
            TileAppearance(textureName: "tile_exit", color: ZXPalette.brightCyan)
        }
    }
}

enum SpriteName {
    static let playerIdle = "player_idle"
    static let playerWalkA = "player_walk_a"
    static let playerWalkB = "player_walk_b"
    static let playerJump = "player_jump"
    static let enemyCrawler = "enemy_crawler"
}
