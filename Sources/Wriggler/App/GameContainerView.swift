import SpriteKit
import SwiftUI
import WrigglerCore

/// Hosts the SpriteKit view plus the touch HUD and the pause/game-over overlays.
struct GameContainerView: View {
    let onExit: () -> Void

    @State private var session: GameSession
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isFocused: Bool

    init(level: Level, onExit: @escaping () -> Void) {
        self.onExit = onExit
        _session = State(initialValue: GameSession(level: level))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: session.scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            GameHUD(session: session, onExit: onExit)

            TouchControls(input: session.input)
                .opacity(session.isPaused || session.status != .playing ? 0 : 1)

            if session.status != .playing || session.isPaused {
                overlay
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
            session.start()
        }
        .onDisappear { session.stop() }
        .onKeyPress(phases: [.down, .up]) { press in
            handleKey(press)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                session.start()
            } else {
                session.stop()
            }
        }
    }

    private var overlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 18) {
                Text(title)
                    .font(.zx(34, weight: .heavy))
                    .foregroundStyle(tint)

                Text(subtitle)
                    .font(.zx(13))
                    .foregroundStyle(Color.zxDimWhite)
                    .multilineTextAlignment(.center)

                HStack(spacing: 14) {
                    if session.isPaused {
                        MenuButton(title: "RESUME", tint: .zxGreen) { session.setPaused(false) }
                        MenuButton(title: "EXIT", tint: .zxMagenta, action: onExit)
                    } else {
                        MenuButton(title: "RETRY", tint: .zxYellow) { session.restart() }
                        MenuButton(title: "EXIT", tint: .zxMagenta, action: onExit)
                    }
                }
            }
            .padding(30)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: session.isPaused)
    }

    private var title: String {
        if session.isPaused { return "PAUSED" }
        switch session.status {
        case .died: return "GAME OVER"
        case .completed: return "LEVEL CLEAR"
        case .playing: return ""
        }
    }

    private var subtitle: String {
        if session.isPaused { return "Take a breath." }
        switch session.status {
        case .died: return "The wriggler did not make it."
        case .completed: return "Time \(formatted(session.elapsedSeconds))"
        case .playing: return ""
        }
    }

    private var tint: Color {
        if session.isPaused { return .zxYellow }
        switch session.status {
        case .died: return .zxMagenta
        case .completed: return .zxGreen
        case .playing: return .zxWhite
        }
    }

    private func formatted(_ seconds: Double) -> String {
        String(format: "%05.1fs", seconds)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if let button = InputController.Button(key: press.key) {
            session.input.set(button, pressed: press.phase != .up)
            return .handled
        }

        guard press.phase == .down else { return .ignored }

        switch press.key {
        case "p", "P", .escape:
            session.togglePause()
            return .handled
        case "r", "R":
            session.restart()
            return .handled
        default:
            return .ignored
        }
    }
}
