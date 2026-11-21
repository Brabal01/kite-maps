import Foundation

/**
 One end of a journey as the planner understands it. `origin == nil` in the stored
 model means "wherever the user is when the journey is opened"; it is never a
 stored position.
 */
public enum JourneyEndpoint: Equatable, Sendable {
    case currentLocation
    case place(Place)

    public var place: Place? {
        if case .place(let place) = self { return place }
        return nil
    }
}

/**
 A whole journey the user chose to keep: both ends, every stop, the travel
 mode and route preferences. This is deliberately separate from the one
 resumable `SavedTrip`, which is an interrupted drive, not a plan.

 The stored shape mirrors the planner's `DirectionsState` exactly:
 `origin` (nil = current location), `destination`, `stops` kept in
 origin→destination order, and a `isReturnTrip` flag that makes the trip run from
 `destination` back to `origin`. That is the only way to keep "My location"
 meaningful after a reversal: a saved start can be a real place, but "my
 location" is not a place and must not be copied into the destination slot.
 */
public struct SavedJourney: Identifiable, Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var id: UUID
    public var name: String
    public var origin: Place?
    public var destination: Place
    /** Always in origin→destination order, whichever way the trip runs. */
    public var stops: [Place]
    public var modeRaw: Int
    public var notes: String
    public var travelDate: Date?
    public var createdAt: Date
    public var avoidTolls: Bool
    public var avoidHighways: Bool
    /** Imported GPX geometry is not turn-by-turn guidance. */
    public var isGPXTrack: Bool
    /** True when the trip runs from `destination` back to `origin` (nil origin = to the current location). */
    public var isReturnTrip: Bool
    public var isFavorite: Bool
    public var lastUsedAt: Date?
    public var schemaVersion: Int

    public var mode: TravelMode {
        get { TravelMode(rawValue: modeRaw) ?? .drive }
        set { modeRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), name: String, origin: Place?, destination: Place,
                stops: [Place] = [], mode: TravelMode = .drive, notes: String = "",
                travelDate: Date? = nil, createdAt: Date = Date(),
                avoidTolls: Bool = false, avoidHighways: Bool = false,
                isGPXTrack: Bool = false, returnTrip: Bool = false,
                isFavorite: Bool = false, lastUsedAt: Date? = nil) {
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
        self.isReturnTrip = returnTrip
        self.isFavorite = isFavorite
        self.lastUsedAt = lastUsedAt
        self.schemaVersion = Self.currentSchemaVersion
        normalize()
    }

    // MARK: Codable — every field added after v31 is optional on disk.

    private enum CodingKeys: String, CodingKey {
        case id, name, origin, destination, stops, modeRaw, notes, travelDate, createdAt
        case avoidTolls, avoidHighways, isGPXTrack, isReturnTrip = "reversed", isFavorite, lastUsedAt, schemaVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        origin = try c.decodeIfPresent(Place.self, forKey: .origin)
        destination = try c.decode(Place.self, forKey: .destination)
        stops = try c.decodeIfPresent([Place].self, forKey: .stops) ?? []
        modeRaw = try c.decodeIfPresent(Int.self, forKey: .modeRaw) ?? TravelMode.drive.rawValue
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        travelDate = try c.decodeIfPresent(Date.self, forKey: .travelDate)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        avoidTolls = try c.decodeIfPresent(Bool.self, forKey: .avoidTolls) ?? false
        avoidHighways = try c.decodeIfPresent(Bool.self, forKey: .avoidHighways) ?? false
        isGPXTrack = try c.decodeIfPresent(Bool.self, forKey: .isGPXTrack) ?? false
        isReturnTrip = try c.decodeIfPresent(Bool.self, forKey: .isReturnTrip) ?? false
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        schemaVersion = Self.currentSchemaVersion
        normalize()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(origin, forKey: .origin)
        try c.encode(destination, forKey: .destination)
        try c.encode(stops, forKey: .stops)
        try c.encode(modeRaw, forKey: .modeRaw)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(travelDate, forKey: .travelDate)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(avoidTolls, forKey: .avoidTolls)
        try c.encode(avoidHighways, forKey: .avoidHighways)
        try c.encode(isGPXTrack, forKey: .isGPXTrack)
        try c.encode(isReturnTrip, forKey: .isReturnTrip)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try c.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
    }

    // MARK: Direction

    /** Where the trip starts, in the order it is travelled. */
    public var travelFrom: JourneyEndpoint {
        isReturnTrip ? .place(destination) : (origin.map(JourneyEndpoint.place) ?? .currentLocation)
    }

    /** Where the trip ends, in the order it is travelled. */
    public var travelTo: JourneyEndpoint {
        isReturnTrip ? (origin.map(JourneyEndpoint.place) ?? .currentLocation) : .place(destination)
    }

    /** The stops in the order they are passed. */
    public var travelStops: [Place] { isReturnTrip ? Array(stops.reversed()) : stops }

    /**
     The same journey run the other way. Reversal is lossless and involutive:
     reversing twice returns the original ends, stops and name.

     * A journey with two real places is swapped physically (origin ⇄ destination,
       stops reversed) so the stored shape stays the simple one older builds read.
     * A journey that starts at "My location" keeps `origin == nil` and flips
       `isReturnTrip`, so the new end is still "My location" rather than a copy of
       the destination.
     */
    public func reversed() -> SavedJourney {
        var copy = self
        let hadAutomaticName = name == automaticName()
        copy.isReturnTrip.toggle()
        copy.normalize()
        if hadAutomaticName { copy.name = copy.automaticName() }
        return copy
    }

    /** A new, independent journey with the same content. */
    public func copy(now: Date = Date()) -> SavedJourney {
        var duplicate = self
        duplicate.id = UUID()
        duplicate.createdAt = now
        duplicate.lastUsedAt = nil
        duplicate.isFavorite = false
        duplicate.name = name.isEmpty ? name : name + " (copy)"
        return duplicate
    }

    public mutating func markUsed(_ date: Date = Date()) { lastUsedAt = date }

    /** Two real ends can be stored swapped; only a "My location" end needs the flag. */
    private mutating func normalize() {
        guard isReturnTrip, let start = origin else { return }
        origin = destination
        destination = start
        stops = Array(stops.reversed())
        isReturnTrip = false
    }

    private func automaticName(currentLocation: String = "My location") -> String {
        "\(label(travelFrom, currentLocation)) → \(label(travelTo, currentLocation))"
    }

    private func label(_ endpoint: JourneyEndpoint, _ currentLocation: String) -> String {
        switch endpoint {
        case .currentLocation: return currentLocation
        case .place(let place): return place.name
        }
    }

    /** The user's name, or both ends in travel order when none was given. */
    public func title(currentLocation: String = "My location") -> String {
        name.isEmpty ? automaticName(currentLocation: currentLocation) : name
    }

    public var displayName: String { title() }
}

public extension Array where Element == SavedJourney {
    /** Favourites first, then most recently used or created. */
    func sortedForDisplay() -> [SavedJourney] {
        sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            return (a.lastUsedAt ?? a.createdAt) > (b.lastUsedAt ?? b.createdAt)
        }
    }

    /** Export every journey as one JSON document that `importJourneys` reads back. */
    func exportedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(SavedJourneyArchive(version: SavedJourney.currentSchemaVersion, journeys: self))
    }
}

struct SavedJourneyArchive: Codable {
    var version: Int
    var journeys: [SavedJourney]
}

public enum SavedJourneyImport {
    public static let maximumBytes = 5_000_000

    /** Journeys from an exported document. New ids are assigned so an import never overwrites an existing journey. */
    public static func journeys(from data: Data) -> [SavedJourney]? {
        guard data.count <= maximumBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(SavedJourneyArchive.self, from: data) else { return nil }
        return archive.journeys.map { journey in
            var fresh = journey
            fresh.id = UUID()
            return fresh
        }
    }
}
