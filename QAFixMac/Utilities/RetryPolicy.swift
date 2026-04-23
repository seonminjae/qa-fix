import Foundation

struct RetryPolicy {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let multiplier: Double
    let maxDelay: TimeInterval
    let jitter: Double

    static let `default` = RetryPolicy(
        maxAttempts: 5,
        baseDelay: 1.0,
        multiplier: 2.0,
        maxDelay: 16.0,
        jitter: 0.2
    )

    func delay(forAttempt attempt: Int, retryAfterSeconds: Double? = nil) -> TimeInterval {
        let exponential = min(maxDelay, baseDelay * pow(multiplier, Double(attempt - 1)))
        let jitterRange = exponential * jitter
        let jittered = exponential + Double.random(in: -jitterRange...jitterRange)
        let computed = max(0, jittered)
        if let retryAfter = retryAfterSeconds {
            return max(retryAfter, computed)
        }
        return computed
    }

    func shouldRetry(status: Int) -> Bool {
        switch status {
        case 408, 425, 429, 500, 502, 503, 504, 529: return true
        default: return false
        }
    }
}

actor ConcurrencyLimiter {
    private var active = 0
    private let limit: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
        // Slot ownership was transferred from the releaser; `active` is
        // unchanged on purpose. Do not increment here — a concurrent
        // `acquire()` would otherwise push us above `limit`.
    }

    func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
            // Slot stays "active" — ownership transfers to the resumed waiter.
        } else {
            active -= 1
        }
    }
}
