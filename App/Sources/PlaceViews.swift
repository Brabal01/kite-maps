import SafariServices
import SwiftUI
import UIKit
import VelaCore

struct PlaceHeader: View {
    @ObservedObject var model: AppModel
    let place: Place
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(place.name)
                    .font(.system(size: 26, weight: .heavy))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .copyable(place.name, below: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button(settings.isSaved(place) ? "Remove from Saved" : "Save place") { settings.toggleSaved(place) }
                    ForEach(settings.savedPlaceLists) { list in
                        Button { settings.toggleList(list.id, place: place) } label: {
                            Label(list.name, systemImage: settings.isInList(place, id: list.id) ? "checkmark" : "folder")
                        }
                    }
                } label: {
                    Image(systemName: settings.isSaved(place) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.primary)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.secondary.opacity(0.18)))
                }.accessibilityLabel("Save to a list")
                Menu {
                    if let url = place.shareURL { ShareLink("Google Maps link", item: url) }
                    if let url = KiteLinks.placeURL(at: place.location, name: place.name) {
                        ShareLink("Kite link", item: url)
                    }
                    ShareLink("Place name", item: place.name)
                    ShareLink("Coordinates", item: String(format: "%.6f, %.6f", place.location.lat, place.location.lng))
                } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.secondary.opacity(0.18)))
                }.buttonStyle(.plain).accessibilityLabel("Share place")
                CircleIconButton(icon: "xmark") { withAnimation { model.closePlace() } }
            }
            PlaceMetaLine(place: place, here: model.userLatLng)
                // Tapping the stars opens the reviews (GitHub #70).
                .onTapGesture { if place.rating != nil { model.showReviews = place.id; model.detent = .full } }
            if model.availableIndoor != nil {
                Button { model.openIndoor() } label: { Label("Floor plan", systemImage: "square.3.layers.3d") }
                    .buttonStyle(.bordered)
            }
            StatusText(place: place).font(.subheadline)
            // The one thing most people want, in reach even with the sheet down.
            HStack(spacing: 10) {
                Button { model.openDirections(to: place) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").font(.system(size: 20, weight: .bold))
                        Text("Directions").font(.system(size: 20, weight: .heavy))
                    }
                    .foregroundColor(Vela.onAccent(scheme))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Capsule().fill(Vela.accent(scheme)))
                }
                .buttonStyle(.plain)
                Button {
                    model.openDirections(to: place)
                    model.startNavigation()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.north.fill").font(.system(size: 18, weight: .bold))
                        Text("Go").font(.system(size: 20, weight: .heavy))
                    }
                    .foregroundColor(Vela.onTonal(scheme))
                    .padding(.horizontal, 24)
                    .frame(minHeight: 56)
                    .background(Capsule().fill(Vela.tonal(scheme)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start driving now")
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .task(id: place.id) { await model.probeIndoor(place) }
    }
}

