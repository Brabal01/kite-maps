import Foundation

/**
 A whole journey the user chose to keep: both ends, every stop, the travel
 mode and route preferences. This is deliberately separate from the one
 resumable `SavedTrip`, which is an interrupted drive, not a plan.
 */
public struct SavedJourney: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var origin: Place?
    public var destination: Place
    public var stops: [Place]
    public var modeRaw: Int
    public var notes: String
    public var travelDate: Date?
    public var createdAt: Date
    public var avoidTolls: Bool
    public var avoidHighways: Bool
    /** Imported GPX geometry is not turn-by-turn guidance. */
    public var isGPXTrack: Bool

    public var mode: TravelMode {
        get { TravelMode(rawValue: modeRaw) ?? .drive }
        set { modeRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), name: String, origin: Place?, destination: Place,
                stops: [Place] = [], mode: TravelMode = .drive, notes: String = "",
                travelDate: Date? = nil, createdAt: Date = Date(),
                avoidTolls: Bool = false, avoidHighways: Bool = false,
                isGPXTrack: Bool = false) {
        self.id = id
        self.name = name
        self.origin = origin
        self.destination = destination
        self.stops = stops
        self.modeRaw = mode.rawValue
        self.notes = notes
        self.travelDate = travelDate
        self.createdAt = createdAt
        self.avoidTolls = avoidTolls
        self.avoidHighways = avoidHighways
        self.isGPXTrack = isGPXTrack
    }

    public func reversed() -> SavedJourney {
        var copy = self
        copy.origin = destination
        copy.destination = origin ?? destination
        copy.stops = Array(stops.reversed())
        copy.name = "\(destination.name) → \(origin?.name ?? "My location")"
        return copy
    }

    public var displayName: String {
        name.isEmpty ? "\(origin?.name ?? "My location") → \(destination.name)" : name
    }
}
