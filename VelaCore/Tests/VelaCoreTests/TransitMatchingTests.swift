import XCTest
@testable import VelaCore

/// Matching live GTFS-Realtime data to the right operating day, route and vehicle.
final class TransitMatchingTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func varint(_ value: UInt64) -> [UInt8] {
        var value = value, out: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    private func tag(_ field: Int, _ wire: Int) -> [UInt8] { varint(UInt64(field << 3 | wire)) }
    private func length(_ field: Int, _ bytes: [UInt8]) -> [UInt8] {
        tag(field, 2) + varint(UInt64(bytes.count)) + bytes
    }
    private func text(_ field: Int, _ value: String) -> [UInt8] { length(field, Array(value.utf8)) }
    private func integer(_ field: Int, _ value: Int) -> [UInt8] {
        tag(field, 0) + varint(UInt64(bitPattern: Int64(value)))
    }
    private func float(_ field: Int, _ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return tag(field, 5) + [UInt8(bits & 0xff), UInt8((bits >> 8) & 0xff),
                                UInt8((bits >> 16) & 0xff), UInt8((bits >> 24) & 0xff)]
    }

    private func descriptor(trip: String = "trip-1", route: String = "route-9",
                            startDate: String? = nil, startTime: String? = nil,
                            direction: Int? = nil) -> [UInt8] {
        var out = text(1, trip) + text(5, route)
        if let startTime { out += text(2, startTime) }
        if let startDate { out += text(3, startDate) }
        if let direction { out += integer(6, direction) }
        return out
    }

    private func update(trip: [UInt8], delay: Int, timestamp: Int? = nil) -> [UInt8] {
        let stop = text(4, "stop-1") + length(3, integer(1, delay))
        var out = length(1, trip) + length(2, stop)
        if let timestamp { out += integer(4, timestamp) }
        out += integer(5, delay)
        return out
    }

    private func vehicle(trip: [UInt8], timestamp: Int) -> [UInt8] {
        let position = float(1, 50.08) + float(2, 14.42) + float(5, 8)
        return length(1, trip) + length(2, position) + integer(4, timestamp)
    }

    private func feed(updates: [[UInt8]], vehicles: [[UInt8]] = [], fetchedAt: Date?) -> TransitRealtime.Feed {
        var bytes: [UInt8] = []
        for (index, update) in updates.enumerated() {
            bytes += length(2, text(1, "u\(index)") + length(3, update))
        }
        for (index, vehicle) in vehicles.enumerated() {
            bytes += length(2, text(1, "v\(index)") + length(4, vehicle))
        }
        var feed = TransitRealtime.parse(Data(bytes))!
        feed.fetchedAt = fetchedAt
        return feed
    }

    private func leg(depart: Date?, scheduled: Date?, trip: String = "trip-1",
                     route: String = "route-9", direction: Int? = nil) -> TransitTrip {
        var leg = TransitLeg(isWalk: false, mode: "BUS", line: "42", fromName: "A", toName: "B",
                             depart: depart, arrive: depart?.addingTimeInterval(600), durationSeconds: 600)
        leg.tripId = trip
        leg.routeId = route
        leg.scheduledDepart = scheduled
        leg.directionId = direction
        leg.boardStop = TransitCall(name: "A", timeZone: "UTC", arrival: nil, departure: depart,
                                    track: nil, scheduledTrack: nil, stopCode: nil, detail: nil,
                                    skipped: false, stopId: "stop-1")
        return TransitTrip(depart: depart, arrive: depart?.addingTimeInterval(600),
                           durationSeconds: 600, transfers: 0, legs: [leg])
    }

