import SpriteKit
import SwiftUI
import WrigglerCore

/// Hosts the SpriteKit view, the HUD and the touch controls.
struct GameContainerView: View {
    let maze: Maze

    @State private var session: GameSession?
    @State private var viewport: CGSize = .zero
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.zxBlack.ignoresSafeArea()

                if let session {
                    SpriteView(scene: session.scene, options: [.ignoresSiblingOrder])
                        .padding(.top, Self.topBarHeight)
                        .padding(.bottom, Self.controlsHeight)
                        .padding(.horizontal, Self.sideMargin)
                        .ignoresSafeArea(edges: .bottom)

                    GameHUD(session: session)

                    TouchControls(input: session.input)
                        .opacity(session.isPaused ? 0 : 1)

                    if session.isPaused {
                        pausedOverlay(session)
                    }
                }
            }
            .onAppear { makeSession(viewport: playArea(in: geometry.size)) }
            .onChange(of: geometry.size) { _, size in
                let area = playArea(in: size)
                viewport = area
                session?.restart(viewport: area)
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
            session?.start()
        }
        .onDisappear { session?.stop() }
        .onKeyPress(phases: [.down, .up]) { press in handle(press) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                session?.start()
            } else {
                session?.stop()
            }
        }
    }

    /// Space left for the maze once the HUD and the on-screen controls are placed.
    private func playArea(in size: CGSize) -> CGSize {
        CGSize(
            width: max(1, size.width - Self.sideMargin * 2),
            height: max(1, size.height - Self.topBarHeight - Self.controlsHeight)
        )
    }

    private func makeSession(viewport size: CGSize) {
        guard session == nil, size.width > 1, size.height > 1 else { return }
        let created = GameSession(
            maze: maze,
            sceneSize: size,
            demo: ProcessInfo.processInfo.arguments.contains("-demo")
        )
        session = created
        created.start()
        isFocused = true
    }

    static let topBarHeight: CGFloat = 44
    static let controlsHeight: CGFloat = 108
    static let sideMargin: CGFloat = 10

    private func pausedOverlay(_ session: GameSession) -> some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("PAUSED")
                    .font(.zx(30, weight: .heavy))
                    .foregroundStyle(Color.zxYellow)
                Text("\(session.roomsExplored) rooms explored")
                    .font(.zx(12))
                    .foregroundStyle(Color.zxDimWhite)
                HStack(spacing: 12) {
                    MenuButton(title: "RESUME", tint: .zxGreen) { session.setPaused(false) }
                    MenuButton(title: "RESTART", tint: .zxMagenta) { session.restart() }
                }
            }
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard let session else { return .ignored }
        if let button = InputController.Button(key: press.key) {
            session.input.set(button, pressed: press.phase != .up)
            return .handled
        }
        if press.phase == .down {
            switch press.key {
            case "p", "P", .escape:
                session.togglePause()
                return .handled
            case "r", "R":
                session.restart()
                return .handled
            default:
                break
            }
        }
        return .ignored
    }
}
