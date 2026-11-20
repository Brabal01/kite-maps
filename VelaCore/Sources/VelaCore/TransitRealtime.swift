import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 * A small, dependency-free reader for the GTFS-Realtime protobuf feed
 * (gtfs-realtime.proto). It reads the three messages Kite can use:
 *
 * - `TripUpdate`: delays and skipped/cancelled stops;
 * - `VehiclePosition`: where the vehicle is now;
 * - `Alert`: service changes and disruptions.
 *
 * The feed URL is configured by the user, so nothing here assumes a country, an
 * agency or a particular server. A missing or broken feed leaves the scheduled
 * Transitous answer untouched.
 */
public enum TransitRealtime {
    public struct Feed: Sendable {
        /** The URL or provider key this feed came from, for diagnostics and matching. */
        public var provider: String?
        /** When the feed was fetched, used when a message carries no timestamp. */
        public var fetchedAt: Date?
        public var tripUpdates: [TripUpdate] = []
        public var vehicles: [Vehicle] = []
        public var alerts: [Alert] = []
        public init() {}
        public var isEmpty: Bool { tripUpdates.isEmpty && vehicles.isEmpty && alerts.isEmpty }
    }

    public struct TripUpdate: Sendable {
        public var tripId: String?
        public var routeId: String?
        public var startDate: String?
        public var startTime: String?
        public var directionId: Int?
        public var vehicleId: String?
        /** When the provider produced this update. */
        public var timestamp: Date?
        /** Whole-trip delay in seconds, when the feed sends one. */
        public var delay: Int?
        public var stops: [StopUpdate] = []
    }

    public struct StopUpdate: Sendable {
        public var stopId: String?
        public var stopSequence: Int?
        public var arrivalDelay: Int?
        public var departureDelay: Int?
        public var skipped = false
    }

    public struct Vehicle: Sendable {
        public var tripId: String?
        public var routeId: String?
        public var startDate: String?
        public var startTime: String?
        public var directionId: Int?
        public var vehicleId: String?
        public var stopId: String?
        public var currentStopSequence: Int?
        public var location: LatLng?
        public var bearing: Double?
        public var speedMps: Double?
        public var updated: Date?
    }

    public struct Alert: Sendable {
        public var tripIds: [String] = []
        public var routeIds: [String] = []
        public var text: String?
    }

    // MARK: - Fetch

