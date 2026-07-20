import XCTest
@testable import RaylineCore

final class ReconnectPolicyTests: XCTestCase {

    private let policy = ReconnectPolicy.default

    func testDelayGrowsExponentially() {
        XCTAssertEqual(policy.delay(forAttempt: 1), 1)
        XCTAssertEqual(policy.delay(forAttempt: 2), 2)
        XCTAssertEqual(policy.delay(forAttempt: 3), 4)
        XCTAssertEqual(policy.delay(forAttempt: 4), 8)
        XCTAssertEqual(policy.delay(forAttempt: 5), 16)
    }

    func testDelayIsCapped() {
        XCTAssertEqual(policy.delay(forAttempt: 6), 30, "Growth must stop at maxDelay")
    }

    /// The cap is what stops a dead server from restarting a process forever.
    func testPolicyGivesUpAfterMaxAttempts() {
        XCTAssertNil(policy.delay(forAttempt: policy.maxAttempts + 1))
        XCTAssertNil(policy.delay(forAttempt: 99))
    }

    func testAttemptNumbersBelowOneAreRejected() {
        XCTAssertNil(policy.delay(forAttempt: 0))
        XCTAssertNil(policy.delay(forAttempt: -1))
    }

    func testEveryAllowedAttemptHasADelay() {
        for attempt in 1...policy.maxAttempts {
            XCTAssertNotNil(policy.delay(forAttempt: attempt), "Attempt \(attempt) must be allowed")
        }
    }

    func testDelayNeverExceedsMaxDelay() {
        for attempt in 1...policy.maxAttempts {
            guard let delay = policy.delay(forAttempt: attempt) else { continue }
            XCTAssertLessThanOrEqual(delay, policy.maxDelay)
            XCTAssertGreaterThan(delay, 0)
        }
    }

    func testStableConnectionResetsTheAttemptCount() {
        XCTAssertTrue(policy.shouldResetAttempts(afterConnectionLasting: 30))
        XCTAssertTrue(policy.shouldResetAttempts(afterConnectionLasting: 120))
    }

    /// A server that accepts and immediately drops must not get unlimited
    /// retries by resetting the counter on every flap.
    func testFlappingConnectionDoesNotResetTheAttemptCount() {
        XCTAssertFalse(policy.shouldResetAttempts(afterConnectionLasting: 0))
        XCTAssertFalse(policy.shouldResetAttempts(afterConnectionLasting: 2))
        XCTAssertFalse(policy.shouldResetAttempts(afterConnectionLasting: 29.9))
    }

    /// Walks the whole schedule the way a flapping server would drive it, to
    /// show the retries are bounded rather than endless.
    func testFlappingServerRunsOutOfAttempts() {
        var attempt = 0
        var delays: [TimeInterval] = []
        while true {
            attempt += 1
            guard let delay = policy.delay(forAttempt: attempt) else { break }
            delays.append(delay)
            // Each reconnect survives 2 s — never long enough to reset.
            XCTAssertFalse(policy.shouldResetAttempts(afterConnectionLasting: 2))
        }
        XCTAssertEqual(delays.count, policy.maxAttempts)
        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 30])
    }
}
