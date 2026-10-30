import Foundation

@main
struct RetentionTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                fputs("FAIL: \(message)\n", stderr)
                failures += 1
            }
        }

        let tz = TimeZone(identifier: "Etc/UTC")!
        let parser = makeOldNameParser(timeZone: tz)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        cal.locale = Locale(identifier: "en_US_POSIX")

        func instant(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int, _ ss: Int = 0) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm, second: ss))!
        }

        func name(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int) -> String {
            String(format: "%04d-%02d-%02d_%02d%02d", y, m, d, hh, mm)
        }

        let anchor = instant(2026, 10, 30, 12, 0)

        // Boundary: exactly 48h old is kept (not pruned).
        do {
            let n = name(2026, 10, 28, 12, 0)
            let snap = instant(2026, 10, 28, 12, 0)
            let now = snap.addingTimeInterval(SnapshotRetention.keepFreshSeconds)
            expect(now.timeIntervalSince(snap) == SnapshotRetention.keepFreshSeconds, "48h setup")
            let del = SnapshotRetention.namesToPrune(sortedCandidateNames: [n], now: now, parseInstant: parser)
            expect(del.isEmpty, "48h boundary should keep")
        }

        // Boundary: 48h + 1s triggers day-keeper path (keep first of day).
        do {
            let n = name(2026, 10, 28, 12, 0)
            let snap = instant(2026, 10, 28, 12, 0)
            let now = snap.addingTimeInterval(SnapshotRetention.keepFreshSeconds + 1)
            let del = SnapshotRetention.namesToPrune(sortedCandidateNames: [n], now: now, parseInstant: parser)
            expect(del.isEmpty, "48h+1 first of day should keep")
        }

        // Boundary: exactly 60 days old is still kept as day keeper.
        do {
            let n = name(2026, 8, 31, 12, 0)
            let snap = instant(2026, 8, 31, 12, 0)
            let now = snap.addingTimeInterval(SnapshotRetention.maxAgeBeforeDayRuleSeconds)
            let del = SnapshotRetention.namesToPrune(sortedCandidateNames: [n], now: now, parseInstant: parser)
            expect(del.isEmpty, "60d boundary should keep")
        }

        // Boundary: 60d + 1s is deleted.
        do {
            let n = name(2026, 8, 31, 12, 0)
            let snap = instant(2026, 8, 31, 12, 0)
            let now = snap.addingTimeInterval(SnapshotRetention.maxAgeBeforeDayRuleSeconds + 1)
            let del = SnapshotRetention.namesToPrune(sortedCandidateNames: [n], now: now, parseInstant: parser)
            expect(del == [n], "60d+1 should prune")
        }

        // Two names same day, both older than 48h: keep earliest, delete later.
        do {
            let early = name(2026, 9, 1, 8, 0)
            let late = name(2026, 9, 1, 20, 0)
            let del = SnapshotRetention.namesToPrune(
                sortedCandidateNames: [early, late],
                now: anchor,
                parseInstant: parser
            )
            expect(del == [late], "same day: keep first older snapshot")
        }

        // Fresh name same day must not prevent keeping the older sibling as day keeper.
        do {
            let early = name(2026, 10, 29, 8, 0)
            let fresh = name(2026, 10, 29, 11, 30)
            let del = SnapshotRetention.namesToPrune(
                sortedCandidateNames: [early, fresh],
                now: anchor,
                parseInstant: parser
            )
            expect(del.isEmpty, "fresh sibling must not drop day keeper")
        }

        // Negative age (future snapshot): kept, not pruned.
        do {
            let future = name(2026, 10, 30, 13, 0)
            let del = SnapshotRetention.namesToPrune(sortedCandidateNames: [future], now: anchor, parseInstant: parser)
            expect(del.isEmpty, "future snapshot should keep")
        }

        // Impossible calendar dates are not deleted when parse fails.
        do {
            let bad = "2026-02-31_0000"
            expect(SnapshotRetention.isOldFormatCandidate(bad), "regex accepts impossible date")
            expect(parser(bad) == nil, "impossible date does not parse")
            let del = SnapshotRetention.namesToPrune(sortedCandidateNames: [bad], now: anchor, parseInstant: parser)
            expect(del.isEmpty, "unparsed name must not be pruned")
        }

        // New-format name is a candidate; instant comes from the six time digits.
        do {
            let newName = "2026-10-29_120530-4242"
            expect(SnapshotRetention.isNewFormatCandidate(newName), "new shape is candidate")
            let newParser = makeNewNameParser(timeZone: tz)
            let snap = instant(2026, 10, 29, 12, 5, 30)
            expect(newParser(newName) == snap, "new shape parses instant")
            let now = snap.addingTimeInterval(SnapshotRetention.keepFreshSeconds + 1)
            let del = SnapshotRetention.namesToPrune(sortedCandidateNames: [newName], now: now, parseInstant: newParser)
            expect(del.isEmpty, "new shape 48h+1 first of day should keep")
        }

        // Old and new name in the same minute (same instant): sort by full name after instant.
        do {
            let oldN = name(2026, 9, 15, 14, 30)
            let newN = "2026-09-15_143000-999"
            let combinedParser: (String) -> Date? = { n in
                if SnapshotRetention.isOldFormatCandidate(n) { return parser(n) }
                if SnapshotRetention.isNewFormatCandidate(n) { return makeNewNameParser(timeZone: tz)(n) }
                return nil
            }
            expect(combinedParser(oldN) == combinedParser(newN), "old and new same-minute instants match")
            let sorted = SnapshotRetention.sortedCandidateNames([newN, oldN], parseInstant: combinedParser)
            expect(sorted == [oldN, newN], "same instant: sort by full name")
            let early = name(2026, 9, 15, 8, 0)
            let del = SnapshotRetention.namesToPrune(
                sortedCandidateNames: [early, oldN, newN],
                now: anchor,
                parseInstant: combinedParser
            )
            expect(del.contains(oldN) && del.contains(newN) && !del.contains(early), "same day older than 48h keeps earliest only")
        }

        if failures > 0 {
            fputs("\(failures) test(s) failed\n", stderr)
            exit(1)
        }
        print("retention-tests: OK")
    }

    private static func makeOldNameParser(timeZone: TimeZone) -> (String) -> Date? {
        let tf = DateFormatter()
        tf.dateFormat = "yyyy-MM-dd_HHmm"
        tf.timeZone = timeZone
        tf.locale = Locale(identifier: "en_US_POSIX")
        tf.isLenient = false
        return { tf.date(from: $0) }
    }

    private static func makeNewNameParser(timeZone: TimeZone) -> (String) -> Date? {
        let tf = DateFormatter()
        tf.dateFormat = "yyyy-MM-dd_HHmmss"
        tf.timeZone = timeZone
        tf.locale = Locale(identifier: "en_US_POSIX")
        tf.isLenient = false
        return { name in
            guard SnapshotRetention.isNewFormatCandidate(name) else { return nil }
            let prefix = String(name.prefix(SnapshotRetention.newFormatInstantPrefixLength))
            return tf.date(from: prefix)
        }
    }
}
