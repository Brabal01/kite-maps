import Security
import SwiftUI
import VelaCore

enum PlacesCredential {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Kite.GooglePlaces",
         kSecAttrAccount as String: "api-key"]
    }

    static var key: String {
        var request = query
        request[kSecReturnData as String] = true
        var data: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &data) == errSecSuccess,
              let data = data as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ key: String) -> Bool {
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let value = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var request = query
        request[kSecValueData as String] = value
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }
}

struct PlacesKeySettings: View {
    @State private var key = PlacesCredential.key
    @State private var saved: Bool?

    var body: some View {
        SecureField("Google Places API key", text: $key)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        Button(L10n.text("Save Places API key")) {
            saved = PlacesCredential.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let saved {
            Text(L10n.text(saved ? "Places API key saved" : "Could not save Places API key"))
                .font(.caption)
        }
    }
}

private enum GooglePlaceMedia {
    struct Author: Decodable, Hashable {
        let displayName: String?
        let uri: URL?
    }

    struct Review: Decodable, Identifiable {
        let name: String
        let rating: Int?
        let text: LocalText?
        let authorAttribution: Author?
        let relativePublishTimeDescription: String?
        var id: String { name }
    }

    struct LocalText: Decodable { let text: String }
    struct Photo: Decodable, Identifiable {
        let name: String
        let authorAttributions: [Author]?
        var id: String { name }
    }

    struct Details: Decodable {
        let reviews: [Review]?
        let photos: [Photo]?
    }

    static func details(placeId: String, key: String, photos: Bool) async throws -> Details {
        var url = URLComponents(url: URL(string: "https://places.googleapis.com/v1/places")!
            .appendingPathComponent(placeId), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "languageCode", value: L10n.isCzech ? "cs" : "en")]
        var request = URLRequest(url: url.url!, timeoutInterval: 15)
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(photos ? "photos" : "reviews", forHTTPHeaderField: "X-Goog-FieldMask")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Details.self, from: data)
    }

    static func photoURL(_ photo: Photo, key: String) async throws -> URL {
        struct Media: Decodable { let photoUri: URL }
        var url = URLComponents(string: "https://places.googleapis.com")!
        url.path = "/v1/\(photo.name)/media"
        url.queryItems = [URLQueryItem(name: "maxWidthPx", value: "1000"),
                          URLQueryItem(name: "skipHttpRedirect", value: "true")]
        var request = URLRequest(url: url.url!, timeoutInterval: 15)
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Media.self, from: data).photoUri
    }
}

struct PlaceMediaSheet: View {
    let place: Place
    var photos = false
    @Environment(\.dismiss) private var dismiss
    @State private var details: GooglePlaceMedia.Details?
    @State private var failed = false
    @State private var retry = 0
    @State private var showGooglePage = false

    /// Google serves at most five reviews through the Places API. Deduplicate by Google's review
    /// resource name, then by author and text, so a refreshed page cannot repeat a card.
    private var reviews: [GooglePlaceMedia.Review] {
        var seen = Set<String>()
        return (details?.reviews ?? []).filter { review in
            let key = !review.name.isEmpty
                ? review.name
                : "\(review.authorAttribution?.displayName ?? "")|\(review.text?.text ?? "")"
            return seen.insert(key).inserted
        }
    }

    /// The few reviews that arrive without a Places API key, from the search card itself.
    private var excerpts: [String] {
        place.reviewExcerpts ?? place.featuredReview.map { [$0] } ?? []
    }

