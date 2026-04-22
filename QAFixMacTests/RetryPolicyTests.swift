import XCTest
@testable import QAFixMac

final class RetryPolicyTests: XCTestCase {
    func testShouldRetryStatuses() {
        let p = RetryPolicy.default
        XCTAssertTrue(p.shouldRetry(status: 429))
        XCTAssertTrue(p.shouldRetry(status: 500))
        XCTAssertTrue(p.shouldRetry(status: 529))
        XCTAssertFalse(p.shouldRetry(status: 200))
        XCTAssertFalse(p.shouldRetry(status: 400))
    }

    func testRetryAfterWins() {
        let p = RetryPolicy.default
        let delay = p.delay(forAttempt: 1, retryAfterSeconds: 30)
        XCTAssertGreaterThanOrEqual(delay, 30)
    }

    func testExponentialGrowth() {
        let p = RetryPolicy.default
        let d1 = p.delay(forAttempt: 1)
        let d3 = p.delay(forAttempt: 3)
        XCTAssertLessThan(d1, d3 * 2)
    }
}
