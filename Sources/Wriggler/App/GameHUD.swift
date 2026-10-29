import SwiftUI
import WrigglerCore

/// Room, progress and carried-object readout, plus the system buttons.
struct GameHUD: View {
    let session: GameSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    label(session.roomLabel, tint: .zxCyan)
                    carried
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 8) {
                        iconButton(session.isPaused ? "play.fill" : "pause.fill") { session.togglePause() }
                        iconButton("arrow.counterclockwise") { session.restart() }
                    }
                    label("ROOMS \(session.roomsExplored)", tint: .zxYellow)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            Spacer()

            if let notice = session.notice {
                Text(notice)
                    .font(.zx(11, weight: .bold))
                    .foregroundStyle(Color.zxYellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 6)
            }
        }
        .allowsHitTesting(true)
    }

    private var carried: some View {
        HStack(spacing: 6) {
            Text("HOLDING")
                .font(.zx(10))
                .foregroundStyle(Color.zxDimWhite)
            Text(session.carried?.rawValue.uppercased() ?? "—")
                .font(.zx(11, weight: .bold))
                .foregroundStyle(session.carried == nil ? Color.zxDimWhite : Color.zxGreen)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
    }

    private func label(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.zx(12, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
    }

    private func iconButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.zxWhite)
                .frame(width: 34, height: 30)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.zxCyan.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct MenuButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.zx(15, weight: .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tint.opacity(0.6), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}