    public static func fetch(_ urlString: String, timeout: TimeInterval = 20) async -> Feed? {
        let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let url = URL(string: clean),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host != nil else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Kite-iOS GTFS-Realtime", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  var feed = parse(data), !feed.isEmpty else { return nil }
            feed.provider = clean
            feed.fetchedAt = Date()
            return feed
        } catch {
            return nil
        }
    }

    // MARK: - Apply

    /**
     * Joins [feed] to [trips] using the strongest identity the feed provides: provider/feed, trip id,
     * route id, direction id, start date and start time. A weak match is never applied to a random
     * trip; when two candidates remain, the leg is left on its timetable. Transitous already carries
     * live times from its own feeds, so those legs are not delayed twice.
     */
    public static func apply(_ feed: Feed, to trips: [TransitTrip], now: Date = Date()) -> [TransitTrip] {
        guard !feed.isEmpty else { return trips }
        let updates = feed.tripUpdates.filter { !($0.tripId ?? "").isEmpty }
        let vehicles = feed.vehicles.filter { !($0.tripId ?? "").isEmpty }
        var tripAlerts: [String: [String]] = [:]
        var routeAlerts: [String: [String]] = [:]
        for alert in feed.alerts {
            guard let text = alert.text, !text.isEmpty else { continue }
            for id in alert.tripIds { tripAlerts[id, default: []].append(text) }
            for id in alert.routeIds { routeAlerts[id, default: []].append(text) }
        }
        return trips.map { trip in
            var out = trip
            for i in out.legs.indices where !out.legs[i].isWalk {
                var leg = out.legs[i]
                if let update = chooseUpdate(updates, for: leg) {
                    let age = age(of: update.timestamp, feed: feed, now: now)
                    if age <= 300 {
                        apply(update, to: &leg, freshness: age <= 120 ? .live : .recent,
                              age: age, provider: feed.provider)
                    } else if !leg.isRealtime {
                        // The timetable is still better than a five-minute-old "live" delay.
                        leg.liveFreshness = .stale
                        leg.liveAgeSeconds = Int(age)
                        leg.liveProvider = feed.provider
                    }
                }
                if let vehicle = chooseVehicle(vehicles, for: leg), let location = vehicle.location {
                    let age = age(of: vehicle.updated, feed: feed, now: now)
                    // A stale vehicle position is not "where the bus is now".
                    if age <= 120 {
                        leg.liveVehicle = TransitVehicle(location: location, bearing: vehicle.bearing,
                                                     speedMps: vehicle.speedMps, updated: vehicle.updated)
                        if leg.liveFreshness == .scheduled {
                            leg.liveFreshness = .live
                            leg.liveAgeSeconds = Int(age)
                            leg.liveProvider = feed.provider
                        }
                    }
                }
                var messages: [String] = []
                if let id = leg.tripId { messages += tripAlerts[id] ?? [] }
                if let id = leg.routeId { messages += routeAlerts[id] ?? [] }
                for message in messages where !leg.serviceAlerts.contains(message) {
                    leg.serviceAlerts.append(message)
                }
                out.legs[i] = leg
            }
            // A live delay moves the trip's depart/arrive too, so sorting and the arrival time agree.
            out.depart = out.legs.first?.depart
            out.arrive = out.legs.last?.arrive
            if let a = out.depart, let b = out.arrive { out.durationSeconds = b.timeIntervalSince(a) }
            return out
        }
    }

    private struct StartIdentity {
        var date: String
        var time: String
    }

    private static func age(of timestamp: Date?, feed: Feed, now: Date) -> Double {
        guard let stamp = timestamp ?? feed.fetchedAt else { return 0 }
        return max(0, now.timeIntervalSince(stamp))
    }

    private static func chooseUpdate(_ updates: [TripUpdate], for leg: TransitLeg) -> TripUpdate? {
        let starts = startIdentities(for: leg)
        let exact = updates.filter { update in
            guard let trip = leg.tripId, let live = update.tripId, trip == live else { return false }
            if let route = update.routeId, let own = leg.routeId, route != own { return false }
            if let direction = update.directionId, let own = leg.directionId, direction != own { return false }
            return true
        }
        if exact.count == 1 { return exact[0] }
        if exact.count > 1 {
            let narrowed = exact.filter { update in
                if let date = update.startDate, !date.isEmpty, !starts.isEmpty,
                   !starts.contains(where: { $0.date == date }) { return false }
                if let time = update.startTime, !time.isEmpty, !starts.isEmpty,
                   !starts.contains(where: { $0.time == time }) { return false }
                return true
            }
            if narrowed.count == 1 { return narrowed[0] }
            // Duplicate updates for the same trip are normal; the newest one wins. Different
            // identities with no way to tell them apart are not applied.
            let sorted = narrowed.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            if let first = sorted.first, narrowed.allSatisfy({ sameIdentity($0, first) }) { return first }
            return nil
        }
        // The planner and the feed may spell the trip id differently. Only fall back when route,
        // direction and the exact service start all agree.
        let fallback = updates.filter { update in
            guard let route = update.routeId, let own = leg.routeId, route == own else { return false }
            guard let direction = update.directionId, let own = leg.directionId, direction == own else { return false }
            guard let date = update.startDate, let time = update.startTime, !starts.isEmpty else { return false }
            return starts.contains { $0.date == date && $0.time == time }
        }
        return fallback.count == 1 ? fallback[0] : nil
    }

    private static func chooseVehicle(_ vehicles: [Vehicle], for leg: TransitLeg) -> Vehicle? {
        let starts = startIdentities(for: leg)
        let exact = vehicles.filter { vehicle in
            guard let trip = leg.tripId, let live = vehicle.tripId, trip == live else { return false }
            if let route = vehicle.routeId, let own = leg.routeId, route != own { return false }
            if let direction = vehicle.directionId, let own = leg.directionId, direction != own { return false }
            return true
        }
        if exact.count == 1 { return exact[0] }
        if exact.count > 1 {
            let narrowed = exact.filter { vehicle in
                if let date = vehicle.startDate, !date.isEmpty, !starts.isEmpty,
                   !starts.contains(where: { $0.date == date }) { return false }
                if let time = vehicle.startTime, !time.isEmpty, !starts.isEmpty,
                   !starts.contains(where: { $0.time == time }) { return false }
                return true
            }
            return narrowed.count == 1 ? narrowed[0] : nil
        }
        let fallback = vehicles.filter { vehicle in
            guard let route = vehicle.routeId, let own = leg.routeId, route == own else { return false }
            guard let direction = vehicle.directionId, let own = leg.directionId, direction == own else { return false }
            guard let date = vehicle.startDate, let time = vehicle.startTime, !starts.isEmpty else { return false }
            return starts.contains { $0.date == date && $0.time == time }
        }
        return fallback.count == 1 ? fallback[0] : nil
    }

    private static func sameIdentity(_ a: TripUpdate, _ b: TripUpdate) -> Bool {
        a.tripId == b.tripId && a.routeId == b.routeId && a.startDate == b.startDate
            && a.startTime == b.startTime && a.directionId == b.directionId
    }

    private static func startIdentities(for leg: TransitLeg) -> [StartIdentity] {
        guard let date = leg.scheduledDepart ?? leg.depart else { return [] }
        let zone = leg.boardStop?.timeZone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: 0)!
        return serviceIdentities(date, timeZone: zone)
    }

    private static func serviceIdentities(_ date: Date, timeZone: TimeZone) -> [StartIdentity] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func identity(_ value: Date, nextDay: Bool) -> StartIdentity? {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: value)
            guard let y = c.year, let m = c.month, let d = c.day,
                  let h = c.hour, let mi = c.minute, let s = c.second else { return nil }
            return StartIdentity(date: String(format: "%04d%02d%02d", y, m, d),
                                 time: String(format: "%02d:%02d:%02d", nextDay ? h + 24 : h, mi, s))
        }
        var out: [StartIdentity] = []
        if let today = identity(date, nextDay: false) { out.append(today) }
        // A trip just after midnight belongs to the previous service day in GTFS.
        if let previous = calendar.date(byAdding: .day, value: -1, to: date),
           let yesterday = identity(previous, nextDay: true) { out.append(yesterday) }
        return out
    }

    private static func apply(_ update: TripUpdate, to leg: inout TransitLeg,
                              freshness: TransitLiveFreshness, age: Double, provider: String?) {
        // Transitous' own real-time already moved leg.depart/leg.arrive; don't apply a second delay.
        let alreadyLive = leg.isRealtime
        let stop = update.stops.first { s in
            (leg.boardStop?.stopId != nil && s.stopId == leg.boardStop?.stopId)
                || (leg.exitStop?.stopId != nil && s.stopId == leg.exitStop?.stopId)
        } ?? update.stops.first
        let departureDelay = stop?.departureDelay ?? stop?.arrivalDelay ?? update.delay
        let arrivalDelay = stop?.arrivalDelay ?? departureDelay
        if !alreadyLive {
            if let departureDelay {
                leg.depart = leg.depart?.addingTimeInterval(TimeInterval(departureDelay))
                leg.delayMinutes = Int((Double(departureDelay) / 60).rounded())
            }
            if let arrivalDelay {
                leg.arrive = leg.arrive?.addingTimeInterval(TimeInterval(arrivalDelay))
                leg.arrivalDelayMinutes = Int((Double(arrivalDelay) / 60).rounded())
            }
        } else {
            if leg.delayMinutes == nil, let departureDelay {
                leg.delayMinutes = Int((Double(departureDelay) / 60).rounded())
            }
            if leg.arrivalDelayMinutes == nil, let arrivalDelay {
                leg.arrivalDelayMinutes = Int((Double(arrivalDelay) / 60).rounded())
            }
        }
        if let id = stop?.stopId {
            if leg.boardStop?.stopId == id, stop?.skipped == true { leg.boardStop?.skipped = true }
            if leg.exitStop?.stopId == id, stop?.skipped == true { leg.exitStop?.skipped = true }
        }
        leg.isRealtime = true
        leg.liveFreshness = freshness
        leg.liveAgeSeconds = Int(age)
        leg.liveProvider = provider
    }

    // MARK: - Protobuf

    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        init(_ data: Data) { bytes = [UInt8](data) }
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < bytes.count, shift < 64 {
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }

        mutating func tag() -> (field: Int, wire: Int)? {
            guard let value = varint() else { return nil }
            let field = Int(value >> 3), wire = Int(value & 0x07)
            return field > 0 ? (field, wire) : nil
        }

        mutating func lengthDelimited() -> [UInt8]? {
            guard let count = varint(), count <= UInt64(bytes.count - index) else { return nil }
            let end = index + Int(count)
            let value = Array(bytes[index..<end])
            index = end
            return value
        }

        mutating func fixed32() -> UInt32? {
            guard index + 4 <= bytes.count else { return nil }
            let value = UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8
                | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
            index += 4
            return value
        }

        mutating func fixed64() -> UInt64? {
            guard index + 8 <= bytes.count else { return nil }
            var value: UInt64 = 0
            for offset in 0..<8 { value |= UInt64(bytes[index + offset]) << (UInt64(offset) * 8) }
            index += 8
            return value
        }

        mutating func skip(_ wire: Int) -> Bool {
            switch wire {
            case 0: return varint() != nil
            case 1: return fixed64() != nil
            case 2: return lengthDelimited() != nil
            case 5: return fixed32() != nil
            default: return false
            }
        }
    }

    private static func message(_ bytes: [UInt8], _ body: (Int, Int, inout Reader) -> Bool) -> Bool {
        var reader = Reader(bytes)
        while let (field, wire) = reader.tag() {
            if !body(field, wire, &reader) { return false }
        }
        return true
    }

    private static func string(_ bytes: [UInt8]) -> String? {
        String(bytes: bytes, encoding: .utf8)
    }

    public static func parse(_ data: Data) -> Feed? {
        var feed = Feed()
        var valid = true
        let root = Reader(data)
        var reader = root
        while let (field, wire) = reader.tag() {
            switch (field, wire) {
            case (2, 2):
                guard let bytes = reader.lengthDelimited() else { valid = false; break }
                if let entity = parseEntity(bytes) {
                    if let update = entity.update { feed.tripUpdates.append(update) }
                    if let vehicle = entity.vehicle { feed.vehicles.append(vehicle) }
                    if let alerts = entity.alert { feed.alerts.append(alerts) }
                }
            default:
                if !reader.skip(wire) { valid = false }
            }
            if !valid { break }
        }
        return valid ? feed : nil
    }

    private static func parseEntity(_ data: [UInt8]) -> (update: TripUpdate?, vehicle: Vehicle?, alert: Alert?)? {
        var update: TripUpdate?
        var vehicle: Vehicle?
        var alert: Alert?
        let ok = message(data) { field, wire, reader in
            switch (field, wire) {
            case (3, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                update = parseTripUpdate(bytes)
                return true
            case (4, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                vehicle = parseVehicle(bytes)
                return true
            case (5, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                alert = parseAlert(bytes)
                return true
            default:
                return reader.skip(wire)
            }
        }
        return ok ? (update, vehicle, alert) : nil
    }

    private static func parseTripUpdate(_ data: [UInt8]) -> TripUpdate? {
        var update = TripUpdate()
        let ok = message(data) { field, wire, reader in
            switch (field, wire) {
            case (1, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                let trip = parseTripDescriptor(bytes)
                update.tripId = trip.id
                update.routeId = trip.routeId
                update.startDate = trip.startDate
                update.startTime = trip.startTime
                update.directionId = trip.directionId
                return true
            case (2, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                if let stop = parseStopUpdate(bytes) { update.stops.append(stop) }
                return true
            case (3, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                update.vehicleId = parseVehicleDescriptor(bytes)
                return true
            case (4, 0):
                guard let value = reader.varint() else { return false }
                update.timestamp = Date(timeIntervalSince1970: TimeInterval(value))
                return true
            case (5, 0):
                guard let value = reader.varint() else { return false }
                update.delay = Int(Int64(bitPattern: value))
                return true
            default:
                return reader.skip(wire)
            }
        }
        return ok ? update : nil
    }

    private static func parseStopUpdate(_ data: [UInt8]) -> StopUpdate? {
        var stop = StopUpdate()
        let ok = message(data) { field, wire, reader in
            switch (field, wire) {
            case (1, 0):
                guard let value = reader.varint() else { return false }
                stop.stopSequence = Int(value)
                return true
            case (2, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                stop.arrivalDelay = parseStopEvent(bytes).delay
                return true
            case (3, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                stop.departureDelay = parseStopEvent(bytes).delay
                return true
            case (4, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                stop.stopId = string(bytes)
                return true
            case (5, 0):
                guard let value = reader.varint() else { return false }
                stop.skipped = value == 1 || value == 4 || value == 6
                return true
            default:
                return reader.skip(wire)
            }
        }
        return ok ? stop : nil
    }

    private static func parseStopEvent(_ data: [UInt8]) -> (delay: Int?, time: Int?) {
        var delay: Int?
        var time: Int?
        _ = message(data) { field, wire, reader in
            switch (field, wire) {
            case (1, 0), (2, 0):
                guard let value = reader.varint() else { return false }
                if field == 1 { delay = Int(Int64(bitPattern: value)) } else { time = Int(Int64(bitPattern: value)) }
                return true
            default:
                return reader.skip(wire)
            }
        }
        return (delay, time)
    }

    private static func parseVehicle(_ data: [UInt8]) -> Vehicle? {
        var vehicle = Vehicle()
        let ok = message(data) { field, wire, reader in
            switch (field, wire) {
            case (1, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                let trip = parseTripDescriptor(bytes)
                vehicle.tripId = trip.id
                vehicle.routeId = trip.routeId
                vehicle.startDate = trip.startDate
                vehicle.startTime = trip.startTime
                vehicle.directionId = trip.directionId
                return true
            case (2, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                let position = parsePosition(bytes)
                vehicle.location = position.location
                vehicle.bearing = position.bearing
                vehicle.speedMps = position.speed
                return true
            case (3, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                vehicle.vehicleId = parseVehicleDescriptor(bytes)
                return true
            case (4, 0):
                guard let value = reader.varint() else { return false }
                vehicle.updated = Date(timeIntervalSince1970: TimeInterval(value))
                return true
            case (6, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                vehicle.stopId = string(bytes)
                return true
            case (7, 0):
                guard let value = reader.varint() else { return false }
                vehicle.currentStopSequence = Int(value)
                return true
            default:
                return reader.skip(wire)
            }
        }
        return ok ? vehicle : nil
    }

    private static func parsePosition(_ data: [UInt8]) -> (location: LatLng?, bearing: Double?, speed: Double?) {
        var lat: Double?
        var lng: Double?
        var bearing: Double?
        var speed: Double?
        _ = message(data) { field, wire, reader in
            switch (field, wire) {
            case (1, 5), (2, 5), (3, 5), (5, 5):
                guard let value = reader.fixed32() else { return false }
                let number = Double(Float(bitPattern: value))
                switch field {
                case 1: lat = number
                case 2: lng = number
                case 3: bearing = number
                default: speed = number
                }
                return true
            default:
                return reader.skip(wire)
            }
        }
        guard let lat, let lng, (-90...90).contains(lat), (-180...180).contains(lng) else {
            return (nil, bearing, speed)
        }
        return (LatLng(lat, lng), bearing, speed)
    }

    private static func parseTripDescriptor(_ data: [UInt8]) -> (id: String?, routeId: String?,
                                                                startDate: String?, startTime: String?,
                                                                directionId: Int?) {
        var id: String?
        var routeId: String?
        var startDate: String?
        var startTime: String?
        var directionId: Int?
        _ = message(data) { field, wire, reader in
            switch (field, wire) {
            case (1, 2), (2, 2), (3, 2), (5, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                switch field {
                case 1: id = string(bytes)
                case 2: startTime = string(bytes)
                case 3: startDate = string(bytes)
                default: routeId = string(bytes)
                }
                return true
            case (6, 0):
                guard let value = reader.varint() else { return false }
                directionId = Int(value)
                return true
            default:
                return reader.skip(wire)
            }
        }
        return (id, routeId, startDate, startTime, directionId)
    }

    private static func parseVehicleDescriptor(_ data: [UInt8]) -> String? {
        var id: String?
        _ = message(data) { field, wire, reader in
            guard field == 1, wire == 2, let bytes = reader.lengthDelimited() else {
                return reader.skip(wire)
            }
            id = string(bytes)
            return true
        }
        return id
    }

    private static func parseAlert(_ data: [UInt8]) -> Alert? {
        var alert = Alert()
        var header: String?
        var description: String?
        let ok = message(data) { field, wire, reader in
            switch (field, wire) {
            case (5, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                let selector = parseEntitySelector(bytes)
                if let id = selector.tripId { alert.tripIds.append(id) }
                if let id = selector.routeId { alert.routeIds.append(id) }
                return true
            case (10, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                header = parseTranslatedString(bytes)
                return true
            case (11, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                description = parseTranslatedString(bytes)
                return true
            default:
                return reader.skip(wire)
            }
        }
        guard ok else { return nil }
        alert.text = [header, description == header ? nil : description].compactMap { $0 }.joined(separator: "\n")
        return alert
    }

    private static func parseEntitySelector(_ data: [UInt8]) -> (tripId: String?, routeId: String?) {
        var tripId: String?
        var routeId: String?
        _ = message(data) { field, wire, reader in
            switch (field, wire) {
            case (2, 2), (4, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                if field == 2 {
                    routeId = string(bytes)
                } else {
                    tripId = parseTripDescriptor(bytes).id
                }
                return true
            default:
                return reader.skip(wire)
            }
        }
        return (tripId, routeId)
    }

    private static func parseTranslatedString(_ data: [UInt8]) -> String? {
        var text: String?
        _ = message(data) { field, wire, reader in
            switch (field, wire) {
            case (1, 2):
                guard let bytes = reader.lengthDelimited() else { return false }
                var translation: String?
                _ = message(bytes) { field, wire, reader in
                    guard field == 1, wire == 2, let bytes = reader.lengthDelimited() else {
                        return reader.skip(wire)
                    }
                    translation = string(bytes)
                    return true
                }
                if text == nil, let translation, !translation.isEmpty { text = translation }
                return true
            default:
                return reader.skip(wire)
            }
        }
        return text
    }
}
