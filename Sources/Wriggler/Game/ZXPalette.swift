import SpriteKit
import SwiftUI

/// The sixteen colours of the ZX Spectrum, used as the game's base palette.
enum ZXPalette {
    static let black = SKColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 1)
    static let blue = SKColor(red: 0.000, green: 0.000, blue: 0.843, alpha: 1)
    static let red = SKColor(red: 0.843, green: 0.000, blue: 0.000, alpha: 1)
    static let magenta = SKColor(red: 0.843, green: 0.000, blue: 0.843, alpha: 1)
    static let green = SKColor(red: 0.000, green: 0.843, blue: 0.000, alpha: 1)
    static let cyan = SKColor(red: 0.000, green: 0.843, blue: 0.843, alpha: 1)
    static let yellow = SKColor(red: 0.843, green: 0.843, blue: 0.000, alpha: 1)
    static let white = SKColor(red: 0.843, green: 0.843, blue: 0.843, alpha: 1)

    static let brightBlue = SKColor(red: 0.000, green: 0.000, blue: 1.000, alpha: 1)
    static let brightRed = SKColor(red: 1.000, green: 0.000, blue: 0.000, alpha: 1)
    static let brightMagenta = SKColor(red: 1.000, green: 0.000, blue: 1.000, alpha: 1)
    static let brightGreen = SKColor(red: 0.000, green: 1.000, blue: 0.000, alpha: 1)
    static let brightCyan = SKColor(red: 0.000, green: 1.000, blue: 1.000, alpha: 1)
    static let brightYellow = SKColor(red: 1.000, green: 1.000, blue: 0.000, alpha: 1)
    static let brightWhite = SKColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1)
}

extension Color {
    static let zxBlack = Color(ZXPalette.black)
    static let zxWhite = Color(ZXPalette.white)
    static let zxCyan = Color(ZXPalette.brightCyan)
    static let zxYellow = Color(ZXPalette.brightYellow)
    static let zxMagenta = Color(ZXPalette.brightMagenta)
    static let zxGreen = Color(ZXPalette.brightGreen)
    static let zxDimWhite = Color(white: 0.55)
}

extension Font {
    /// The monospaced, blocky look of an 8-bit loading screen.
    static func zx(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
