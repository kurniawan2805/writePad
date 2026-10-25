import Foundation

/// When autosave runs and how it backs off. Pure, so the timing rules can be tested without waiting.
struct SaveTiming: Sendable, Equatable {
    /// Quiet time after the last change before writing.
    var delay: Duration = .seconds(1)
    /// However often changes push the save back, it starts within this long of the first unsaved change.
    var maxLatency: Duration = .seconds(5)
    /// Wait before the first retry of a failed save; doubles with each failure.
    var retryBase: Duration = .seconds(1)
    var retryCap: Duration = .seconds(60)

    /// `notBefore` is the end of a retry backoff: changes made while a save keeps failing don't retry sooner.
    func deadline(now: ContinuousClock.Instant, firstUnsaved: ContinuousClock.Instant,
                  notBefore: ContinuousClock.Instant? = nil) -> ContinuousClock.Instant {
        let due = min(now + delay, firstUnsaved + maxLatency)
        return notBefore.map { max(due, $0) } ?? due
    }

    func retryDelay(afterFailures failures: Int) -> Duration {
        min(retryBase * (1 << min(max(failures - 1, 0), 6)), retryCap)
    }
}
