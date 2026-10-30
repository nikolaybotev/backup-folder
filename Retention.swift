import Foundation

enum SnapshotRetention {
    static let keepFreshSeconds: TimeInterval = 48 * 3600
    static let maxAgeBeforeDayRuleSeconds: TimeInterval = 60 * 86400

    private static let oldNamePattern = #"^\d{4}-\d{2}-\d{2}_\d{4}$"#
    private static let newNamePattern = #"^\d{4}-\d{2}-\d{2}_\d{6}(-\d+)+$"#

    /// Snapshot names before phase 1: `yyyy-MM-dd_HHmm`.
    static func isOldFormatCandidate(_ name: String) -> Bool {
        name.range(of: oldNamePattern, options: .regularExpression) != nil
    }

    /// Snapshot names from phase 1: `yyyy-MM-dd_HHmmss-<pid>` with optional `-2`, `-3`, … suffixes.
    static func isNewFormatCandidate(_ name: String) -> Bool {
        name.range(of: newNamePattern, options: .regularExpression) != nil
    }

    static func isSnapshotCandidate(_ name: String) -> Bool {
        isOldFormatCandidate(name) || isNewFormatCandidate(name)
    }

    /// Length of the `yyyy-MM-dd_HHmmss` prefix in a new-format name.
    static let newFormatInstantPrefixLength = 17

    /// Keep-or-delete decision for snapshot candidates, oldest instant first (caller sorts names).
    /// Returns directory names to remove; non-parsable names are left in place.
    static func namesToPrune(
        sortedCandidateNames names: [String],
        now: Date,
        parseInstant: (String) -> Date?
    ) -> [String] {
        var keptDays = Set<String>()
        var toDelete: [String] = []
        for n in names {
            guard let t = parseInstant(n) else { continue }
            let age = now.timeIntervalSince(t)
            if age <= keepFreshSeconds { continue }
            let day = String(n.prefix(10))
            if age > maxAgeBeforeDayRuleSeconds || keptDays.contains(day) {
                toDelete.append(n)
            } else {
                keptDays.insert(day)
            }
        }
        return toDelete
    }

    /// Sort candidates by parsed instant, then full name (spec D10).
    static func sortedCandidateNames(
        _ names: [String],
        parseInstant: (String) -> Date?
    ) -> [String] {
        names.filter { isSnapshotCandidate($0) }.sorted { a, b in
            let ta = parseInstant(a)
            let tb = parseInstant(b)
            switch (ta, tb) {
            case let (la?, lb?) where la != lb:
                return la < lb
            case (nil, nil):
                return a < b
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return a < b
            }
        }
    }
}
