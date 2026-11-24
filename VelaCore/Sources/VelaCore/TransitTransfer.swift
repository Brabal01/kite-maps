import Foundation

public struct TransitTransfer: Identifiable, Hashable, Sendable {
    public let id: Int
    public let station: String
    public let secondsLeft: Int
    public let cancelled: Bool
    public var missed: Bool { !cancelled && secondsLeft < 0 }
}

public extension TransitTrip {
    /// Compare the actual connection gap against the estimated walk at the traveller's pace.
    func transferWarnings(walkingPace: Double? = nil) -> [TransitTransfer] {
        let rides = legs.indices.filter { !legs[$0].isWalk }
        return zip(rides, rides.dropFirst()).compactMap { a, b in
            let incoming = legs[a], outgoing = legs[b]
            let cancelled = incoming.cancelled || outgoing.cancelled
            let station = incoming.toName.isEmpty ? outgoing.fromName : incoming.toName
            if cancelled { return TransitTransfer(id: a, station: station, secondsLeft: 0, cancelled: true) }
            guard let arrival = incoming.calls.last?.arrival ?? incoming.arrive,
                  let departure = outgoing.calls.first?.departure ?? outgoing.depart else { return nil }
            let walk = legs[(a + 1)..<b].reduce(0.0) { total, leg in
                guard let pace = walkingPace, leg.distanceMeters > 0 else { return total + leg.durationSeconds }
                let extra = max(0, leg.durationSeconds - leg.distanceMeters / 1.3)
                return total + leg.distanceMeters / min(2.2, max(0.65, pace)) + extra
            }
            let left = Int(floor(departure.timeIntervalSince(arrival) - walk))
            return left < 180 ? TransitTransfer(id: a, station: station, secondsLeft: left, cancelled: false) : nil
        }
    }
}
