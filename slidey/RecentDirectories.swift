import Foundation
import SwiftUI

struct RecentDirectory: Codable, Identifiable, Hashable {
    let bookmark: Data
    let displayName: String
    let path: String

    var id: String { path }
}

class RecentDirectories: ObservableObject {
    @Published var directories: [RecentDirectory] = []
    private let maxRecents = 5
    private let userDefaultsKey = "RecentDirectoryBookmarksV2"

    init() {
        loadRecents()
    }

    func addDirectory(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        let entry = RecentDirectory(
            bookmark: bookmark,
            displayName: url.lastPathComponent,
            path: url.path
        )

        var updated = directories.filter { $0.path != entry.path }
        updated.insert(entry, at: 0)
        if updated.count > maxRecents {
            updated = Array(updated.prefix(maxRecents))
        }
        directories = updated
        saveRecents()
    }

    /// Resolves a recent entry's bookmark and begins security-scoped access.
    /// Caller MUST call `stopAccessingSecurityScopedResource()` on the returned
    /// URL when finished. Returns nil if the bookmark can no longer be resolved
    /// (e.g. the directory was deleted or moved off-volume); the stale entry is
    /// removed from recents in that case.
    func resolveAndBeginAccess(for entry: RecentDirectory) -> URL? {
        var isStale = false
        let resolved: URL
        do {
            resolved = try URL(
                resolvingBookmarkData: entry.bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            removeEntry(matching: entry.path)
            return nil
        }

        guard resolved.startAccessingSecurityScopedResource() else {
            return nil
        }

        if isStale {
            // Refresh the bookmark while we still have access, so the entry
            // keeps working after the next restart.
            if let refreshed = try? resolved.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                replaceBookmark(forPath: entry.path, with: refreshed, displayName: resolved.lastPathComponent, newPath: resolved.path)
            }
        }
        return resolved
    }

    private func removeEntry(matching path: String) {
        directories.removeAll { $0.path == path }
        saveRecents()
    }

    private func replaceBookmark(forPath oldPath: String, with newBookmark: Data, displayName: String, newPath: String) {
        guard let idx = directories.firstIndex(where: { $0.path == oldPath }) else { return }
        directories[idx] = RecentDirectory(bookmark: newBookmark, displayName: displayName, path: newPath)
        saveRecents()
    }

    private func saveRecents() {
        guard let data = try? JSONEncoder().encode(directories) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let entries = try? JSONDecoder().decode([RecentDirectory].self, from: data) else {
            return
        }
        directories = entries
    }
}
