import SwiftUI
import WrigglerCore

struct MainMenuView: View {
    let levels: [Level]
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (Level) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            VStack(spacing: 6) {
                Text("WRIGGLER")
                    .font(.zx(52, weight: .heavy))
                    .foregroundStyle(Color.zxCyan)
                    .shadow(color: Color.zxMagenta.opacity(0.8), radius: 0, x: 3, y: 3)

                Text("a Spectrum maze, re-wriggled")
                    .font(.zx(13))
                    .foregroundStyle(Color.zxDimWhite)
            }

            Spacer(minLength: 20)

            content

            Spacer(minLength: 12)

            Text("Original 1985 ZX Spectrum version © its authors")
                .font(.zx(10))
                .foregroundStyle(Color.zxDimWhite.opacity(0.7))
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Text("LOADING . . .")
                .font(.zx(16))
                .foregroundStyle(Color.zxYellow)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Text("LOAD ERROR")
                    .font(.zx(16, weight: .bold))
                    .foregroundStyle(Color.zxMagenta)
                Text(errorMessage)
                    .font(.zx(11))
                    .foregroundStyle(Color.zxDimWhite)
                    .multilineTextAlignment(.center)
            }
        } else if levels.isEmpty {
            Text("NO LEVELS")
                .font(.zx(16))
                .foregroundStyle(Color.zxMagenta)
        } else {
            VStack(spacing: 10) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    Button {
                        onSelect(level)
                    } label: {
                        LevelRow(index: index + 1, level: level)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LevelRow: View {
    let index: Int
    let level: Level

    var body: some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d", index))
                .font(.zx(18, weight: .bold))
                .foregroundStyle(Color.zxYellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(level.name.uppercased())
                    .font(.zx(17, weight: .bold))
                    .foregroundStyle(Color.zxWhite)
                Text("\(level.map.width)×\(level.map.height) cells · \(level.enemySpawns.count) crawlers")
                    .font(.zx(11))
                    .foregroundStyle(Color.zxDimWhite)
            }

            Spacer(minLength: 8)

            Text("PLAY ▶")
                .font(.zx(13, weight: .bold))
                .foregroundStyle(Color.zxGreen)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.zxCyan.opacity(0.35), lineWidth: 1)
        )
    }
}
