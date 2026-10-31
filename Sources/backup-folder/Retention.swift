import Foundation

struct RetentionTier {
    let intervalSeconds: Int
    let ageSeconds: Int
}

enum SnapshotRetention {
    static let keepFreshSeconds: TimeInterval = 48 * 3600
    static let maxAgeBeforeDayRuleSeconds: TimeInterval = 60 * 86400

    static let defaultTiers: [RetentionTier] = [
        RetentionTier(intervalSeconds: 0, ageSeconds: Int(keepFreshSeconds)),
        RetentionTier(intervalSeconds: 86400, ageSeconds: Int(maxAgeBeforeDayRuleSeconds)),
    ]

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
        parseInstant: (String) -> Date?,
        tiers: [RetentionTier] = defaultTiers,
        timeZone: TimeZone = .current
    ) -> [String] {
        var markedBuckets: [Int: Set<String>] = [:]
        var toDelete: [String] = []
        for n in names {
            guard let t = parseInstant(n) else { continue }
            let age = now.timeIntervalSince(t)
            guard let tierIndex = tiers.firstIndex(where: { Double($0.ageSeconds) >= age }) else {
                toDelete.append(n)
                continue
            }
            let tier = tiers[tierIndex]
            if tier.intervalSeconds == 0 {
                continue
            }
            let key = bucketKey(
                name: n,
                instant: t,
                intervalSeconds: tier.intervalSeconds,
                timeZone: timeZone
            )
            var marked = markedBuckets[tierIndex, default: []]
            if marked.contains(key) {
                toDelete.append(n)
            } else {
                marked.insert(key)
                markedBuckets[tierIndex] = marked
            }
        }
        return toDelete
    }

    static func bucketKey(
        name: String,
        instant: Date,
        intervalSeconds: Int,
        timeZone: TimeZone
    ) -> String {
        if intervalSeconds == 86400 {
            return String(name.prefix(10))
        }
        if intervalSeconds > 86400, intervalSeconds % 86400 == 0 {
            let n = intervalSeconds / 86400
            let ordinal = civilDayOrdinal(from: instant, timeZone: timeZone)
            return String(ordinal / n)
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "en_US_POSIX")
        let prefix = String(name.prefix(10))
        let comps = cal.dateComponents([.hour, .minute, .second], from: instant)
        let secondOfDay = (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)
        let index = secondOfDay / intervalSeconds
        return "\(prefix)_\(index)"
    }

    static func civilDayOrdinal(from instant: Date, timeZone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "en_US_POSIX")
        let dayStart = cal.startOfDay(for: instant)
        guard let epochDay = cal.date(from: DateComponents(year: 1970, month: 1, day: 1)) else {
            return 0
        }
        let epochStart = cal.startOfDay(for: epochDay)
        return cal.dateComponents([.day], from: epochStart, to: dayStart).day ?? 0
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