    private func service(_ date: Date) -> (date: String, time: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return (String(format: "%04d%02d%02d", c.year!, c.month!, c.day!),
                String(format: "%02d:%02d:%02d", c.hour!, c.minute!, c.second!))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                  hour: hour, minute: minute))!
    }

    func testStartDateSelectsTheRightOperatingDay() throws {
        let first = date(2027, 1, 15, 8, 0)
        let second = date(2027, 1, 16, 8, 0)
        let a = service(first), b = service(second)
        let feed = feed(updates: [
            update(trip: descriptor(startDate: a.date, startTime: a.time), delay: 180),
            update(trip: descriptor(startDate: b.date, startTime: b.time), delay: 600)
        ], fetchedAt: first)
        let applied = TransitRealtime.apply(feed, to: [leg(depart: first, scheduled: first)], now: first)
        let result = try XCTUnwrap(applied.first?.legs.first)
        XCTAssertEqual(result.delayMinutes, 3)
        XCTAssertEqual(result.depart, first.addingTimeInterval(180))
        XCTAssertEqual(result.liveFreshness, .live)
    }

    func testAmbiguousTripWithNoStartInfoIsNotApplied() throws {
        let first = date(2027, 1, 15, 8, 0)
        let a = service(first), b = service(first.addingTimeInterval(86_400))
        let feed = feed(updates: [
            update(trip: descriptor(startDate: a.date, startTime: a.time), delay: 180),
            update(trip: descriptor(startDate: b.date, startTime: b.time), delay: 600)
        ], fetchedAt: first)
        let applied = TransitRealtime.apply(feed, to: [leg(depart: nil, scheduled: nil)], now: first)
        let result = try XCTUnwrap(applied.first?.legs.first)
        XCTAssertNil(result.delayMinutes)
        XCTAssertFalse(result.isRealtime)
    }

    func testStaleFeedFallsBackToSchedule() throws {
        let now = date(2027, 1, 15, 8, 0)
        let feed = feed(updates: [update(trip: descriptor(), delay: 180)],
                        fetchedAt: now.addingTimeInterval(-400))
        let applied = TransitRealtime.apply(feed, to: [leg(depart: now, scheduled: now)], now: now)
        let result = try XCTUnwrap(applied.first?.legs.first)
        XCTAssertNil(result.delayMinutes)
        XCTAssertFalse(result.isRealtime)
        XCTAssertEqual(result.liveFreshness, .stale)
    }

    func testRecentFeedIsKeptButMarkedRecent() throws {
        let now = date(2027, 1, 15, 8, 0)
        let feed = feed(updates: [update(trip: descriptor(), delay: 120)],
                        fetchedAt: now.addingTimeInterval(-200))
        let applied = TransitRealtime.apply(feed, to: [leg(depart: now, scheduled: now)], now: now)
        let result = try XCTUnwrap(applied.first?.legs.first)
        XCTAssertEqual(result.delayMinutes, 2)
        XCTAssertEqual(result.liveFreshness, .recent)
        XCTAssertEqual(result.liveAgeSeconds, 200)
    }

    func testStaleVehicleIsNotShown() throws {
        let now = date(2027, 1, 15, 8, 0)
        let feed = feed(updates: [], vehicles: [vehicle(trip: descriptor(), timestamp: Int(now.timeIntervalSince1970) - 300)],
                        fetchedAt: now)
        let applied = TransitRealtime.apply(feed, to: [leg(depart: now, scheduled: now)], now: now)
        let result = try XCTUnwrap(applied.first?.legs.first)
        XCTAssertNil(result.liveVehicle)
    }

    func testOvernightTripUsesPreviousServiceDate() throws {
        let departure = date(2027, 1, 2, 0, 30)
        let feed = feed(updates: [
            update(trip: descriptor(startDate: "20270101", startTime: "24:30:00"), delay: 180)
        ], fetchedAt: departure)
        let applied = TransitRealtime.apply(feed, to: [leg(depart: departure, scheduled: departure)], now: departure)
        let result = try XCTUnwrap(applied.first?.legs.first)
        XCTAssertEqual(result.delayMinutes, 3)
        XCTAssertEqual(result.depart, departure.addingTimeInterval(180))
    }

    func testDirectionMismatchIsNotApplied() throws {
        let now = date(2027, 1, 15, 8, 0)
        let feed = feed(updates: [update(trip: descriptor(direction: 1), delay: 180)], fetchedAt: now)
        let applied = TransitRealtime.apply(feed, to: [leg(depart: now, scheduled: now, direction: 0)], now: now)
        let result = try XCTUnwrap(applied.first?.legs.first)
        XCTAssertNil(result.delayMinutes)
    }
}
