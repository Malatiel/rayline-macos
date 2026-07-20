import Foundation

/// Decides whether and when to retry after the tunnel drops on its own.
///
/// Kept as a pure value so the retry schedule is unit-tested without timers.
/// The mechanism that actually waits and reconnects lives in `VPNManager`,
/// because it spawns a process and cannot be exercised in tests.
struct ReconnectPolicy: Equatable {

    /// How many times to retry a single drop before giving up and leaving the
    /// error on screen. Without a cap, a server that is simply gone would keep
    /// restarting a process forever.
    let maxAttempts: Int

    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    /// How long a connection must survive before its drop is treated as a fresh
    /// incident rather than a continuation of the previous one.
    ///
    /// Without this, a server that accepts a connection and drops it seconds
    /// later would reset the attempt counter every time and retry forever.
    let stabilityThreshold: TimeInterval

    static let `default` = ReconnectPolicy(
        maxAttempts: 6,
        baseDelay: 1,
        maxDelay: 30,
        stabilityThreshold: 30
    )

    /// Delay before the given 1-based attempt, or `nil` once the policy gives up.
    func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 1, attempt <= maxAttempts else { return nil }
        let exponential = baseDelay * pow(2, Double(attempt - 1))
        return min(exponential, maxDelay)
    }

    /// Whether a drop after a connection of this length starts a new count.
    func shouldResetAttempts(afterConnectionLasting duration: TimeInterval) -> Bool {
        duration >= stabilityThreshold
    }
}