struct PlaceBody: View {
    @ObservedObject var model: AppModel
    let place: Place
    @ObservedObject private var settings = AppSettings.shared
    @State private var tab = 0
    @State private var hoursOpen = false
    @State private var related: (placeID: String, place: Place)?
    @State private var reviewResult: (featureID: String, rows: [PlaceReview])?
    @State private var galleryResult: (featureID: String, urls: [String])?
    /** Driving time from here, shown on the Directions button like Google Maps. */
    @State private var driveSeconds: Double?
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                SheetTopMarker()
                VStack(alignment: .leading, spacing: 14) {
                    actions
                    PhotoStrip(urls: photos, height: 160, opensViewer: true, streetView: place)
                    Color.clear.frame(height: 0).id("place-tab")
                    if hasAbout || hasReviews {
                        Picker("", selection: $tab) {
                            Text("Overview").tag(0)
                            if hasReviews { Text("Reviews").tag(2) }
                            if hasAbout { Text("About").tag(1) }
                        }
                        .pickerStyle(.segmented)
                    }
                    switch hasReviews || tab != 2 ? tab : 0 {
                    case 1: about
                    case 2: ReviewsList(place: mediaPlace, reviews: reviews)
                    default: overview
                    }
                    Text(attribution).font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
            .sheetScroll()
            .onChange(of: tab) { _ in withAnimation { scroll.scrollTo("place-tab", anchor: .top) } }
        }
        .onChange(of: model.showReviews) { id in
            if id == place.id, hasReviews { tab = 2; model.showReviews = nil }
        }
        .onChange(of: hasReviews) { available in
            if !available, tab == 2 { tab = 0 }
            if available, model.showReviews == place.id { tab = 2; model.showReviews = nil }
        }
        .onAppear {
            if hasReviews, model.showReviews == place.id { tab = 2; model.showReviews = nil }
        }
        .task(id: place.id) { await loadDriveTime() }
        .task(id: "\(place.id)|\(settings.noGoogle)") { await matchMediaPlace() }
        .task(id: mediaFeatureID) {
            guard let id = mediaFeatureID, galleryResult?.featureID != id else { return }
            let urls = await GoogleClient.shared.placeGallery(featureID: id)
            if !Task.isCancelled { galleryResult = (id, urls) }
        }
        .task(id: hasReviews ? mediaFeatureID : nil) {
            guard hasReviews, let id = mediaFeatureID, reviewResult?.featureID != id else { return }
            let rows = await GoogleClient.shared.placeReviews(featureID: id)
            if !Task.isCancelled { reviewResult = (id, rows) }
        }
    }

    private func loadDriveTime() async {
        driveSeconds = nil
        guard let from = model.userLatLng, from.distance(to: place.location) > 300,
              from.distance(to: place.location) < 300_000 else { return }
        // The same way the directions get it, with the user's avoid settings and today's traffic, so
        // the card and the route agree (the open router alone said 23 min for a 29 min drive).
        let s = model.settings
        var r: [Route]?
        if !s.noGoogle {
            r = try? await GoogleClient.shared.directions(from: from, to: place.location, mode: .drive,
                                                          avoidHighways: s.avoidHighways, avoidTolls: s.avoidTolls)
        }
        if r?.isEmpty ?? true { r = try? await OSRM.route(from: from, to: place.location, mode: .drive) }
        guard !Task.isCancelled, let secs = r?.map(\.durationSeconds).min() else { return }
        withAnimation { driveSeconds = secs }
    }

    private var hasAbout: Bool { !place.about.isEmpty }
    private var mediaPlace: Place {
        if !settings.noGoogle, let related, related.placeID == place.id { return related.place }
        return place
    }
    private var mediaFeatureID: String? { settings.noGoogle ? nil : mediaPlace.featureId }
    private var hasReviews: Bool {
        !settings.noGoogle && (mediaPlace.reviewCount ?? 1) > 0
            && (mediaFeatureID != nil || (mediaPlace.source == "google" && mediaPlace.rating != nil))
    }
    private var reviews: [PlaceReview]? {
        guard let id = mediaFeatureID else { return [] }
        return reviewResult?.featureID == id ? reviewResult?.rows : nil
    }
    private var photos: [String] {
        guard !settings.noGoogle else { return place.photoUrls.filter { !PhotoStrip.isGoogle($0) } }
        let gallery = galleryResult?.featureID == mediaFeatureID ? galleryResult?.urls ?? [] : []
        let reviewPhotos = (reviews ?? []).flatMap(\.photos)
        var seen = Set<String>()
        return (place.photoUrls + mediaPlace.photoUrls + gallery + reviewPhotos).filter { url in
            let key = PhotoStrip.isGoogle(url) ? url.components(separatedBy: "=w").first ?? url : url
            return seen.insert(key).inserted
        }
    }
    private var attribution: String {
        if place.source == "google" { return "Place details from Google Maps" }
        if mediaPlace.source == "google" { return "Map data © OpenStreetMap contributors · Photos and reviews from Google Maps" }
        return "Map data © OpenStreetMap contributors"
    }

    private func matchMediaPlace() async {
        guard !settings.noGoogle, place.featureId == nil, place.source == "osm",
              place.category?.caseInsensitiveCompare(place.name) != .orderedSame else { return }
        do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
        let matches = (try? await GoogleClient.shared.search(place.name, center: place.location, spanMeters: 2_000, pages: 1)) ?? []
        guard !Task.isCancelled, !settings.noGoogle else { return }
        let target = matches.filter {
            $0.featureId != nil && $0.name.caseInsensitiveCompare(place.name) == .orderedSame
                && $0.location.distance(to: place.location) <= 85
        }.min { $0.location.distance(to: place.location) < $1.location.distance(to: place.location) }
        if let target { related = (place.id, target) }
    }

    /** A bus stop or a station, which gets a live departure board. */
    private var isStop: Bool {
        let text = ((place.category ?? "") + " " + place.name).lowercased()
        return ["station", "bus stop", "stop ", "transit", "subway", "metro", "tram", "light rail", "terminal", "depot"]
            .contains { text.contains($0) }
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let s = driveSeconds {
                    Label("\(Fmt.duration(s)) drive", systemImage: "car.fill")
                        .font(.body.weight(.bold))
                        .padding(.horizontal, 16).frame(height: 52)
                        .background(Capsule().stroke(Color.secondary.opacity(0.35)))
                }
                if let tel = telURL(place.phone) {
                    PillButton(title: "Call", icon: "phone.fill") { openURL(tel) }
                }
                if let web = webURL(place.website) {
                    PillButton(title: "Website", icon: "globe") { openURL(web) }
                }
                if place.id == model.settings.parking?.id {
                    PillButton(title: "Clear spot", icon: "xmark.circle") { model.clearParking() }
                }
                Menu {
                    if model.settings.home?.id == place.id {
                        Button(role: .destructive) { model.setHome(nil) } label: { Label("Remove home", systemImage: "house.slash") }
                    } else {
                        Button { model.setHome(place) } label: { Label("Set as home", systemImage: "house") }
                    }
                    if model.settings.work?.id == place.id {
                        Button(role: .destructive) { model.setWork(nil) } label: { Label("Remove work", systemImage: "briefcase") }
                    } else {
                        Button { model.setWork(place) } label: { Label("Set as work", systemImage: "briefcase") }
                    }
                    Button { UIPasteboard.general.string = String(format: "%.6f, %.6f", place.location.lat, place.location.lng) } label: {
                        Label("Copy coordinates", systemImage: "doc.on.doc")
                    }
                    if let a = place.address {
                        Button { UIPasteboard.general.string = [place.name, a].joined(separator: ", ") } label: {
                            Label("Copy address", systemImage: "doc.on.clipboard")
                        }
                    }
                    Section("Open in") {
                        ForEach(OtherApp.allCases, id: \.self) { app in
                            Button { openURL(app.url(for: place)) } label: { Label(app.rawValue, systemImage: app.icon) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                        Text("More").font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .foregroundColor(Vela.onTonal(scheme))
                    .background(Capsule().fill(Vela.tonal(scheme)))
                }
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = place.editorialSummary { Text(s).font(.body).copyable(s) }
            if let a = place.address { InfoRow(icon: "mappin.and.ellipse", text: a).copyable(a) }
            if isStop { DepartureBoard(place: place) }
            if !place.hours.isEmpty { hours.copyable(place.hours.joined(separator: "\n")) }
            if let phone = place.phone {
                InfoRow(icon: "phone", text: phone)
                    .onTapGesture { if let u = telURL(phone) { openURL(u) } }
                    .copyable(phone)
            }
            if let site = place.website {
                InfoRow(icon: "globe", text: site.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                    .onTapGesture { if let u = webURL(site) { openURL(u) } }
                    .copyable(site)
            }
            if hasReviews {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reviews").font(.headline)
                    if let reviews, !reviews.isEmpty {
                        ForEach(Array(reviews.prefix(3).enumerated()), id: \.offset) { _, review in
                            PlaceReviewCard(review: review)
                        }
                    } else if let preview = mediaPlace.featuredReview {
                        Text("“\(preview)”").font(.subheadline)
                    }
                    Button("See more reviews") { tab = 2 }.font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var hours: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "clock").frame(width: 22).foregroundColor(.secondary)
                VStack(alignment: .leading) {
                    StatusText(place: place).font(.subheadline)
                    if !hoursOpen, let today = place.hours.first {
                        Text(today).font(.subheadline).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: hoursOpen ? "chevron.up" : "chevron.down").foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { hoursOpen.toggle() } }
            if hoursOpen {
                ForEach(place.hours, id: \.self) { h in
                    let parts = h.split(separator: ":", maxSplits: 1).map(String.init)
                    HStack(alignment: .top) {
                        Text(parts.first ?? h).font(.subheadline).frame(width: 100, alignment: .leading)
                        Text(parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "").font(.subheadline)
                    }
                    .padding(.leading, 36)
                }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(place.about, id: \.self) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title).font(.headline)
                    ForEach(section.items, id: \.self) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark").font(.caption).foregroundColor(.secondary)
                            Text(item).font(.subheadline)
                        }
                    }
                }
            }
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).frame(width: 22).foregroundColor(.secondary)
            Text(text).font(.subheadline).foregroundColor(.primary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SavedView: View {
    @ObservedObject var settings: AppSettings
    let onPick: (Place) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Place?
    @State private var newName = ""

    var body: some View {
        NavigationView {
            Group {
                if settings.saved.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bookmark").font(.largeTitle).foregroundColor(.secondary)
                        Text("No saved places yet").font(.headline)
                        Text("Tap the bookmark on a place to save it here.").font(.subheadline).foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(settings.saved) { p in
                            Button { onPick(p) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).foregroundColor(.primary)
                                    if let a = p.address { Text(a).font(.caption).foregroundColor(.secondary) }
                                }
                            }
                            .contextMenu {
                                Button { startRename(p) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { settings.saved.removeAll { $0.id == p.id } } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button { startRename(p) } label: { Label("Rename", systemImage: "pencil") }.tint(Vela.routeBlue)
                            }
                        }
                        .onDelete { settings.saved.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") {
                    if let p = renaming { settings.renameSaved(p.id, to: newName) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private extension SavedView {
    func startRename(_ p: Place) {
        newName = p.name
        renaming = p
    }
}

/** Next departures at a stop from Transitous, refreshed every 30 seconds while it's open. */
struct DepartureBoard: View {
    let place: Place
    @State private var board: (stop: String, departures: [Transitous.Departure])?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Departures").font(.headline)
            if let b = board {
                ForEach(Array(b.departures.prefix(8).enumerated()), id: \.offset) { _, d in
                    HStack(spacing: 10) {
                        LineChip(leg: TransitLeg(isWalk: false, mode: d.mode, line: d.line, color: d.color, textColor: d.textColor))
                        Text(d.headsign).font(.subheadline).lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(countdown(d.time)).font(.subheadline.weight(.semibold))
                                .foregroundColor(d.delayMinutes != nil ? Vela.open : .primary)
                            if let late = d.delayMinutes, late != 0 {
                                Text(late > 0 ? "\(late) min late" : "\(-late) min early").font(.caption2)
                                    .foregroundColor(late > 0 ? Vela.closed : Vela.open)
                            }
                        }
                    }
                }
                Text("Live times in green · from Transitous").font(.caption).foregroundColor(.secondary)
            } else if loaded {
                Text("No departures found here.").font(.subheadline).foregroundColor(.secondary)
            } else {
                HStack { ProgressView(); Text("Loading departures…").foregroundColor(.secondary) }
            }
        }
        .task(id: place.id) {
            while !Task.isCancelled {
                let b = await Transitous.departures(near: place.location)
                if Task.isCancelled { return }
                if b != nil || !loaded { board = b }
                loaded = true
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func countdown(_ t: Date) -> String {
        let mins = Int((t.timeIntervalSinceNow / 60).rounded())
        if mins <= 0 { return "Now" }
        if mins < 60 { return "\(mins) min" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: t)
    }
}

/** Other map apps a place can be handed to, by their web links (no app list permission needed). */
enum OtherApp: String, CaseIterable {
    case google = "Google Maps"
    case waze = "Waze"
    case apple = "Apple Maps"

    var icon: String {
        switch self {
        case .google: return "map"
        case .waze: return "car"
        case .apple: return "applelogo"
        }
    }

    func url(for p: Place) -> URL {
        let ll = "\(p.location.lat),\(p.location.lng)"
        // "&", "+" and "=" would cut the name short ("M&S" became "M").
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let name = p.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        switch self {
        case .google: return p.shareURL ?? URL(string: "https://www.google.com/maps/search/?api=1&query=\(ll)")!
        case .waze: return URL(string: "https://waze.com/ul?ll=\(ll)&navigate=yes")!
        case .apple: return URL(string: "https://maps.apple.com/?ll=\(ll)&q=\(name)")!
        }
    }
}

/**
 * A place's Google reviews inside Kite (GitHub #70): stars, who, when and what they said, the ones
 * Google Maps shows first. When Google won't list them, a button opens them on Google in Kite.
 */
struct ReviewsList: View {
    let place: Place
    let reviews: [PlaceReview]?
    @State private var web: URL?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let rating = place.rating {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%.1f", rating)).font(.system(size: 40, weight: .heavy))
                    VStack(alignment: .leading, spacing: 2) {
                        Stars(rating: rating, size: 16)
                        if let n = place.reviewCount { Text("\(n.formatted()) reviews on Google").font(.subheadline).foregroundColor(.secondary) }
                    }
                }
            }
            if let reviews {
                ForEach(Array(reviews.enumerated()), id: \.offset) { _, review in
                    PlaceReviewCard(review: review)
                }
            } else {
                HStack(spacing: 10) { ProgressView(); Text("Loading reviews…").foregroundColor(.secondary) }
            }
            if reviews?.isEmpty != false, let r = place.featuredReview {
                Text("“\(r)”").font(.subheadline)
            } else if reviews?.isEmpty == true {
                Text("No reviews returned for this place.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let url = GoogleReviews.webURL(place) {
                Button { web = url } label: {
                    Label(reviews?.isEmpty == false ? "More reviews on Google" : "Read the reviews on Google", systemImage: "text.bubble")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundColor(Vela.onTonal(scheme))
                        .background(Capsule().fill(Vela.tonal(scheme)))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $web) { url in
            SafariView(url: url).ignoresSafeArea()
        }
    }
}

private struct PlaceReviewCard: View {
    let review: PlaceReview
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(review.author).font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                if let rating = review.rating { Stars(rating: Double(rating), size: 12) }
                if let time = review.time { Text(time).font(.caption).foregroundStyle(.secondary) }
            }
            if let text = review.text { Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            if !review.photos.isEmpty { PhotoStrip(urls: review.photos, height: 96, opensViewer: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Vela.chip(scheme), in: RoundedRectangle(cornerRadius: 12))
    }
}

/** A web page inside Kite (Google's reviews), with Safari's own Done button. */
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}
