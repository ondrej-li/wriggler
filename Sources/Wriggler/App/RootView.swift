import SwiftUI
import WrigglerCore

struct RootView: View {
    @State private var levels: [Level] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var activeLevel: Level?

    var body: some View {
        ZStack {
            Color.zxBlack.ignoresSafeArea()

            if let activeLevel {
                GameContainerView(level: activeLevel) {
                    self.activeLevel = nil
                }
            } else {
                MainMenuView(
                    levels: levels,
                    isLoading: isLoading,
                    errorMessage: loadError
                ) { level in
                    activeLevel = level
                }
            }
        }
        .task { loadLevels() }
        .statusBarHidden()
    }

    private func loadLevels() {
        guard levels.isEmpty else { return }
        defer { isLoading = false }
        do {
            levels = try LevelCatalog.load()
            loadError = nil
            // Launch with `-autostart` to jump straight into the first level (handy while iterating).
            if ProcessInfo.processInfo.arguments.contains("-autostart") {
                activeLevel = levels.first
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#Preview {
    RootView()
}
