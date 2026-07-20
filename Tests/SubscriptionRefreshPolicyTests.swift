import XCTest
@testable import RaylineCore

final class SubscriptionRefreshPolicyTests: XCTestCase {

    private let policy = SubscriptionRefreshPolicy.default
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func source(lastRefreshedAt: Date?) -> SubscriptionSource {
        SubscriptionSource(
            name: "S",
            url: "https://sub.example/list",
            lastRefreshedAt: lastRefreshedAt
        )
    }

    func testNeverRefreshedIsDue() {
        XCTAssertTrue(policy.isDue(lastRefreshedAt: nil, now: now))
    }

    func testRecentlyRefreshedIsNotDue() {
        let recent = now.addingTimeInterval(-60)
        XCTAssertFalse(policy.isDue(lastRefreshedAt: recent, now: now))
    }

    func testExactlyAtTheIntervalIsDue() {
        let boundary = now.addingTimeInterval(-policy.interval)
        XCTAssertTrue(policy.isDue(lastRefreshedAt: boundary, now: now))
    }

    func testJustInsideTheIntervalIsNotDue() {
        let almost = now.addingTimeInterval(-policy.interval + 1)
        XCTAssertFalse(policy.isDue(lastRefreshedAt: almost, now: now))
    }

    func testWellPastTheIntervalIsDue() {
        let old = now.addingTimeInterval(-policy.interval * 10)
        XCTAssertTrue(policy.isDue(lastRefreshedAt: old, now: now))
    }

    /// A clock that moved backwards must not park a subscription forever.
    func testFutureTimestampIsTreatedAsDue() {
        let future = now.addingTimeInterval(policy.interval)
        XCTAssertTrue(policy.isDue(lastRefreshedAt: future, now: now))
    }

    func testOnlyStaleSourcesAreSelected() {
        let fresh = source(lastRefreshedAt: now.addingTimeInterval(-60))
        let stale = source(lastRefreshedAt: now.addingTimeInterval(-policy.interval * 2))
        let never = source(lastRefreshedAt: nil)

        let due = policy.sourcesDue([fresh, stale, never], now: now)

        XCTAssertEqual(due.count, 2)
        XCTAssertTrue(due.contains { $0.id == stale.id })
        XCTAssertTrue(due.contains { $0.id == never.id })
        XCTAssertFalse(due.contains { $0.id == fresh.id }, "A fresh source must not be refetched")
    }

    func testNoSourcesMeansNothingDue() {
        XCTAssertTrue(policy.sourcesDue([], now: now).isEmpty)
    }

    func testCheckIntervalIsShorterThanRefreshInterval() {
        XCTAssertLessThan(
            policy.checkInterval, policy.interval,
            "Checking less often than the interval would delay refreshes past their due time"
        )
    }
}
