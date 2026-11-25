import SwiftUI
import VelaCore

struct RouteStopsSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var submitted: String?
    @State private var category: String?
    @State private var searching = false
    @State private var expanded: String?
    @State private var size: PresentationDetent = .medium
    @State private var detours: [String: Double] = [:]
    @State private var fuelQuotes: [String: FuelPrices.Quote] = [:]

    private struct SearchInput: Equatable {
        let text: String
        let submitted: Bool
        let category: Bool
        let routeID: UUID?
        let useGoogle: Bool
    }

    private let categories = [
        ("Gas stations", "fuelpump.fill", "gas station"), ("EV charging", "bolt.car.fill", "ev charging station"),
        ("Coffee", "cup.and.saucer.fill", "coffee"), ("Food", "fork.knife", "restaurants"),
        ("Supermarkets", "cart.fill", "supermarket"), ("Toilets", "toilet.fill", "toilets"),
        ("Parking", "parkingsign", "parking"), ("Pharmacy", "cross.case.fill", "pharmacy")
    ]

    private var route: Route? { model.nav?.route ?? model.directions?.route }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var input: SearchInput {
        SearchInput(text: trimmedQuery, submitted: submitted == trimmedQuery, category: category == trimmedQuery,
                    routeID: route?.id, useGoogle: !settings.noGoogle)
    }
    private var savedPlaces: [Place] {
        [settings.home, settings.work].compactMap { $0 } + Array(settings.saved.prefix(12))
    }

    var body: some View {
        NavigationStack {
            List {
                if let selected = model.visibleStopResults.first(where: { $0.id == model.selectedStopResult?.id }) {
                    Button("All results") {
                        model.selectedStopResult = nil
                        size = .large
                    }
                    result(selected, highlighted: true)
                } else {
                    searchChoices
                    if searching {
                        HStack(spacing: 10) { ProgressView(); Text("Looking along your route…") }
                            .foregroundStyle(.secondary)
                    }
                    if !model.displayedStopResults.isEmpty {
                        Section("Stops along the route") {
                            Toggle("Open now", isOn: $model.onlyOpenStopResults)
                            ForEach(model.visibleStopResults) { stop in result(stop) }
                        }
                    }
                    if !trimmedQuery.isEmpty, !searching, model.visibleStopResults.isEmpty {
                        Text(model.onlyOpenStopResults ? "No places with confirmed opening status right now." : "Nothing found near this part of the route.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .id(model.selectedStopResult?.id)
            .kiteList()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a stop on the route")
            .onSubmit(of: .search) { submitted = trimmedQuery }
            .onChange(of: query) { value in
                if value != category { category = nil }
                if value != submitted { submitted = nil }
            }
            .navigationTitle("Add stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large], selection: $size)
        .modifier(RouteStopMapInteraction())
        .onAppear {
            model.openStopSearch()
            if DemoScript.step == "route-stops", query.isEmpty {
                query = "Kaufland"
                submitted = query
            }
        }
        .task(id: input) { await search(input) }
    }

    @ViewBuilder private var searchChoices: some View {
        if trimmedQuery.isEmpty {
            Section("Search along route") {
                ForEach(categories, id: \.0) { choice in
                    Button {
                        category = choice.2
                        submitted = choice.2
                        query = choice.2
                    } label: { Label(choice.0, systemImage: choice.1) }
                }
            }
            if model.nav == nil {
                Section("Your places") {
                    Button {
                        model.routePointRole = .stop
                        dismiss()
                    } label: { Label("Choose on map", systemImage: "map") }
                    ForEach(savedPlaces) { place in
                        Button {
                            model.addStop(place)
                            dismiss()
                        } label: { Label(place.name, systemImage: "bookmark") }
                    }
                }
            }
        } else if model.nav == nil, submitted != trimmedQuery {
            Button { submitted = trimmedQuery } label: { Label("Search the entire route", systemImage: "magnifyingglass") }
        }
    }

    private func result(_ stop: RouteStopCandidate, highlighted: Bool = false) -> some View {
        RouteStopResultCard(stop: stop, detour: detours[stop.id], fuel: fuelQuotes[stop.id],
                            expanded: highlighted || expanded == stop.id,
                            canAdd: model.nav?.canAddStop(stop.place) ?? ((model.directions?.stops.count ?? 0) < 8),
                            toggle: { expanded = expanded == stop.id ? nil : stop.id },
                            showOnMap: highlighted ? nil : { selectOnMap(stop) },
                            add: {
            if let nav = model.nav { nav.addStop(stop.place, routeMeters: stop.routeMeters) }
            else { model.addStop(stop.place, routeMeters: stop.routeMeters) }
            dismiss()
        })
    }

    private func search(_ input: SearchInput) async {
        model.selectedStopResult = nil
        model.displayedStopResults = []
        expanded = nil
        detours = [:]
        fuelQuotes = [:]
        searching = input.text.count >= 2
        guard searching else { return }
        if !input.submitted {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
        }
        let nav = model.nav
        let plan = model.directions
        let route = self.route
        let here = plan?.origin?.location ?? model.userLatLng ?? model.viewport.center
        let origin = plan?.reversed == true ? plan?.destination.location ?? here : here
        let destination = nav?.destination ?? plan?.destination
        let fallback = [origin, plan?.reversed == true ? here : destination?.location ?? origin]
        let corridor = RouteStopSearch(line: route?.polyline ?? fallback, origin: origin,
                                       progress: nav.map { $0.progress?.alongMeters ?? 0 })
        let excluded = (nav?.stops ?? plan?.stops ?? []) + [destination].compactMap { $0 }
        let draft = nav == nil && !input.submitted
        let results = await corridor.search(input.text, named: !input.category, useGoogle: input.useGoogle,
                                            excluding: excluded, draft: draft)
        guard !Task.isCancelled else { return }
        model.displayedStopResults = draft ? Array(results.prefix(14)) : results
        searching = false
        if input.submitted, !results.isEmpty {
            nav?.following = false
            let locations = nav == nil ? results.map(\.place.location) : results.prefix(7).map(\.place.location)
            model.frame(locations, bottomFraction: 0.45, top: 65)
        }
        async let prices = FuelPrices.ukQuotes(for: results.map(\.place))
        if route?.mode == .drive {
            let computed = await corridor.drivingDetours(results)
            if !Task.isCancelled { detours = computed }
        }
        let quotes = await prices
        if !Task.isCancelled { fuelQuotes = quotes }
    }

    private func selectOnMap(_ stop: RouteStopCandidate) {
        model.selectedStopResult = stop
        model.nav?.following = false
        size = .medium
        model.frame([stop.place.location], bottomFraction: 0.45, top: 65)
    }
}

private struct RouteStopMapInteraction: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) { content.presentationBackgroundInteraction(.enabled(upThrough: .medium)) }
        else { content }
    }
}

private struct RouteStopResultCard: View {
    let stop: RouteStopCandidate
    let detour: Double?
    let fuel: FuelPrices.Quote?
    let expanded: Bool
    let canAdd: Bool
    let toggle: () -> Void
    let showOnMap: (() -> Void)?
    let add: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme
    @State private var gallery: [String]?

    private var googleFuel: String? { settings.noGoogle ? nil : stop.place.fuelPrice }

    var body: some View {
        let place = stop.place
        VStack(alignment: .leading, spacing: 9) {
            Button(action: toggle) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(place.name).font(.headline).foregroundStyle(.primary)
                        StatusText(place: place).font(.caption)
                        if let price = fuel?.labels.first ?? googleFuel {
                            Label(price, systemImage: "fuelpump").font(.caption).foregroundStyle(.secondary)
                        }
                        if let ahead = stop.ahead { Text("\(Fmt.distance(ahead)) ahead").font(.caption) }
                        if let detour {
                            Text(DetourText.short(detour)).font(.caption.weight(.semibold)).foregroundStyle(DetourText.color(detour))
                        } else if stop.routeMeters != nil, stop.offset > 100 {
                            Text("About \(Fmt.distance(stop.offset)) from the route").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if showOnMap != nil { Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                details
            }
            HStack {
                if let showOnMap { Button("Show on map", action: showOnMap).buttonStyle(.bordered) }
                Button("Add stop", action: add).buttonStyle(.borderedProminent).disabled(!canAdd)
            }
        }
        .padding(.vertical, 6)
        .task(id: expanded && !settings.noGoogle ? place.featureId : nil) {
            guard expanded, !settings.noGoogle, place.photoUrls.count < 4, let id = place.featureId, gallery == nil else { return }
            let photos = await GoogleClient.shared.placeGallery(featureID: id)
            if !Task.isCancelled { gallery = Array(photos.prefix(4)) }
        }
    }

    private var details: some View {
        let place = stop.place
        let photos = place.photoUrls + (settings.noGoogle ? [] : gallery ?? [])
        return VStack(alignment: .leading, spacing: 9) {
            if !photos.isEmpty {
                PhotoStrip(urls: Array(photos.prefix(4)), height: 104, opensViewer: true)
                if !settings.noGoogle, photos.contains(where: PhotoStrip.isGoogle) {
                    Text("Photos from Google Maps").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let summary = place.editorialSummary { Text(summary).font(.subheadline).lineLimit(4) }
            if FuelPrices.isStation(place) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Fuel prices", systemImage: "fuelpump").font(.subheadline.weight(.semibold))
                    Text(fuel?.labels.joined(separator: " · ") ?? googleFuel ?? "Price unavailable").font(.subheadline)
                    if let fuel {
                        Text("UK Fuel Finder · \(fuel.updated.formatted(date: .abbreviated, time: .omitted))")
                        Text("Contains public sector information licensed under the Open Government Licence v3.0.")
                    } else if googleFuel != nil {
                        Text("Reported by Google Maps")
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let address = place.address { InfoRow(icon: "mappin.and.ellipse", text: address) }
            if !place.hours.isEmpty {
                DisclosureGroup("Opening hours") {
                    ForEach(place.hours, id: \.self) { Text($0).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                }.font(.subheadline)
            }
            if let phone = telURL(place.phone) { Link("Call", destination: phone).font(.subheadline) }
            if let web = webURL(place.website) { Link("Website", destination: web).font(.subheadline) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Vela.ground(scheme), in: RoundedRectangle(cornerRadius: 12))
    }
}
