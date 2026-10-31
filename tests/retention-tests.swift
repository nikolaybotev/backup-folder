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

        // 15-minute civil buckets with a +7 minute offset; both local times kept in different buckets.
        do {
            let east7 = TimeZone(secondsFromGMT: 7 * 60)!
            let parserEast = makeOldNameParser(timeZone: east7)
            var calEast = Calendar(identifier: .gregorian)
            calEast.timeZone = east7
            calEast.locale = Locale(identifier: "en_US_POSIX")
            let n1010 = name(2026, 10, 30, 0, 10)
            let n1020 = name(2026, 10, 30, 0, 20)
            let t1010 = calEast.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 0, minute: 10))!
            let nowEast = t1010.addingTimeInterval(5 * 3600 + 600)
            let tiers15m: [RetentionTier] = [
                RetentionTier(intervalSeconds: 0, ageSeconds: 4 * 3600),
                RetentionTier(intervalSeconds: 15 * 60, ageSeconds: 8 * 3600),
            ]
            let del = SnapshotRetention.namesToPrune(
                sortedCandidateNames: [n1010, n1020],
                now: nowEast,
                parseInstant: parserEast,
                tiers: tiers15m,
                timeZone: east7
            )
            expect(del.isEmpty, "15m tier: local 00:10 and 00:20 both kept")
        }

        // Same 15-minute bucket: later name pruned.
        do {
            let east7 = TimeZone(secondsFromGMT: 7 * 60)!
            let parserEast = makeOldNameParser(timeZone: east7)
            var calEast = Calendar(identifier: .gregorian)
            calEast.timeZone = east7
            calEast.locale = Locale(identifier: "en_US_POSIX")
            let early = name(2026, 10, 30, 0, 10)
            let late = name(2026, 10, 30, 0, 12)
            let tEarly = calEast.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 0, minute: 10))!
            let nowEast = tEarly.addingTimeInterval(5 * 3600 + 600)
            let tiers15m: [RetentionTier] = [
                RetentionTier(intervalSeconds: 0, ageSeconds: 4 * 3600),
                RetentionTier(intervalSeconds: 15 * 60, ageSeconds: 8 * 3600),
            ]
            let del = SnapshotRetention.namesToPrune(
                sortedCandidateNames: [early, late],
                now: nowEast,
                parseInstant: parserEast,
                tiers: tiers15m,
                timeZone: east7
            )
            expect(del == [late], "15m tier: same bucket drops later name")
        }

        // Default daily tier: two date prefixes kept when both sit between 48h and 60d (7h west).
        do {
            let west7 = TimeZone(secondsFromGMT: -7 * 3600)!
            let parserWest = makeOldNameParser(timeZone: west7)
            var calWest = Calendar(identifier: .gregorian)
            calWest.timeZone = west7
            calWest.locale = Locale(identifier: "en_US_POSIX")
            let a = "2026-10-29_2350"
            let b = "2026-10-30_0010"
            let ta = parserWest(a)!
            let tb = parserWest(b)!
            let nowWest = ta.addingTimeInterval(SnapshotRetention.keepFreshSeconds + 3600)
            expect(nowWest.timeIntervalSince(tb) < SnapshotRetention.keepFreshSeconds + 3600, "west7 ages inside window")
            expect(nowWest.timeIntervalSince(tb) > SnapshotRetention.keepFreshSeconds, "west7 both past keep-all")
            let del = SnapshotRetention.namesToPrune(
                sortedCandidateNames: [a, b],
                now: nowWest,
                parseInstant: parserWest,
                timeZone: west7
            )
            expect(del.isEmpty, "default tiers: cross-midnight prefixes both kept")
        }

        // 2-day civil buckets in UTC: 10-30 and 10-31 share; 10-29 is previous bucket.
        do {
            let tiers2d: [RetentionTier] = [
                RetentionTier(intervalSeconds: 0, ageSeconds: Int(SnapshotRetention.keepFreshSeconds)),
                RetentionTier(intervalSeconds: 2 * 86400, ageSeconds: Int(SnapshotRetention.maxAgeBeforeDayRuleSeconds)),
            ]
            let d29 = name(2026, 10, 29, 12, 0)
            let d30 = name(2026, 10, 30, 12, 0)
            let d31 = name(2026, 10, 31, 12, 0)
            let now2d = instant(2026, 10, 31, 12, 0).addingTimeInterval(SnapshotRetention.keepFreshSeconds + 1)
            let del = SnapshotRetention.namesToPrune(
                sortedCandidateNames: [d29, d30, d31],
                now: now2d,
                parseInstant: parser,
                tiers: tiers2d,
                timeZone: tz
            )
            expect(del == [d31], "2d bucket: keep 10-29 and earliest of 10-30/10-31 pair")
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
