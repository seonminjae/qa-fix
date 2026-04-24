export interface RetryPolicy {
  maxAttempts: number
  baseDelay: number
  multiplier: number
  maxDelay: number
  jitter: number
  /** Returns delay in seconds. */
  delay(attempt: number, retryAfterSec?: number): number
  shouldRetry(status: number): boolean
}

class RetryPolicyImpl implements RetryPolicy {
  readonly maxAttempts: number
  readonly baseDelay: number
  readonly multiplier: number
  readonly maxDelay: number
  readonly jitter: number

  constructor(opts?: {
    maxAttempts?: number
    baseDelay?: number
    multiplier?: number
    maxDelay?: number
    jitter?: number
  }) {
    this.maxAttempts = opts?.maxAttempts ?? 5
    this.baseDelay = opts?.baseDelay ?? 1.0
    this.multiplier = opts?.multiplier ?? 2.0
    this.maxDelay = opts?.maxDelay ?? 16.0
    this.jitter = opts?.jitter ?? 0.2
  }

  delay(attempt: number, retryAfterSec?: number): number {
    const exponential = Math.min(this.maxDelay, this.baseDelay * Math.pow(this.multiplier, attempt - 1))
    const jitterRange = exponential * this.jitter
    const jittered = exponential + (Math.random() * 2 - 1) * jitterRange
    const computed = Math.max(0, jittered)
    if (retryAfterSec !== undefined) {
      return Math.max(retryAfterSec, computed)
    }
    return computed
  }

  shouldRetry(status: number): boolean {
    return [408, 425, 429, 500, 502, 503, 504, 529].includes(status)
  }
}

export const defaultRetryPolicy: RetryPolicy = new RetryPolicyImpl()

interface Deferred {
  resolve: () => void
}

export class ConcurrencyLimiter {
  private active = 0
  private readonly limit: number
  private waiters: Deferred[] = []

  constructor(limit: number) {
    this.limit = limit
  }

  acquire(): Promise<void> {
    if (this.active < this.limit) {
      this.active++
      return Promise.resolve()
    }
    return new Promise<void>((resolve) => {
      this.waiters.push({ resolve })
    })
  }

  release(): void {
    const waiter = this.waiters.shift()
    if (waiter) {
      // Slot ownership transfers to the resumed waiter; active stays unchanged.
      waiter.resolve()
    } else {
      this.active--
    }
  }
}
