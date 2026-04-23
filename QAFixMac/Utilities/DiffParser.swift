import Foundation

struct DiffFile: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let hunks: [DiffHunk]

    var additions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .addition }.count } }
    var deletions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deletion }.count } }
}

struct DiffHunk: Hashable {
    let header: String
    let lines: [DiffLine]
}

struct DiffLine: Hashable {
    enum Kind { case addition, deletion, context, meta }

    let kind: Kind
    let text: String
}

enum DiffParser {
    static func parse(_ unifiedDiff: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var currentFile: String?
        var currentHunks: [DiffHunk] = []
        var currentHunkHeader: String?
        var currentHunkLines: [DiffLine] = []

        func flushHunk() {
            if let header = currentHunkHeader {
                currentHunks.append(DiffHunk(header: header, lines: currentHunkLines))
            }
            currentHunkHeader = nil
            currentHunkLines = []
        }

        func flushFile() {
            flushHunk()
            if let path = currentFile {
                files.append(DiffFile(path: path, hunks: currentHunks))
            }
            currentFile = nil
            currentHunks = []
        }

        for rawLine in unifiedDiff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("diff --git ") {
                flushFile()
                if let range = line.range(of: " b/") {
                    currentFile = String(line[range.upperBound...])
                }
                continue
            }
            if line.hasPrefix("+++ ") {
                let stripped = line.dropFirst(4)
                if stripped.hasPrefix("b/") {
                    currentFile = String(stripped.dropFirst(2))
                } else {
                    currentFile = String(stripped)
                }
                continue
            }
            if line.hasPrefix("--- ") {
                continue
            }
            if line.hasPrefix("@@") {
                flushHunk()
                currentHunkHeader = line
                continue
            }
            if line.hasPrefix("+") {
                currentHunkLines.append(DiffLine(kind: .addition, text: String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                currentHunkLines.append(DiffLine(kind: .deletion, text: String(line.dropFirst())))
            } else if line.hasPrefix(" ") {
                currentHunkLines.append(DiffLine(kind: .context, text: String(line.dropFirst())))
            } else if !line.isEmpty && currentHunkHeader != nil {
                currentHunkLines.append(DiffLine(kind: .meta, text: line))
            }
        }
        flushFile()
        return files
    }
}
