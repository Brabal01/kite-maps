import Foundation

/** What the app calls: Google first (the full place cards), OpenStreetMap when Google fails. */
public enum PlaceSearch {
    public struct Result: Sendable {
        public var places: [Place]
        /** Set when Google failed and the open-data search answered instead. */
        public var googleError: String?
        public init(places: [Place], googleError: String? = nil) {
            self.places = places
            self.googleError = googleError
        }
    }

    public static func search(_ query: String, center: LatLng, spanMeters: Double?, useGoogle: Bool = true, language: String = "en") async -> Result {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Result(places: []) }
        var googleError: String?
        if useGoogle { do {
            let places = try await GoogleClient.shared.search(q, center: center, spanMeters: spanMeters, language: language)
            if !places.isEmpty {
                return Result(places: places)
            }
        } catch {
            googleError = error.localizedDescription
        } }
        if useGoogle, !Task.isCancelled {
            let suggestions = try? await GoogleClient.shared.suggest(q, near: center, spanMeters: spanMeters ?? 20_000,
                                                                      language: language)
            if let places = suggestions?.places, !places.isEmpty { return Result(places: places) }
        }
        guard !Task.isCancelled else { return Result(places: []) }
        if let pc = await Postcodes.lookup(q) { return Result(places: [pc], googleError: googleError) }
        let osm = (try? await Photon.search(q, near: center)) ?? []
        return Result(places: osm, googleError: googleError)
    }

    public static func mapFocus(query: String, places: [Place], category: Bool) -> [LatLng] {
        let terms = SuggestParser.words(query)
        let named = !category && !terms.isEmpty && places.filter { place in
            let name = Set(SuggestParser.words(place.name))
            return terms.allSatisfy(name.contains)
        }.count * 5 >= places.count * 3
        return places.prefix(named ? 1 : 3).map(\.location)
    }

    static let nearMeters = 100_000.0, farMeters = 300_000.0

    /** Results within 100 km keep Google's order but go ahead of any more than 300 km away. */
    public static func nearFirst(_ places: [Place], center: LatLng) -> [Place] {
        guard let top = places.first, top.location.distance(to: center) > farMeters,
              places.contains(where: { $0.location.distance(to: center) < nearMeters }) else { return places }
        let near = places.filter { $0.location.distance(to: center) <= farMeters }
        return near + places.filter { $0.location.distance(to: center) > farMeters }
    }
}
