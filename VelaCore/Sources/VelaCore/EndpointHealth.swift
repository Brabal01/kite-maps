import Foundation

/**
 Remembers which public mirror recently refused or failed us, so a long drive
 does not keep hammering a server that is rate-limiting or down.

 * HTTP 429/503 and a `Retry-After` header block the mirror for at least that long.
 * Repeated timeouts and 5xx answers block it with exponential backoff
   (`baseDelay`, doubling, capped at `maximumDelay`).
 * After the block expires the next request is a probe: success clears the
   state, failure doubles the delay again (a half-open circuit).
 * A device that is simply offline says nothing about the server, so callers
   must not report those failures.
 */
public final class EndpointHealth: @unchecked Sendable {
    public struct Policy: Sendable {
        public var baseDelay: TimeInterval = 20
        public var maximumDelay: TimeInterval = 900
        /** Failures that are not a rate limit before the mirror is blocked. */
        public var failuresBeforeBlock = 2
        /** Never honour a Retry-After above this, so one bad header cannot silence a mirror all day. */
        public var maximumRetryAfter: TimeInterval = 1_800

        public init() {}
    }

    public enum Failure: Equatable, Sendable {
        case rateLimited(retryAfter: TimeInterval?)
        case serverError
        case timeout
    }

    private struct State {
        var failures = 0
        var blockedUntil: Date?
    }

    public static let shared = EndpointHealth()

    private let policy: Policy
    private let lock = NSLock()
    private var states: [String: State] = [:]

    public init(policy: Policy = Policy()) { self.policy = policy }

    /** True when a request to [endpoint] may be sent at [now]. */
    public func isAvailable(_ endpoint: String, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let until = states[endpoint]?.blockedUntil else { return true }
        return now >= until
    }

    /** The endpoints in [candidates] that may be asked now, in their given order. */
    public func available(_ candidates: [String], now: Date = Date()) -> [String] {
        candidates.filter { isAvailable($0, now: now) }
    }

    /** Seconds until any of [candidates] can be asked again; 0 when one can be asked now. */
    public func secondsUntilAvailable(_ candidates: [String], now: Date = Date()) -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        let waits = candidates.map { endpoint -> TimeInterval in
            guard let until = states[endpoint]?.blockedUntil else { return 0 }
            return max(0, until.timeIntervalSince(now))
        }
        return waits.min() ?? 0
    }

    public func recordSuccess(_ endpoint: String) {
        lock.lock(); defer { lock.unlock() }
        states[endpoint] = nil
    }

    public func recordFailure(_ endpoint: String, _ failure: Failure, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var state = states[endpoint] ?? State()
        state.failures += 1
        let backoff = min(policy.maximumDelay, policy.baseDelay * pow(2, Double(max(0, state.failures - 1))))
        switch failure {
        case .rateLimited(let retryAfter):
            let asked = min(policy.maximumRetryAfter, max(0, retryAfter ?? 0))
            state.blockedUntil = now.addingTimeInterval(max(asked, backoff))
        case .serverError, .timeout:
            if state.failures >= policy.failuresBeforeBlock {
                state.blockedUntil = now.addingTimeInterval(backoff)
            }
        }
        states[endpoint] = state
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        states = [:]
    }

    /** A `Retry-After` header: delta-seconds or an HTTP date. */
    public static func retryAfter(_ header: String?, now: Date = Date()) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }
        if let seconds = TimeInterval(header), seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: header) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    /** Whether a status code is the server's fault and should count against it. */
    public static func failure(forStatus status: Int, retryAfter: TimeInterval?) -> Failure? {
        switch status {
        case 429: return .rateLimited(retryAfter: retryAfter)
        case 503: return .rateLimited(retryAfter: retryAfter)
        case 504, 408: return .timeout
        case 500...599: return .serverError
        default: return nil
        }
    }
}
