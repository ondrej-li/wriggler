import Foundation
import WrigglerCore

/// Finds and decodes the levels shipped in the app bundle (`Levels/*.json`).
enum LevelCatalog {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func load(from bundle: Bundle = .main) throws -> [Level] {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Levels"),
            !urls.isEmpty
        else {
            throw Failure(message: "No level files found in the app bundle.")
        }

        return
            try urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                do {
                    return try LevelLoader.parse(json: Data(contentsOf: url))
                } catch {
                    throw Failure(message: "\(url.lastPathComponent): \(error)")
                }
            }
    }
}
