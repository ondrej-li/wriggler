import SwiftUI

/// Top bar with the level name, run timer and system buttons.
struct GameHUD: View {
    let session: GameSession
    let onExit: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 16) {
                HStack(spacing: 14) {
                    Text(session.level.name.uppercased())
                        .font(.zx(14, weight: .bold))
                        .foregroundStyle(Color.zxCyan)

                    Text(time)
                        .font(.zx(14))
                        .foregroundStyle(Color.zxYellow)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))

                Spacer()

                HUDButton(systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                    session.togglePause()
                }
                HUDButton(systemImage: "xmark") {
                    onExit()
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)

            Spacer()
        }
        .allowsHitTesting(true)
    }

    private var time: String {
        String(format: "TIME %05.1f", session.elapsedSeconds)
    }
}

private struct HUDButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.zxWhite)
                .frame(width: 38, height: 34)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.zxCyan.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Wide, blocky button used by the menu and the pause overlays.
struct MenuButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.zx(16, weight: .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tint.opacity(0.6), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MenuButton(title: "RESUME", tint: .zxGreen) {}
        .padding(40)
        .background(Color.zxBlack)
}
