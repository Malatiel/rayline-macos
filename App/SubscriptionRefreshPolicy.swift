import Foundation

/// Decides which subscriptions are stale enough to refresh on their own.
///
/// Pure value so the schedule is unit-tested without waiting on a timer, and so
/// "is this due?" stays separate from the network work it triggers.
struct SubscriptionRefreshPolicy: Equatable {

    /// Measured from the last successful refresh, not from when the
    /// subscription was added.
    let interval: TimeInterval

    /// Checking far more often than `interval` costs nothing — the check is
    /// local — and means a machine that was asleep picks up soon after waking.
    let checkInterval: TimeInterval

    static let `default` = SubscriptionRefreshPolicy(
        interval: 6 * 60 * 60,
        checkInterval: 30 * 60
    )

    /// A subscription that has never been refreshed is due immediately: it was
    /// added at some point and its profiles may already be out of date.
    func isDue(lastRefreshedAt: Date?, now: Date) -> Bool {
        guard let lastRefreshedAt else { return true }
        // A timestamp in the future means the clock moved backwards; treat it as
        // due rather than trusting it and never refreshing again.
        guard lastRefreshedAt <= now else { return true }
        return now.timeIntervalSince(lastRefreshedAt) >= interval
    }

    func sourcesDue(_ sources: [SubscriptionSource], now: Date) -> [SubscriptionSource] {
        sources.filter { isDue(lastRefreshedAt: $0.lastRefreshedAt, now: now) }
    }
}
