import Foundation

/// A single proposed file change. Mirrors the backend's `FileDiff` so we
/// can decode swarm `diff` events directly into this shape.
struct FileDiff: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var operation: Operation
    var before: String?
    var after: String?
    var additions: Int
    var deletions: Int
    var status: Status = .pending

    enum Operation: String, Hashable { case create, modify, delete }
    enum Status: Hashable { case pending, accepted, rejected }
}

extension FileDiff {
    /// Compute hunks for inline rendering. Naive line-diff — good enough
    /// for the preview UI; the backend produces the canonical patch.
    func hunks() -> [Hunk] {
        let beforeLines = (before ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let afterLines  = (after  ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var hunks: [Hunk] = []
        var i = 0, j = 0
        while i < beforeLines.count || j < afterLines.count {
            if i < beforeLines.count, j < afterLines.count, beforeLines[i] == afterLines[j] {
                hunks.append(Hunk(kind: .same, content: beforeLines[i]))
                i += 1; j += 1
            } else if j < afterLines.count, !beforeLines.contains(afterLines[j]) {
                hunks.append(Hunk(kind: .added, content: afterLines[j]))
                j += 1
            } else if i < beforeLines.count, !afterLines.contains(beforeLines[i]) {
                hunks.append(Hunk(kind: .removed, content: beforeLines[i]))
                i += 1
            } else if i < beforeLines.count {
                hunks.append(Hunk(kind: .removed, content: beforeLines[i]))
                i += 1
            } else if j < afterLines.count {
                hunks.append(Hunk(kind: .added, content: afterLines[j]))
                j += 1
            }
        }
        return hunks
    }

    struct Hunk: Identifiable, Hashable {
        let id = UUID()
        let kind: Kind
        let content: String
        enum Kind: Hashable { case same, added, removed }
    }
}
