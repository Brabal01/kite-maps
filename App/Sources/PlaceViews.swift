import MapKit
import SwiftUI
import UIKit
import VelaCore

struct PlaceHeader: View {
    @ObservedObject var model: AppModel
    let place: Place
    var journey = false
    @ObservedObject private var settings = AppSettings.shared
    @State private var showReviews = false
    @State private var showGallery = false
    @Environment(\.colorScheme) private var scheme

    private var canShowReviews: Bool {
        !settings.noGoogle && (place.source == "google" || (place.reviewCount ?? 0) > 0 || place.featuredReview != nil)
    }

    private var canShowPhotos: Bool {
        place.photoUrls.contains(where: { !settings.noGoogle || !PhotoStrip.isGoogle($0) })
            || (!settings.noGoogle && place.source == "google")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KiteSpace.s) {
            HStack(alignment: .top, spacing: KiteSpace.xs) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(KiteText.title(26))
                        .foregroundColor(KiteColor.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .copyable(place.name, below: true)
                    PlaceMetaLine(place: place, here: model.userLatLng)
                    StatusText(place: place).font(KiteText.caption())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KiteCircleButton(icon: "xmark", size: 38, label: "Close") {
                    withAnimation(KiteMotion.gentle) { model.closePlace() }
                }
            }

            HStack(spacing: KiteSpace.xs) {
                action(icon: settings.isSaved(place) ? "bookmark.fill" : "bookmark",
                       title: settings.isSaved(place) ? "Saved" : "Save",
                       tint: settings.isSaved(place) ? KiteColor.accentText : KiteColor.ink) {
                    settings.toggleSaved(place)
                }
                if let url = place.shareURL {
                    ShareLink(item: url) {
                        actionLabel(icon: "square.and.arrow.up", title: "Share", tint: KiteColor.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share")
                }
                if canShowReviews {
                    action(icon: "star.bubble", title: "Reviews", tint: KiteColor.ink) { showReviews = true }
                }
                if canShowPhotos {
                    action(icon: "photo.on.rectangle.angled", title: "Photos", tint: KiteColor.ink) { showGallery = true }
                }
            }
            .sheet(isPresented: $showReviews) { PlaceMediaSheet(place: place).kiteType() }
            .sheet(isPresented: $showGallery) { PlaceMediaSheet(place: place, photos: true).kiteType() }

            if journey {
                Button { model.addJourneyStop(place) } label: {
                    Label("Add stop", systemImage: "plus.circle.fill")
                }
                .buttonStyle(KitePrimaryButtonStyle(height: 54))
                .disabled(model.addingJourneyStop)
            } else {
                directions
            }
        }
        .padding(.horizontal, KiteSpace.m)
        .padding(.bottom, KiteSpace.xs)
    }

    private var directions: some View {
        HStack(spacing: KiteSpace.xs) {
            Button { model.openDirections(to: place) } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .buttonStyle(KitePrimaryButtonStyle(height: 54))
            Button {
                model.openDirections(to: place)
                model.autoStart = true
            } label: {
                Label("Go", systemImage: "location.north.fill")
                    .font(KiteText.headline(18))
                    .foregroundColor(KiteColor.accentText)
                    .frame(minWidth: 92, minHeight: 54)
                    .background(
                        RoundedRectangle(cornerRadius: KiteRadius.button, style: .continuous)
                            .fill(KiteColor.accentSoft)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start driving now")
        }
        .padding(.top, 2)
    }

    private func action(icon: String, title: String, tint: Color, run: @escaping () -> Void) -> some View {
        Button(action: run) { actionLabel(icon: icon, title: title, tint: tint) }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text(title))
    }

    private func actionLabel(icon: String, title: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
            Text(L10n.text(title)).font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundColor(tint)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(KiteColor.fill)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PlaceBody: View {
    @ObservedObject var model: AppModel
    let place: Place
    @State private var tab = 0
    @State private var hoursOpen = false
    /** Driving time from here, shown on the Directions button like Google Maps. */
    @State private var driveSeconds: Double?
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            SheetTopMarker()
            VStack(alignment: .leading, spacing: 14) {
                actions
                PhotoStrip(urls: place.photoUrls, height: 140, opensViewer: true, streetView: place)
                if hasAbout {
                    Picker("", selection: $tab) {
                        Text("Overview").tag(0)
                        Text("About").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                if tab == 0 { overview } else { about }
                let source = place.source == "apple" ? "Place details from Apple Maps"
                    : place.source == "google" ? "Place details from Google Maps" : "Map data © OpenStreetMap contributors"
                Text(L10n.text(source))
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 80)
        }
        .sheetScroll()
        .task(id: place.id) { await loadDriveTime() }
    }

    private func loadDriveTime() async {
        driveSeconds = nil
        guard !model.hasActiveJourney else { return }
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
                    Label(L10n.format("%@ drive", String(describing: Fmt.duration(s))), systemImage: "car.fill")
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
            let coords = String(format: "%.6f, %.6f", place.location.lat, place.location.lng)
            InfoRow(icon: "scope", text: coords).copyable(coords)
            if let r = place.featuredReview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review").font(.headline)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "person.crop.circle.fill").font(.title2).foregroundColor(.secondary)
                        Text("“\(r)”").font(.subheadline)
                    }
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
    @State private var board: [Transitous.Departure]?
    @State private var selectedPlatform: String?
    @State private var selectedTrip: DepartureSelection?
    @State private var refreshedAt: Date?
    @State private var failed = false

    private struct DepartureSelection: Identifiable {
        let id: String
        let departure: Transitous.Departure
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Departures").font(.headline)
            if let board {
                let platforms = Array(Set(board.compactMap(\.platform)))
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                if !platforms.isEmpty {
                    Picker(L10n.text("Filter by platform"), selection: $selectedPlatform) {
                        Text(L10n.text("All platforms")).tag(String?.none)
                        ForEach(platforms, id: \.self) { platform in
                            Text(L10n.format("Platform %@", platform)).tag(Optional(platform))
                        }
                    }
                    .pickerStyle(.menu)
                }
                let shown = board.filter { selectedPlatform == nil || $0.platform == selectedPlatform }
                if shown.isEmpty {
                    Text("No departures found here.").font(.subheadline).foregroundColor(.secondary)
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(shown.prefix(20).enumerated()), id: \.offset) { _, departure in
                            if let id = departure.tripID {
                                Button { selectedTrip = DepartureSelection(id: id, departure: departure) } label: {
                                    row(departure, now: context.date, isLink: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                row(departure, now: context.date, isLink: false)
                            }
                        }
                    }
                }
                if let refreshedAt {
                    Text(L10n.format("Transitous · updated %@", refreshedAt.formatted(date: .omitted, time: .shortened)))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if failed {
                Text(L10n.text("Couldn't refresh departures.")).font(.subheadline).foregroundColor(.secondary)
            } else if board == nil {
                HStack { ProgressView(); Text("Loading departures…").foregroundColor(.secondary) }
            }
        }
        .task(id: place.placeId ?? place.id) {
            while !Task.isCancelled {
                do {
                    let departures: [Transitous.Departure]
                    if place.source == "transitous", let id = place.placeId {
                        departures = try await Transitous.departures(stopID: id)
                    } else {
                        departures = await Transitous.departures(near: place.location)?.departures ?? []
                    }
                    try Task.checkCancellation()
                    board = departures
                    failed = false
                    refreshedAt = Date()
                    if let platform = selectedPlatform, !departures.contains(where: { $0.platform == platform }) {
                        selectedPlatform = nil
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    failed = true
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .sheet(item: $selectedTrip) { selection in
            TransitDepartureDetail(tripID: selection.id, departure: selection.departure)
        }
    }

    private func row(_ d: Transitous.Departure, now: Date, isLink: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                LineChip(leg: TransitLeg(isWalk: false, mode: d.mode, line: d.line, color: d.color,
                                         textColor: d.textColor, lineIdentity: d.identity))
                Text(d.headsign).font(.subheadline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(d.time, format: .dateTime.hour().minute())
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                    if d.isCancelled {
                        Text(L10n.text("Cancelled departure")).font(.caption).foregroundColor(Vela.closed)
                    } else if failed || d.time < now.addingTimeInterval(-60) {
                        Text(L10n.text("Last known")).font(.caption).foregroundColor(.secondary)
                    } else {
                        let minutes = max(0, Int(ceil(d.time.timeIntervalSince(now) / 60)))
                        Text(minutes == 0 ? L10n.text("Now") : "\(minutes) min")
                            .font(.caption).foregroundColor(d.isRealtime ? Vela.open : .secondary)
                    }
                }
                if isLink {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 8) {
                if let platform = d.platform {
                    if d.isRealtime, let scheduled = d.scheduledTrack, scheduled != platform {
                        Label(L10n.format("Platform change: %@ → %@", scheduled, platform), systemImage: "arrow.left.arrow.right")
                            .foregroundColor(Vela.closed)
                    } else {
                        Label(L10n.format("Platform %@", platform), systemImage: "signpost.right")
                    }
                }
                if let code = d.stopCode, code != d.platform {
                    Text(L10n.format("Stop code %@", code))
                }
                if d.isRealtime && !d.isCancelled, let delay = d.delayMinutes, delay != 0, !failed {
                    Text(L10n.format(delay > 0 ? "%@ min late" : "%@ min early", String(abs(delay))))
                        .foregroundColor(delay > 0 ? Vela.closed : Vela.open)
                }
                Spacer(minLength: 0)
                Text(L10n.text(d.isRealtime ? (failed ? "Live data stale" : "Live") : "Scheduled"))
                    .foregroundColor(d.isRealtime && !failed ? Vela.open : .secondary)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct TransitDepartureDetail: View {
    let tripID: String
    let departure: Transitous.Departure
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var detail: Transitous.TripDetail?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        LineChip(leg: TransitLeg(isWalk: false, mode: departure.mode, line: departure.line,
                                                 lineIdentity: departure.identity))
                        Text(detail?.leg.headsign ?? departure.headsign).font(.title3.weight(.semibold))
                    }
                    if let detail {
                        if detail.cancelled || departure.isCancelled {
                            Label(L10n.text("Cancelled departure"), systemImage: "exclamationmark.circle")
                                .foregroundColor(Vela.closed)
                        }
                        if failed {
                            Text(L10n.text("Couldn't refresh this trip.")).foregroundColor(.secondary)
                        }
                        TimelineView(.periodic(from: .now, by: 5)) { context in
                            progress(detail, now: context.date)
                        }
                        Text(L10n.text("Trip stops")).font(.headline)
                        let stops = detail.calls
                        ForEach(stops.indices, id: \.self) { index in stopRow(stops[index]) }
                        ForEach(detail.leg.serviceAlerts, id: \.self) { alert in
                            Label(alert, systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                        Text("Transitous").font(.caption).foregroundColor(.secondary)
                    } else if failed {
                        Label(L10n.text("Couldn't refresh this trip."), systemImage: "wifi.exclamationmark")
                    } else {
                        ProgressView(L10n.text("Loading trip…"))
                    }
                }
                .padding(16)
            }
            .navigationTitle(L10n.text("Trip details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Close")) { dismiss() }
                }
            }
        }
        .task(id: settings.gtfsRealtimeURL) {
            while !Task.isCancelled {
                do {
                    async let feed = TransitRealtime.fetch(settings.gtfsRealtimeURL)
                    var latest = try await Transitous.tripDetail(tripID: tripID)
                    if let realtime = await feed {
                        latest.trip = TransitRealtime.apply(realtime, to: [latest.trip]).first ?? latest.trip
                    }
                    try Task.checkCancellation()
                    detail = latest
                    failed = false
                } catch {
                    guard !Task.isCancelled else { return }
                    failed = true
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func stopRow(_ call: TransitCall) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(call.name).font(.subheadline.weight(.medium))
                if let platform = call.track {
                    Text(L10n.format("Platform %@", platform)).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if call.skipped {
                Text(L10n.text("Stop skipped")).font(.caption).foregroundColor(Vela.closed)
            } else if let time = call.departure ?? call.arrival {
                Text(time, format: .dateTime.hour().minute()).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private func progress(_ detail: Transitous.TripDetail, now: Date) -> some View {
        let position = departure.isCancelled || failed ? nil : detail.position(at: now)
        return VStack(alignment: .leading, spacing: 6) {
            if !detail.geometry.isEmpty || !detail.stops.isEmpty || position != nil {
                TripDetailMap(detail: detail, vehicle: position?.location, isGPS: position?.isGPS == true)
                    .frame(height: 235)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if let position {
                Label(L10n.text(position.isGPS ? "Live GPS position" : "Estimated vehicle position"),
                      systemImage: position.isGPS ? "location.fill" : "clock")
                    .foregroundColor(position.isGPS ? .blue : .orange)
            } else {
                Text(L10n.text("Vehicle position unavailable")).foregroundColor(.secondary)
            }
            if !detail.cancelled, !departure.isCancelled, !failed,
               let next = detail.calls.first(where: { !$0.skipped && ($0.arrival ?? $0.departure ?? .distantPast) > now }) {
                Text(L10n.format("Next stop: %@", next.name)).fontWeight(.semibold)
            }
            Text(L10n.text(detail.leg.isRealtime ? (failed ? "Live data stale" : "Live") : "Scheduled"))
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
    }

}

private struct TripDetailMap: UIViewRepresentable {
    let detail: Transitous.TripDetail
    let vehicle: LatLng?
    let isGPS: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        let shape = detail.geometry
        let locations = detail.stops.map(\.location)
        if coordinator.shape != shape || coordinator.stopLocations != locations {
            coordinator.shape = shape
            coordinator.stopLocations = locations
            coordinator.color = UIColor(hex: detail.leg.displayColor)
            map.removeOverlays(map.overlays)
            map.removeAnnotations(coordinator.stopPins)
            if shape.count >= 2 {
                map.addOverlay(MKPolyline(coordinates: shape.map(Self.coordinate), count: shape.count))
            }
            coordinator.stopPins = detail.stops.map { stop in
                let pin = MKPointAnnotation()
                pin.title = stop.call.name
                pin.coordinate = Self.coordinate(stop.location)
                return pin
            }
            map.addAnnotations(coordinator.stopPins)
            if !coordinator.fitted {
                let fitPoints = shape + locations
                if let first = fitPoints.first {
                    let rect = fitPoints.dropFirst().reduce(Self.mapRect(first)) { $0.union(Self.mapRect($1)) }
                    let fit = rect.insetBy(dx: -max(1800, rect.width * 0.10), dy: -max(1800, rect.height * 0.10))
                    map.setVisibleMapRect(fit, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 36, right: 24),
                                          animated: false)
                    coordinator.fitted = true
                }
            }
        }

        let pin = coordinator.vehiclePin
        if let vehicle {
            pin.title = L10n.text(isGPS ? "Live GPS position" : "Estimated vehicle position")
            coordinator.vehicleSymbol = detail.leg.transitMode.symbol
            coordinator.isGPS = isGPS
            pin.coordinate = Self.coordinate(vehicle)
            if !map.annotations.contains(where: { $0 === pin }) {
                map.addAnnotation(pin)
            }
            if let marker = map.view(for: pin) as? MKMarkerAnnotationView {
                coordinator.styleVehicle(marker)
            }
            if !coordinator.fitted {
                map.setRegion(MKCoordinateRegion(center: pin.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200),
                              animated: false)
                coordinator.fitted = true
            }
        } else {
            map.removeAnnotation(pin)
        }
    }

    private static func coordinate(_ p: LatLng) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
    }

    private static func mapRect(_ p: LatLng) -> MKMapRect {
        MKMapRect(origin: MKMapPoint(coordinate(p)), size: MKMapSize(width: 1, height: 1))
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var shape: [LatLng] = []
        var stopLocations: [LatLng] = []
        var stopPins: [MKPointAnnotation] = []
        var color: UIColor = .systemBlue
        let vehiclePin = MKPointAnnotation()
        var vehicleSymbol = "tram.fill"
        var isGPS = false
        var fitted = false

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = color
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? MKPointAnnotation else { return nil }
            let marker = MKMarkerAnnotationView(annotation: point, reuseIdentifier: nil)
            marker.canShowCallout = true
            if point === vehiclePin {
                styleVehicle(marker)
            } else {
                marker.markerTintColor = color
                marker.glyphImage = UIImage(systemName: "circle.fill")
                marker.displayPriority = .defaultLow
            }
            return marker
        }

        func styleVehicle(_ marker: MKMarkerAnnotationView) {
            marker.markerTintColor = isGPS ? .systemBlue : .systemOrange
            marker.glyphImage = UIImage(systemName: vehicleSymbol)
            marker.displayPriority = .required
        }
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
