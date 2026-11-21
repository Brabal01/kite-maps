import Foundation

/**
 Decides which part of a route to look up next. It owns no network and no
 clock, so the request behaviour of a long drive is testable.

 * Only sections inside a window ahead of the vehicle are asked for
   (`lookaheadMeters`), nearest first, so a 400 km route costs the same as a
   40 km one at any moment.
 * A failed section is retried at most `maxAttempts` times, with exponential
   backoff, and a server-provided wait (Retry-After) is respected.
 * Consecutive failures open a circuit breaker: nothing is requested until the
   cool-down ends, instead of retrying every section in turn.
 * A section the vehicle has passed is never requested.
 */
public struct RouteSectionScheduler: Sendable {
    public struct Config: Sendable {
        public var sectionMeters = 4_000.0
        public var lookaheadMeters = 24_000.0
        public var maxAttempts = 4
        public var baseBackoff: TimeInterval = 15
        public var maxBackoff: TimeInterval = 240
        public var breakerThreshold = 3
        public var breakerCooldown: TimeInterval = 90

        public init() {}
    }

    public enum Status: Equatable, Sendable {
        case pending
        case loading
        case loaded
        case failed(attempts: Int, retryAt: Date)
        /** The retry budget is spent; the section stays unavailable. */
        case abandoned
    }

    public let config: Config
    public let totalMeters: Double
    public private(set) var statuses: [Status]
    public private(set) var progressMeters = 0.0
    private var consecutiveFailures = 0
    private var breakerOpenUntil: Date?
    private var attemptsMade: [Int: Int] = [:]

    public init(totalMeters: Double, config: Config = Config()) {
        self.config = config
        self.totalMeters = max(0, totalMeters)
        let count = totalMeters > 0 ? Int(ceil(totalMeters / config.sectionMeters)) : 0
        statuses = Array(repeating: .pending, count: count)
    }

    public var sectionCount: Int { statuses.count }

    public func range(of index: Int) -> ClosedRange<Double> {
        let start = Double(index) * config.sectionMeters
        return start...min(totalMeters, start + config.sectionMeters)
    }

    public mutating func updateProgress(_ meters: Double) {
        if meters.isFinite { progressMeters = max(progressMeters, max(0, meters)) }
    }

    /** The sections that matter now: the one the vehicle is on and those inside the look-ahead. */
    public var window: Range<Int> {
        guard !statuses.isEmpty else { return 0..<0 }
        let first = min(statuses.count - 1, Int(progressMeters / config.sectionMeters))
        let last = min(statuses.count, Int(floor((progressMeters + config.lookaheadMeters) / config.sectionMeters)) + 1)
        return first..<max(first + 1, last)
    }

    /** The next section to request, or nil when nothing is due (all loaded, waiting, or breaker open). */
    public mutating func next(now: Date) -> Int? {
        if let until = breakerOpenUntil {
            if now < until { return nil }
            breakerOpenUntil = nil
        }
        guard !statuses.contains(.loading) else { return nil }
        for index in window {
            switch statuses[index] {
            case .pending:
                statuses[index] = .loading
                return index
            case .failed(_, let retryAt) where now >= retryAt:
                statuses[index] = .loading
                return index
            default: continue
            }
        }
        return nil
    }

    public mutating func succeeded(_ index: Int) {
        guard statuses.indices.contains(index) else { return }
        statuses[index] = .loaded
        consecutiveFailures = 0
    }

    /** [wait] is a server-provided minimum, such as Retry-After or a mirror's remaining back-off. */
    public mutating func failed(_ index: Int, now: Date, wait: TimeInterval = 0) {
        guard statuses.indices.contains(index) else { return }
        let attempts = attemptsMade[index, default: 0] + 1
        attemptsMade[index] = attempts
        consecutiveFailures += 1
        if consecutiveFailures >= config.breakerThreshold {
            breakerOpenUntil = now.addingTimeInterval(max(config.breakerCooldown, wait))
        }
        guard attempts < config.maxAttempts else {
            statuses[index] = .abandoned
            return
        }
        let backoff = min(config.maxBackoff, config.baseBackoff * pow(2, Double(attempts - 1)))
        statuses[index] = .failed(attempts: attempts, retryAt: now.addingTimeInterval(max(backoff, wait)))
    }

    /** A request that was cancelled (route changed, view closed) is not a failure. */
    public mutating func cancelled(_ index: Int) {
        guard statuses.indices.contains(index), statuses[index] == .loading else { return }
        statuses[index] = .pending
    }

    public var isWindowLoaded: Bool { window.allSatisfy { statuses[$0] == .loaded } }
    public var isRouteLoaded: Bool { statuses.allSatisfy { $0 == .loaded } }

    /** Some section the vehicle still needs could not be loaded and is not being retried right now. */
    public var hasUnavailableSection: Bool {
        window.contains { index in
            switch statuses[index] {
            case .failed, .abandoned: return true
            default: return false
            }
        }
    }

    /** When to look again if nothing is due now; nil when only progress can create new work. */
    public func nextWake(now: Date) -> Date? {
        var wake: Date?
        for index in window {
            switch statuses[index] {
            case .failed(_, let retryAt): wake = min(wake ?? retryAt, retryAt)
            case .pending: wake = min(wake ?? now, now)
            default: break
            }
        }
        guard var due = wake else { return nil }
        if let until = breakerOpenUntil, until > due { due = until }
        return due
    }
}
