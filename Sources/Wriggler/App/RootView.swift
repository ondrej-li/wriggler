import SwiftUI
import WrigglerCore

struct RootView: View {
    @State private var maze: Maze?
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Color.zxBlack.ignoresSafeArea()

            if let maze {
                GameContainerView(maze: maze)
            } else if let loadError {
                VStack(spacing: 10) {
                    Text("MAZE DATA ERROR")
                        .font(.zx(18, weight: .bold))
                        .foregroundStyle(Color.zxMagenta)
                    Text(loadError)
                        .font(.zx(12))
                        .foregroundStyle(Color.zxDimWhite)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            } else {
                Text("LOADING . . .")
                    .font(.zx(16))
                    .foregroundStyle(Color.zxYellow)
            }
        }
        .task { load() }
        .statusBarHidden()
    }

    private func load() {
        guard maze == nil, loadError == nil else { return }
        do {
            maze = try MazeBundle.load()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

enum MazeBundle {
    static func load(bundle: Bundle = .main) throws -> Maze {
        guard let url = bundle.url(forResource: "maze", withExtension: "json", subdirectory: "Maze") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Maze(definition: try MazeDefinition.load(from: try Data(contentsOf: url)))
    }
}

#Preview {
    RootView()
}
