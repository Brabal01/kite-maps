import SwiftUI
import VelaCore

struct RouteEndpointPicker: View {
    @ObservedObject var model: AppModel
    let endpoint: RouteEndpoint
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searching = false

    var body: some View {
        NavigationView {
            List {
                Button { select(nil) } label: { Label("My location", systemImage: "location.fill") }
                    .disabled(model.userLatLng == nil)
                Button {
                    model.endpointOnMap = endpoint
                    dismiss()
                } label: { Label("Choose on map", systemImage: "mappin.and.ellipse") }
                if searching { ProgressView("Searching…") }
                ForEach(results) { place in
                    Button { select(place) } label: {
                        VStack(alignment: .leading) {
                            Text(place.name)
                            if let address = place.address { Text(address).font(.caption).foregroundColor(.secondary) }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search for a place or address")
            .task(id: query) {
                let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
                results = []
                searching = !term.isEmpty
                guard !term.isEmpty else { return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                let viewport = model.viewport
                let response = await PlaceSearch.search(term, center: model.userLatLng ?? viewport.center,
                                                       spanMeters: viewport.span, useGoogle: model.settings.googleSearchEnabled, language: L10n.isCzech ? "cs" : "en")
                guard !Task.isCancelled else { return }
                results = response.places
                searching = false
            }
            .navigationTitle(L10n.text(endpoint.rawValue))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func select(_ place: Place?) {
        model.selectEndpoint(endpoint, place: place)
        dismiss()
    }
}

struct MapEndpointPicker: View {
    @ObservedObject var model: AppModel
    let endpoint: RouteEndpoint

    var body: some View {
        ZStack {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(Vela.routeBlue)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            VStack {
                HStack {
                    Text("Move the map to choose a point").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Cancel") { model.endpointOnMap = nil }
                }
                .padding(14)
                .glass(RoundedRectangle(cornerRadius: 16))
                Spacer()
                PillButton(title: endpoint == .from ? "Set starting point" : "Set destination",
                           icon: "mappin.circle.fill", filled: true) { model.confirmEndpointOnMap() }
            }
            .padding(16)
        }
    }
}

struct ActiveTransitView: View {
    @ObservedObject var model: AppModel
    let journey: TransitJourney

    private var upcomingControls: [UpcomingRoadControl] {
        let line = journey.leg.path
        guard let fix = model.userLatLng, line.count >= 2, !model.nearbyControls.isEmpty else { return [] }
        let cumulative = Geo.cumulative(line)
        let along = Geo.project(fix, on: line, cumulative: cumulative).along
        return Array(model.nearbyControls.compactMap { control -> UpcomingRoadControl? in
            let point = Geo.project(control.location, on: line, cumulative: cumulative)
            let distance = point.along - along
            guard point.offset <= 15, (0...2_000).contains(distance) else { return nil }
            return UpcomingRoadControl(control: control, meters: (distance / 10).rounded() * 10)
        }.sorted { $0.meters < $1.meters }.prefix(6))
    }

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(journey.leg.isWalk ? L10n.text("Walking leg") : journey.leg.line.isEmpty ? L10n.text("Public transport") : journey.leg.line,
                          systemImage: vehicleSymbol(journey.leg.vehicle))
                        .font(.title2.weight(.bold))
                    Spacer()
                    Button("End") { model.endNavigation() }
                }
                HStack {
                    Text(L10n.format("Leg %@ of %@", String(journey.index + 1), String(journey.trip.legs.count)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.frameTransitJourney() } label: {
                        Label(L10n.isCzech ? "Přehled cesty" : "Trip overview",
                              systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                    }
                }
                if let direction = journey.leg.headsign { Text(L10n.format("Direction: %@", direction)).font(.headline) }
                if !journey.leg.isWalk {
                    HStack(spacing: 6) {
                        Text(journey.leg.isRealtime ? "Live data" : "Scheduled timetable")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(journey.leg.isRealtime ? Vela.open : .secondary)
                        if let vehicle = journey.leg.liveVehicle, let updated = vehicle.updated,
                           abs(Date().timeIntervalSince(updated)) <= 120 {
                            Text(L10n.format("Vehicle updated %@", updated.formatted(date: .omitted, time: .shortened)))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(L10n.isCzech ? "≈ Odhad podle jízdního řádu" : "≈ Timetable position estimate")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if journey.leg.isWalk {
                    Text(journey.leg.toName)
                    if journey.loadingWalk { ProgressView("Loading walking guidance…") }
                } else {
                    if !journey.boarded {
                        TransitCallRow(role: "Board at %@", name: journey.leg.fromName, stop: journey.leg.boardStop,
                                       time: journey.leg.depart, delay: journey.leg.delayMinutes)
                    }
                    TransitCallRow(role: "Get off at %@", name: journey.leg.toName, stop: journey.leg.exitStop,
                                   time: journey.leg.arrive, delay: journey.leg.arrivalDelayMinutes)
                }
                if !journey.leg.isWalk && !journey.boarded {
                    PillButton(title: "I'm on board", icon: "checkmark", filled: true) { model.boardTransit() }
                } else if !journey.loadingWalk {
                    PillButton(title: journey.leg.isWalk ? "Reached the next stop" : "I've got off",
                               icon: "arrow.right", filled: true) { model.advanceTransit() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glass(RoundedRectangle(cornerRadius: 20))
            RoadControlTimeline(controls: upcomingControls, emptyMessage: model.nearbyControlsStatus)
            Spacer()
        }
        .padding(16)
    }
}

struct JustDriveView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared

    private var nearbyEvents: [UpcomingRoadControl] {
        guard let here = model.userLatLng else { return [] }
        return Array(model.nearbyControls.filter { $0.kind.showsDuringDriving }.map {
            UpcomingRoadControl(control: $0, meters: here.distance(to: $0.location))
        }.sorted { $0.meters < $1.meters }.prefix(6))
    }

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading) {
                    Text("Just drive").font(.headline)
                    if let road = model.driveRoad { Text(road).font(.subheadline).lineLimit(1) }
                }
                Spacer()
                Button("End") { model.endJustDrive() }
            }
            .padding(14)
            .glass(RoundedRectangle(cornerRadius: 16))
            if !nearbyEvents.isEmpty {
                Text(L10n.text("Road events nearby")).font(.caption.weight(.semibold))
            }
            RoadControlTimeline(controls: nearbyEvents, emptyMessage: model.nearbyControlsStatus)
            Spacer()
            HStack(alignment: .bottom) {
                SpeedBadge(mps: model.driveSpeed, limitKmh: model.driveLimit)
                Spacer()
                VStack {
                    MapFab(icon: "car.fill", tint: Vela.routeBlue, size: 48) { model.endJustDrive() }
                        .accessibilityLabel("Just drive active")
                        .accessibilityAddTraits(.isSelected)
                    if !settings.noGoogle {
                        MapFab(icon: "car.2.fill", tint: settings.traffic ? Vela.routeBlue : .primary, size: 48) {
                            settings.traffic.toggle()
                        }
                        .accessibilityLabel(settings.traffic ? "Hide live traffic" : "Show live traffic")
                    }
                    MapFab(icon: "location.fill", size: 48) { model.centerOnUser() }
                        .accessibilityLabel("Centre on me")
                }
            }
        }
        .padding(16)
    }
}

struct JourneyPlaceSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let place = model.selected {
            VStack(spacing: 0) {
                PlaceHeader(model: model, place: place, journey: true)
                    .padding(.top, 20)
                PlaceBody(model: model, place: place)
            }
        }
    }
}

struct ArrivalParkingSheet: View {
    @ObservedObject var model: AppModel
    let destination: Place
    @State private var results: [Place]?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if let results {
                    if results.isEmpty { Text("No mapped public or visitor parking found nearby.") }
                    ForEach(results) { parking in
                        Button {
                            model.endNavigation()
                            model.openDirections(to: parking)
                            dismiss()
                        } label: {
                            Label(parking.name, systemImage: "parkingsign")
                        }
                    }
                } else { ProgressView("Looking for parking…") }
            }
            .navigationTitle("Nearby parking")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { results = await ArrivalMapData.parking(near: destination.location) }
        }
    }
}

struct TransitStartButton: View {
    let start: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: start) {
            Label("Start transit navigation", systemImage: "tram.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundColor(Vela.onAccent(scheme))
                .background(Capsule().fill(Vela.accent(scheme)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("start-transit")
    }
}
