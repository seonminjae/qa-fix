import AppKit
import Foundation

enum BookmarkError: Error, LocalizedError {
    case accessDenied(URL)
    case resolveFailed(Error)
    case selectionCancelled

    var errorDescription: String? {
        switch self {
        case .accessDenied(let url): return "Access denied to \(url.path)."
        case .resolveFailed(let error): return "Bookmark resolve failed: \(error.localizedDescription)"
        case .selectionCancelled: return "Directory selection cancelled."
        }
    }
}

struct BookmarkManager {
    static func promptForRepository() throws -> (url: URL, bookmark: Data) {
        let panel = NSOpenPanel()
        panel.title = "Select iOS Repository Root"
        panel.prompt = "Select"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            throw BookmarkError.selectionCancelled
        }
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return (url, bookmark)
    }

    static func resolve(_ bookmark: Data) throws -> URL {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return url
        } catch {
            throw BookmarkError.resolveFailed(error)
        }
    }

    @discardableResult
    static func startAccess(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    static func stopAccess(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
