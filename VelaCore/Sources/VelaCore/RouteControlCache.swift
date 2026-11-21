import Foundation

/**
 Recently fetched road controls for a stretch of route, kept for a short time.
 Switching between alternatives, a planner that rebuilds its preview, and a
 reroute that rejoins the old road all ask for the same stretch again; the
 public servers should not be asked twice for what was answered minutes ago.
 */
public final class RouteControlCache: @unchecked Sendable {
    public static let shared = RouteControlCache()

    private struct Entry {
        var controls: [RouteControl]
        var storedAt: Date
    }

    private let lifetime: TimeInterval
    private let capacity: Int
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var order: [String] = []

    public init(lifetime: TimeInterval = 20 * 60, capacity: Int = 48) {
        self.lifetime = lifetime
        self.capacity = capacity
    }

    /** Identity of a stretch: its exact shape (to about a metre) and who walks it. */
    public static func key(for section: [LatLng], walking: Bool) -> String {
        var hasher = Hasher()
        // Hasher is randomly seeded per process, which is fine for an in-memory cache.
        for point in section {
            hasher.combine(Int((point.lat * 1e5).rounded()))
            hasher.combine(Int((point.lng * 1e5).rounded()))
        }
        return "\(walking ? "w" : "d")\(section.count)-\(hasher.finalize())"
    }

    public func controls(for key: String, now: Date = Date()) -> [RouteControl]? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) < lifetime else {
            entries[key] = nil
            order.removeAll { $0 == key }
            return nil
        }
        return entry.controls
    }

    public func store(_ controls: [RouteControl], for key: String, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        if entries[key] == nil { order.append(key) }
        entries[key] = Entry(controls: controls, storedAt: now)
        while order.count > capacity {
            entries[order.removeFirst()] = nil
        }
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries = [:]
        order = []
    }
}
