import Foundation

/// What to do with a config re-read. The caller keeps the live config on `.keepAndLog` and `.unchanged`.
enum ConfigReloadDecision: Equatable {
    case keepAndLog(String)
    case unchanged
    case applyAndLog(DropBoxWatcherConfig)

    var logLine: String? {
        switch self {
        case .keepAndLog(let line):
            return line
        case .unchanged:
            return nil
        case .applyAndLog:
            return "config reloaded"
        }
    }
}

/// Compares a re-read with the live config. Does not touch the watch, the log file, or the process.
func decideConfigReload(
    current: DropBoxWatcherConfig,
    read: Result<DropBoxWatcherConfig, ConfigLoadError>
) -> ConfigReloadDecision {
    switch read {
    case .failure(let error):
        return .keepAndLog("config reload rejected: \(reloadRejectionReason(error, hiding: current.webhookKey))")
    case .success(let updated):
        if updated == current {
            return .unchanged
        }
        return .applyAndLog(updated)
    }
}

private func reloadRejectionReason(_ error: ConfigLoadError, hiding secret: String) -> String {
    let reason: String
    switch error {
    case .permissionsTooOpen:
        reason = "config permissions too open"
    case .parse(let message):
        reason = "config parse error: \(message)"
    case .io:
        reason = "config io error"
    }
    if secret.isEmpty {
        return reason
    }
    return reason.replacingOccurrences(of: secret, with: "[redacted]")
}
