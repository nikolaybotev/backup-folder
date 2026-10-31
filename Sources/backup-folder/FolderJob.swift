import Foundation

struct FolderPair: Sendable, Equatable {
    var source: String
    var dest: String
}

enum FolderJob {
    /// Highest folder status. Empty input is 0; the backup schema does not start a job with no folders.
    static func aggregate(_ statuses: [Int32]) -> Int32 {
        statuses.max() ?? 0
    }

    /// Runs every pair. `concurrency` nil, or a non-positive value, starts them all.
    /// A positive cap is how many folder bodies may be inside `runner` at once.
    /// Bodies run on a Dispatch queue because clonefile and flock block, and the
    /// cooperative pool must keep making progress.
    static func run(
        pairs: [FolderPair],
        concurrency: Int?,
        runner: @escaping @Sendable (FolderPair) -> Int32
    ) async -> Int32 {
        if pairs.isEmpty {
            return 0
        }
        let width: Int
        if let concurrency, concurrency > 0 {
            width = min(concurrency, pairs.count)
        } else {
            width = pairs.count
        }
        return await withTaskGroup(of: Int32.self) { group in
            var nextIndex = 0
            while nextIndex < width {
                let pair = pairs[nextIndex]
                nextIndex += 1
                group.addTask {
                    await runOffPool(pair, runner)
                }
            }
            var statuses: [Int32] = []
            statuses.reserveCapacity(pairs.count)
            while let status = await group.next() {
                statuses.append(status)
                if nextIndex < pairs.count {
                    let pair = pairs[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await runOffPool(pair, runner)
                    }
                }
            }
            return aggregate(statuses)
        }
    }

    private static func runOffPool(
        _ pair: FolderPair,
        _ runner: @escaping @Sendable (FolderPair) -> Int32
    ) async -> Int32 {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            DispatchQueue.global().async {
                let status = runner(pair)
                continuation.resume(returning: status)
            }
        }
    }
}
