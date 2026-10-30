import Foundation

struct WebhookClaim: Hashable, Sendable {
    let standardizedPath: String
    let inode: UInt64
    let size: UInt64

    var fileName: String {
        URL(fileURLWithPath: standardizedPath).lastPathComponent
    }
}

/// Sole webhook speaker (FR11 / P2).
actor WebhookNotifier {
    private let webhookURL: URL
    private let webhookKey: String
    private let transport: WebhookTransport
    private let sleeper: WebhookSleeper
    private let log: OperationalLog?
    private let iso8601: ISO8601DateFormatter
    private let requestTimeout: TimeInterval = 60

    private var pending: [WebhookClaim] = []
    private var sending = false
    private var backoffStep = 0
    private let backoffSeconds: [Double] = [1, 2, 4, 8, 16, 30]
    private var retryTask: Task<Void, Never>?

    init(
        webhookURL: URL,
        webhookKey: String,
        transport: WebhookTransport,
        sleeper: WebhookSleeper,
        log: OperationalLog? = nil
    ) {
        self.webhookURL = webhookURL
        self.webhookKey = webhookKey
        self.transport = transport
        self.sleeper = sleeper
        self.log = log
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.iso8601 = formatter
    }

    func submit(claims: [WebhookClaim]) {
        mergePending(claims)
        if pending.isEmpty { return }
        cancelRetryWait()
        scheduleSendIfIdle()
    }

    func pendingCountForTesting() -> Int {
        pending.count
    }

    func pendingFileNamesForTesting() -> [String] {
        pending.map(\.fileName)
    }

    private func mergePending(_ claims: [WebhookClaim]) {
        for claim in claims {
            if pending.contains(claim) { continue }
            pending.append(claim)
        }
    }

    private func cancelRetryWait() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func scheduleSendIfIdle() {
        guard !sending, !pending.isEmpty else { return }
        sending = true
        Task { await self.runSendLoop() }
    }

    private func runSendLoop() async {
        while !pending.isEmpty {
            let batch = pending
            let eventTime = iso8601.string(from: Date())
            let names = orderedUniqueFileNames(batch)
            let body = buildBody(eventTime: eventTime, fileNames: names)
            let auth = "Bearer \(webhookKey)"
            let request = WebhookHTTPRequest(
                url: webhookURL,
                authorization: auth,
                body: body,
                timeout: requestTimeout
            )

            let success: Bool
            do {
                let response = try await transport.post(request)
                if (200 ... 299).contains(response.statusCode) {
                    success = true
                    log?.clearDeliveryFailureRateLimit()
                } else {
                    success = false
                    log?.logDeliveryFailure(status: response.statusCode, errorDescription: "non-2xx")
                }
            } catch {
                success = false
                if error is CancellationError {
                    continue
                }
                log?.logDeliveryFailure(status: nil, errorDescription: error.localizedDescription)
            }

            if success {
                for claim in batch {
                    pending.removeAll { $0 == claim }
                }
                backoffStep = 0
                continue
            }

            let stepIndex = min(backoffStep, backoffSeconds.count - 1)
            let wait = backoffSeconds[stepIndex]
            backoffStep = min(backoffStep + 1, backoffSeconds.count - 1)

            let slept = await sleepUnlessCancelled(seconds: wait)
            if !slept {
                backoffStep = max(0, backoffStep - 1)
                continue
            }
        }
        sending = false
    }

    private func orderedUniqueFileNames(_ batch: [WebhookClaim]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for claim in batch {
            let name = claim.fileName
            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }

    private func buildBody(eventTime: String, fileNames: [String]) -> Data {
        let dict: [String: Any] = [
            "event_time": eventTime,
            "files": fileNames,
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    private func sleepUnlessCancelled(seconds: Double) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            retryTask = Task {
                do {
                    try await sleeper.sleep(seconds: seconds)
                    if Task.isCancelled {
                        cont.resume(returning: false)
                    } else {
                        cont.resume(returning: true)
                    }
                } catch is CancellationError {
                    cont.resume(returning: false)
                } catch {
                    cont.resume(returning: true)
                }
            }
        }
    }
}
