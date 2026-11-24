import SwiftUI
import VelaCore

struct NearbyDeparturesView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var stops: [Transitous.Stop]?
    @State private var selected: Transitous.Stop?
    @State private var departures: [Transitous.Departure]?
    @State private var boardLoaded = false
    @State private var stopFailed = false
    @State private var reload = 0

    var body: some View {
        NavigationStack {
            List {
                if model.userLatLng == nil {
                    Text("Waiting for your location.").foregroundStyle(.secondary)
                } else if stopFailed {
                    Button("Retry nearby stops") { reload += 1 }
                } else if stops == nil {
                    ProgressView("Finding stops…")
                } else if let stops, stops.isEmpty {
                    Text("No stops within walking distance.").foregroundStyle(.secondary)
                } else if let stops {
                    Section {
                        Picker("Stop", selection: $selected) {
                            ForEach(stops) { Text($0.name).tag(Optional($0)) }
                        }
                        if let selected {
                            Button {
                                dismiss()
                                var place = Place(id: "transit:\(selected.id)", name: selected.name, location: selected.location,
                                                  source: "transit")
                                place.category = "Station"
                                model.select(place)
                            } label: { Label("Show stop on map", systemImage: "map") }
                        }
                    }
                    Section("Departures") {
                        if let departures, !departures.isEmpty {
                            ForEach(Array(departures.prefix(12).enumerated()), id: \.offset) { _, d in
                                HStack {
                                    LineChip(leg: TransitLeg(isWalk: false, mode: d.mode, line: d.line,
                                                             color: d.color, textColor: d.textColor))
                                    VStack(alignment: .leading) {
                                        Text(d.headsign)
                                        if let platform = d.platform { Text("Platform \(platform)").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(d.time, style: .time)
                                        Text(d.delayMinutes.map { $0 == 0 ? "On time" : "\($0) min" } ?? "Scheduled")
                                            .font(.caption).foregroundStyle(d.delayMinutes == nil ? Color.secondary : Color.green)
                                    }
                                }
                            }
                        } else if boardLoaded {
                            Text("No upcoming departures.").foregroundStyle(.secondary)
                        } else {
                            ProgressView("Loading departures…")
                        }
                    }
                }
            }
            .navigationTitle("Nearby departures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: "\(model.userLatLng != nil):\(reload)") {
            guard let at = model.userLatLng else { return }
            stopFailed = false
            let result = await Transitous.nearbyStops(at)
            guard !Task.isCancelled else { return }
            stopFailed = result == nil
            stops = result
            selected = result?.first
        }
        .task(id: selected) {
            departures = nil
            boardLoaded = false
            guard let selected else { return }
            while !Task.isCancelled {
                let now = await Transitous.departures(at: selected)
                guard !Task.isCancelled else { return }
                if let now { departures = now.filter { $0.time.timeIntervalSinceNow > -30 } }
                boardLoaded = true
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}

struct TransitJourneyView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var journey: TransitJourney
    @Environment(\.colorScheme) private var scheme
    @State private var overview = false
    @State private var confirmEnd = false
    @State private var access: [StationEntrance] = []
    @State private var showAccess = false

    private var gate: LatLng? {
        guard let leg = journey.leg, leg.vehicle == .metro || leg.vehicle == .train else { return nil }
        switch journey.phase {
        case .board: return leg.calls.first?.location ?? leg.path.first
        case .ride: return leg.calls.last?.location ?? leg.path.last
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !overview {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if let leg = journey.leg, !leg.isWalk { LineChip(leg: leg) }
                        Text(title).font(.headline)
                        Spacer()
                        if journey.phase != .complete {
                            Button { model.followTransit() } label: { Image(systemName: "location.fill") }
                                .accessibilityLabel("Recenter")
                        }
                    }
                    details
                }
                .padding(16).background(Vela.ground(scheme), in: RoundedRectangle(cornerRadius: 18))
                .padding([.horizontal, .top], 12)
            }
            Spacer()
            HStack {
                Button {
                    overview.toggle()
                    if overview { model.showTransitOverview() } else { model.followTransit() }
                } label: { Label(overview ? "Follow" : "Overview", systemImage: overview ? "location" : "map") }
                Spacer()
                if !access.isEmpty {
                    Button(journey.phase == .ride ? "Exits" : "Entrances") { showAccess = true }
                    Spacer()
                }
                Button(journey.phase == .complete ? "Done" : "End") {
                    if journey.phase == .complete { model.endTransit() } else { confirmEnd = true }
                }.foregroundStyle(.red)
            }
            .padding(16).background(Vela.ground(scheme), in: RoundedRectangle(cornerRadius: 18))
            .padding([.horizontal, .bottom], 12)
        }
        .confirmationDialog("End transit guidance?", isPresented: $confirmEnd) {
            Button("End guidance", role: .destructive) { model.endTransit() }
        }
        .sheet(isPresented: $showAccess) {
            NavigationStack {
                List(access) { pin in
                    Button {
                        showAccess = false
                        overview = true
                        journey.following = false
                        model.showSpot(pin.location)
                    } label: { Label(pin.title, systemImage: pin.wheelchair == true ? "figure.roll" : "door.left.hand.open") }
                }.navigationTitle("Station access")
            }
        }
        .task(id: gate) {
            access = []
            if let gate {
                let pins = await StationAccess.entrances(near: gate)
                if !Task.isCancelled { access = pins }
            }
        }
        .task(id: "\(journey.index):\(journey.phase)") {
            guard journey.phase != .complete else { return }
            let index = journey.index
            while !Task.isCancelled {
                var refreshed = await Transitous.refresh(journey.trip)
                guard !Task.isCancelled else { return }
                var position: Transitous.VehiclePosition?
                if let leg = refreshed?.legs[safe: index] ?? journey.leg, !leg.isWalk {
                    if let pid = await PidRealtime.update(leg, token: PidKeyStore.read()) {
                        var trip = refreshed ?? journey.trip
                        if trip.legs.indices.contains(index) {
                            trip.legs[index] = pid.leg
                            refreshed = trip
                        }
                        position = pid.position
                    }
                    if journey.phase == .ride, position == nil, refreshed?.legs[safe: index]?.cancelled != true {
                        position = await Transitous.livePosition(for: leg)
                    }
                }
                guard !Task.isCancelled else { return }
                journey.updateLive(refreshed, vehicle: position, at: index)
                model.mapTick += 1
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private var title: String {
        switch journey.phase {
        case .walk:
            let name = journey.leg?.toName ?? ""
            return "Walk to \(name.isEmpty || name == "END" ? "the destination" : name)"
        case .board: return "Board at \(journey.leg?.fromName ?? "the stop")"
        case .ride: return journey.exitWarning ? "Get ready to exit" : "On the way"
        case .complete: return "You have arrived"
        }
    }

    @ViewBuilder private var details: some View {
        switch journey.phase {
        case .walk:
            if let walk = journey.walking {
                if let next = walk.nextManeuver { Text(next.instruction).font(.title3.bold()) }
                if let progress = walk.progress {
                    Text("\(Fmt.distance(progress.remainingMeters)) · \(Fmt.duration(progress.remainingSeconds))")
                        .foregroundStyle(.secondary)
                }
            } else if journey.walkingUnavailable { Text("Follow the transfer path on the map.").foregroundStyle(.secondary) }
            else { ProgressView("Preparing walking guidance…") }
            Button("I've reached this stop") { model.advanceTransit() }.buttonStyle(.bordered)
        case .board:
            if let platform = journey.leg?.calls.first?.platform { Text("Platform \(platform)").font(.title3.bold()) }
            if let headsign = journey.leg?.headsign { Text("Toward \(headsign)") }
            if let depart = journey.leg?.calls.first?.departure ?? journey.leg?.depart {
                HStack { Text(depart, style: .time); delay }
            }
            if journey.leg?.cancelled == true { Text("Service cancelled").foregroundStyle(.red) }
            else { Button("I'm on board") { model.boardTransit() }.buttonStyle(.borderedProminent) }
        case .ride:
            if let next = journey.nextStop { Text("Next · \(next.name)").font(.title3.bold()) }
            if let exit = journey.leg?.toName { Text("Get off at \(exit)") }
            if let vehicle = journey.vehicle {
                Text(vehicle.isGPS ? "GPS vehicle position" : "Vehicle position estimated from live times")
                    .font(.caption).foregroundStyle(.secondary)
                if let occupancy = vehicle.occupancy { Text(occupancy.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption) }
            }
            delay
            Button("I've got off") { model.advanceTransit() }.buttonStyle(.bordered)
        case .complete:
            Text(journey.destination.name)
        }
        ForEach(journey.leg?.alerts.prefix(2).map { $0 } ?? [], id: \.self) { alert in
            Text(alert).font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var delay: some View {
        if let minutes = journey.leg?.delayMinutes {
            Text(minutes == 0 ? "On time" : minutes > 0 ? "\(minutes) min late" : "\(-minutes) min early")
                .font(.caption).foregroundStyle(minutes > 0 ? Color.orange : Color.green)
        } else { Text("Scheduled").font(.caption).foregroundStyle(.secondary) }
    }
}

struct SavedTransitRow: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared
    let plan: SavedTransitPlan
    @State private var reminderFailed = false

    var body: some View {
        HStack(spacing: 10) {
            Button { model.openTransit(plan) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name).font(.subheadline.bold()).lineLimit(1)
                    Text(plan.departure.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            if plan.departure > Date() {
                Button {
                    if plan.reminder {
                        TransitReminders.cancel(plan)
                        setReminder(false)
                    } else {
                        Task {
                            if await TransitReminders.schedule(plan) {
                                if settings.savedTransit.contains(where: { $0.id == plan.id }) { setReminder(true) }
                                else { TransitReminders.cancel(plan) }
                            } else { reminderFailed = true }
                        }
                    }
                } label: { Image(systemName: plan.reminder ? "bell.fill" : "bell") }
                    .accessibilityLabel(plan.reminder ? "Cancel reminder" : "Remind me five minutes before leaving")
            }
            Button(role: .destructive) {
                TransitReminders.cancel(plan)
                settings.savedTransit.removeAll { $0.id == plan.id }
            } label: { Image(systemName: "trash") }
                .accessibilityLabel("Remove saved transit trip")
        }
        .padding(12)
        .alert("Couldn't schedule the reminder", isPresented: $reminderFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Check Kite’s notification permissions in iPhone Settings.") }
    }

    private func setReminder(_ enabled: Bool) {
        guard let i = settings.savedTransit.firstIndex(where: { $0.id == plan.id }) else { return }
        settings.savedTransit[i].reminder = enabled
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