    var body: some View {
        NavigationView {
            List {
                // Native content comes first. The Google web page is an explicit fallback for the
                // full review list, never presented as if Kite had fetched all of it natively.
                if photos {
                    if !place.photoUrls.isEmpty { PhotoStrip(urls: place.photoUrls, height: 150, opensViewer: true) }
                    ForEach(details?.photos ?? []) { NativePlacePhoto(photo: $0) }
                } else {
                    PlaceMetaLine(place: place)
                    if !reviews.isEmpty {
                        ForEach(reviews) { review in
                            VStack(alignment: .leading, spacing: 5) {
                                if let author = review.authorAttribution { AuthorCredit(author: author) }
                                if let rating = review.rating { Label("\(rating)/5", systemImage: "star.fill").foregroundStyle(.orange) }
                                if let date = review.relativePublishTimeDescription { Text(date).font(.caption).foregroundStyle(.secondary) }
                                if let text = review.text?.text, !text.isEmpty { Text(text) }
                            }
                        }
                    } else {
                        ForEach(excerpts, id: \.self) { Text($0) }
                    }
                }
                if place.source == "google", !AppSettings.shared.noGoogle, !PlacesCredential.key.isEmpty {
                    if place.placeId == nil {
                        Text(L10n.text("This place has no Google Places ID.")).foregroundStyle(.secondary)
                    } else if failed {
                        Text(L10n.text("Google content could not be loaded. Check the Places API key."))
                        Button(L10n.text("Reload")) { retry += 1 }
                        PlacesKeySettings()
                    } else if let details {
                        if photos ? (details.photos ?? []).isEmpty : reviews.isEmpty {
                            Text(L10n.text(photos ? "No additional photos available." : "No review text available here."))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView()
                    }
                }
                if !AppSettings.shared.noGoogle, place.googlePlacePage != nil {
                    Section {
                        Button {
                            showGooglePage = true
                        } label: {
                            Label(L10n.text(photos ? "Open photos on the Google Maps website"
                                                   : "Open all reviews on the Google Maps website"),
                                  systemImage: "safari")
                        }
                        Text(L10n.text("Google only provides a sample without an API key. The full list opens on the Google Maps website."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .kiteList()
            .navigationTitle(L10n.text(photos ? "Photos" : "Reviews"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(isPresented: $showGooglePage) {
                if let url = place.googlePlacePage {
                    GoogleMapsPage(url: url, title: place.name, section: photos ? .photos : .reviews)
                }
            }
            .task(id: "\(place.id)-\(retry)") {
                let key = PlacesCredential.key
                guard place.source == "google", !AppSettings.shared.noGoogle, let id = place.placeId, !key.isEmpty else { return }
                let requestedID = place.id
                failed = false
                details = nil
                do {
                    let result = try await GooglePlaceMedia.details(placeId: id, key: key, photos: photos)
                    // The sheet can be reused when the selected place changes; an older answer must
                    // not replace the reviews or photos of the place now on screen.
                    guard !Task.isCancelled, place.id == requestedID else { return }
                    details = result
                } catch {
                    guard !Task.isCancelled, place.id == requestedID else { return }
                    failed = true
                }
            }
        }.navigationViewStyle(.stack)
    }
}

private struct AuthorCredit: View {
    let author: GooglePlaceMedia.Author

    var body: some View {
        if let name = author.displayName {
            if let url = author.uri { Link(name, destination: url).font(.caption.weight(.semibold)) }
            else { Text(name).font(.caption.weight(.semibold)) }
        }
    }
}

private struct NativePlacePhoto: View {
    let photo: GooglePlaceMedia.Photo
    @State private var url: URL?
    @State private var failed = false
    @State private var viewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let url {
                Button { viewing = true } label: {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() }
                        else if phase.error != nil { Image(systemName: "photo").foregroundStyle(.secondary) }
                        else { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                }.buttonStyle(.plain)
                .fullScreenCover(isPresented: $viewing) { PhotoViewer(urls: [url.absoluteString], start: 0) }
            } else if failed {
                Button(L10n.text("Reload")) { Task { await load() } }
            } else {
                ProgressView()
            }
            ForEach(photo.authorAttributions ?? [], id: \.self) { AuthorCredit(author: $0) }
        }.task { if url == nil { await load() } }
    }

    private func load() async {
        failed = false
        do { url = try await GooglePlaceMedia.photoURL(photo, key: PlacesCredential.key) }
        catch { if !Task.isCancelled { failed = true } }
    }
}
