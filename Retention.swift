import Foundation

enum SnapshotRetention {
    static let keepFreshSeconds: TimeInterval = 48 * 3600
    static let maxAgeBeforeDayRuleSeconds: TimeInterval = 60 * 86400

    private static let oldNamePattern = #"^\d{4}-\d{2}-\d{2}_\d{4}$"#

    /// Phase 0 snapshot names: `yyyy-MM-dd_HHmm` (four time digits = hour and minute).
    static func isOldFormatCandidate(_ name: String) -> Bool {
        name.range(of: oldNamePattern, options: .regularExpression) != nil
    }

    /// Keep-or-delete decision for old-format candidates, oldest instant first (caller sorts names).
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
}
