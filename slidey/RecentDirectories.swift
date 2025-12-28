import Foundation
import SwiftUI

class RecentDirectories: ObservableObject {
    @Published var directories: [URL] = []
    private let maxRecents = 5
    private let userDefaultsKey = "RecentDirectories"

    init() {
        loadRecents()
    }

    func addDirectory(_ url: URL) {
        var updatedDirectories = directories.filter { $0 != url }
        updatedDirectories.insert(url, at: 0)

        if updatedDirectories.count > maxRecents {
            updatedDirectories = Array(updatedDirectories.prefix(maxRecents))
        }

        directories = updatedDirectories
        saveRecents()
    }

    private func saveRecents() {
        let paths = directories.map { $0.path }
        UserDefaults.standard.set(paths, forKey: userDefaultsKey)
    }

    private func loadRecents() {
        guard let paths = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] else {
            return
        }

        directories = paths.map { URL(fileURLWithPath: $0) }
    }
}
