import Foundation

struct DirectoryId: Hashable {
    let systemNumber: UInt64
    let systemFileNumber: UInt64
}

enum WalkPolicy {
    /// Returns whether a directory with this id may be entered. Inserts the id on first visit.
    /// Returns false when ids are missing or the pair was already seen.
    static func mayEnter(
        systemNumber: NSNumber?,
        systemFileNumber: NSNumber?,
        visited: inout Set<DirectoryId>
    ) -> Bool {
        guard let sysNum = systemNumber, let sysFileNum = systemFileNumber else {
            return false
        }
        let id = DirectoryId(
            systemNumber: sysNum.uint64Value,
            systemFileNumber: sysFileNum.uint64Value
        )
        if visited.contains(id) {
            return false
        }
        visited.insert(id)
        return true
    }
}
