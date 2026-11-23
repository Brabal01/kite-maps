import MapKit
import SwiftUI
import VelaCore

/** Route preview: the from/to card on top, routes on the map, the trip sheet below. */
struct DirectionsOverlay: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    /** How tall the from/to card is, so the sheet at full height stops below it. */
    @State private var cardHeight: CGFloat = 130

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.height + geo.safeAreaInsets.bottom
            ZStack(alignment: .top) {
                VStack {
                    Spacer()
                    BottomSheet(detent: $model.detent, containerHeight: full, peekHeight: TripHeader.peek(model.directions),
                                allowsCollapse: true, topClearance: cardHeight + 16) {
                        TripHeader(model: model)
                    } content: {
                        TripBody(model: model)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                if model.detent != .collapsed, let d = model.directions {
                    VStack(spacing: 6) {
                        EndpointsCard(model: model, state: d)
                        if d.route != nil || d.pickedTrip != nil {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { model.detent = .collapsed }
                            } label: {
                                Label("Show map overview", systemImage: "map")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12).frame(minHeight: 36)
                                    .glass(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                        .padding(.top, 6)
                        .background(GeometryReader { g in
                            Color.clear
                                .onAppear { cardHeight = g.size.height }
                                .onChange(of: g.size.height) { cardHeight = $0 }
                        })
                }
            }
            // Never wider than the screen, whatever a row inside asks for: a long trip's row once
            // pushed the whole screen, from/to box included, off the right edge.
            .frame(width: geo.size.width)
            .onChange(of: model.detent == .collapsed) { _ in model.frameRoute() }
            .safeAreaInset(edge: .bottom, spacing: 4) {
                if model.detent != .collapsed, let trip = model.directions?.pickedTrip {
                    TransitStartButton { model.startTransit(trip) }
                        .padding(.horizontal, 14).padding(.bottom, 4)
                }
            }
            .alert("Transit", isPresented: Binding(get: { model.transitStartNotice != nil },
                                                   set: { if !$0 { model.transitStartNotice = nil } })) {
                Button("OK") { model.transitStartNotice = nil }
            } message: { Text(L10n.text(model.transitStartNotice ?? "")) }
            .sheet(item: $model.gpxExport) { export in
                VStack(spacing: 18) {
                    Image(systemName: "map").font(.system(size: 42, weight: .semibold))
                        .foregroundColor(KiteColor.accentText)
                    Text(L10n.text("Export GPX")).font(KiteText.title())
                    Text(export.name).font(KiteText.caption()).foregroundColor(KiteColor.inkSecondary)
                    ShareLink(item: export.url) {
                        Label(L10n.text("Share .gpx file"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(KitePrimaryButtonStyle(height: 52))
                    Button(L10n.text("Done")) { model.gpxExport = nil }
                        .font(KiteText.label(16))
                }
                .padding(24)
                .presentationDetents([.height(300)])
            }
        }
    }
}

struct EndpointsCard: View {
    @ObservedObject var model: AppModel
    let state: DirectionsState
    @Environment(\.colorScheme) private var scheme
    @State private var showStops = false

    private var stopIndices: [Int] {
        state.reversed ? Array(state.stops.indices.reversed()) : Array(state.stops.indices)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { withAnimation { model.closeDirections() } } label: {
                Image(systemName: "arrow.left").font(.system(size: 22, weight: .bold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            VStack(spacing: 0) {
                endpoint(.from, icon: "circle", color: Vela.tealLight, text: state.fromPlace?.name ?? "My location")
                if !state.stops.isEmpty {
                    Divider().padding(.leading, 30)
                    Button { withAnimation(.easeInOut(duration: 0.2)) { showStops.toggle() } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").frame(width: 18)
                            Text(L10n.format("Stops on route: %@", String(state.stops.count)))
                            Spacer()
                            Image(systemName: showStops ? "chevron.up" : "chevron.down").font(.caption)
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showStops {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(stopIndices.enumerated()), id: \.element) { position, index in
                                    stopRow(position, index)
                                }
                            }
                        }
                        .frame(height: min(3, CGFloat(state.stops.count)) * 44)
                    }
                }
                Divider().padding(.leading, 30)
                endpoint(.to, icon: "mappin.circle.fill", color: Vela.closed, text: state.toPlace?.name ?? "My location")
                if !state.transit && state.stops.count < 8 {
                    Divider().padding(.leading, 30)
                    Button { model.addingStop = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).frame(width: 18)
                            Text("Add stop").font(.system(size: 17, weight: .semibold))
                            Spacer()
                        }
                        .foregroundColor(Vela.accentText(scheme))
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { model.reverseDirections() } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 19, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Vela.chip(scheme)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Swap start and end")
        }
        .foregroundColor(.primary)
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func stopRow(_ position: Int, _ index: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(position + 1)")
                .font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(Color.secondary))
            Text(state.stops[index].name).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                Button {
                    model.moveStop(index, by: state.reversed ? 1 : -1)
                } label: { Label("Move stop earlier", systemImage: "arrow.up") }
                .disabled(position == 0)
                Button {
                    model.moveStop(index, by: state.reversed ? -1 : 1)
                } label: { Label("Move stop later", systemImage: "arrow.down") }
                .disabled(position == state.stops.count - 1)
                Button(role: .destructive) { model.removeStop(index) } label: {
                    Label("Remove stop", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 20))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Stop options")
        }
        .frame(height: 44)
    }

    private func endpoint(_ kind: RouteEndpoint, icon: String, color: Color, text: String) -> some View {
        Button { model.editingEndpoint = kind } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundColor(color).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.text(kind.rawValue)).font(.caption).foregroundColor(.secondary)
                    Text(L10n.text(text)).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                }
                Spacer()
                Image(systemName: "pencil").font(.caption).foregroundColor(.secondary)
            }
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/** The part of the trip sheet always in view: how long, how you go, and a giant Go. */
/**
 The one place that explains what the planner is waiting for. A denied
 permission, a slow GPS, a stale fix and an approximate fix are not the same
 problem and must not share one sentence.
 */
struct PlanningStatusBanner: View {
    @ObservedObject var model: AppModel
    var compact = false
    @Environment(\.colorScheme) private var scheme

    private var icon: String {
        guard let s = model.directions?.planning else { return "location.fill" }
        if model.location.denied || model.location.servicesOff { return "location.slash.fill" }
        switch s.phase {
        case .waitingForPermission: return "location.badge.clock"
        case .failed: return "exclamationmark.triangle.fill"
        case .searching: return model.planningOffersManualStart ? "location.magnifyingglass" : "location.fill"
        case .ready, .idle:
            switch s.originUsability {
            case .stale: return "clock.arrow.circlepath"
            case .approximate: return "location.slash.circle.fill"
            case .imprecise, .expired: return "exclamationmark.triangle.fill"
            case .usable, .missing: return "location.fill"
            }
        }
    }

    var body: some View {
        if let text = model.planningStatusText {
            VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 13 : 15, weight: .bold))
                        .foregroundColor(KiteColor.accentText)
                        .frame(width: 18)
                    Text(L10n.text(text))
                        .font(.system(size: compact ? 13.5 : 15.5, weight: .semibold))
                        .foregroundColor(KiteColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("planning-status")

                HStack(spacing: 7) {
                    if model.location.denied || model.location.servicesOff {
                        action("Open Settings", "gearshape.fill", "planning-settings", LocationService.openSettings)
                    }
                    if model.planningCanRefresh {
                        action("Try again", "arrow.clockwise", "planning-retry") { model.retryPlanningLocation() }
                    }
                    if model.planningOffersManualStart {
                        action("Choose start", "mappin", "planning-manual-start") { model.editingEndpoint = .from }
                    }
                    if model.location.reducedAccuracy, !model.location.denied, !model.location.servicesOff {
                        action("Use precise location", "scope", "planning-precise") { model.usePrecisePlanningLocation() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func action(_ title: String, _ icon: String, _ id: String,
                        _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L10n.text(title), systemImage: icon)
                .font(.system(size: 12.5, weight: .bold))
                .padding(.horizontal, 11)
                .frame(minHeight: compact ? 30 : 34)
                .foregroundColor(KiteColor.accentText)
                .background(Capsule().fill(KiteColor.accentSoft))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct TripHeader: View {
    @ObservedObject var model: AppModel
    @AppStorage("walkingSpeed") private var walkingSpeed = 5.0
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme

    /** Route cards show when there's a choice to make: up to three, the picked one lit. */
    static func cards(_ d: DirectionsState) -> [Route] {
        !d.transit && d.route != nil && d.current.count > 1 ? Array(d.current.prefix(3)) : []
    }

    /** The place shuts before, or just as, this trip gets there. */
    static func closing(_ d: DirectionsState) -> ClosingCheck.Warning? {
        guard !d.transit, d.startsFromLocation, let r = d.route else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return ClosingCheck.warning(status: d.destination.statusText, nowMinutes: (c.hour ?? 0) * 60 + (c.minute ?? 0),
                                    travelSeconds: r.durationSeconds)
    }

    /** How tall the sheet sits at rest, so everything above the fold (cards, Go, modes) is in view. */
    static func peek(_ d: DirectionsState?) -> CGFloat {
        guard let d else { return 300 }
        if d.transit { return d.trips?.isEmpty == true ? 310 : 200 }
        let n = cards(d).count
        let base: CGFloat = n == 0 ? 300 : 288
        return base + (closing(d) != nil ? 36 : 0)
    }

    private var optionsMenu: some View {
        Menu {
            Button { model.saveCurrentJourney() } label: {
                Label(L10n.text("Save journey"), systemImage: "bookmark")
            }
            Button { model.prepareGPXExport() } label: {
                Label(L10n.text("Export GPX"), systemImage: "square.and.arrow.up")
            }
            if model.directions?.mode == .walk {
                Picker("Walking speed", selection: $walkingSpeed) {
                    ForEach(4...16, id: \.self) { step in
                        let speed = Double(step) / 2
                        Text("\(speed.formatted(.number.locale(AppSettings.shared.language.locale))) km/h").tag(speed)
                    }
                }
            } else {
                Toggle("Avoid tolls", isOn: $settings.avoidTolls)
                Toggle(Fmt.yards ? "Avoid motorways" : "Avoid highways", isOn: $settings.avoidHighways)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.primary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Vela.chip(scheme)))
        }
        .accessibilityLabel("Route options")
        .onChange(of: settings.avoidTolls) { _ in model.reloadRoutes() }
        .onChange(of: settings.avoidHighways) { _ in model.reloadRoutes() }
        .onChange(of: walkingSpeed) { _ in model.refreshWalkingRoutes() }
    }

    private var goButton: some View {
        Button { model.startNavigation() } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.north.fill").font(.system(size: 22, weight: .bold))
                Text(L10n.text("Go")).font(KiteText.headline(22))
            }
        }
        .buttonStyle(KitePrimaryButtonStyle(height: 62))
        .accessibilityLabel("Start navigation")
        .accessibilityIdentifier("start-navigation")
    }

    @ViewBuilder private func closingLine(_ d: DirectionsState) -> some View {
        if let w = Self.closing(d) {
            Label(L10n.format(w.before ? "Closes at %@, before you arrive" : "Closes at %@, just after you arrive", w.closes),
                  systemImage: "clock.badge.exclamationmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(scheme == .dark ? Vela.closedDark : Vela.closed)
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(height: 22)
        }
    }

    private func card(_ r: Route, best: Route, on: Bool, pick: @escaping () -> Void) -> some View {
        let delta = r.durationSeconds - best.durationSeconds
        let comparison = r.id == best.id ? L10n.text("Fastest route")
            : delta < 30 ? L10n.text("Same time") : "+\(Fmt.duration(delta))"
        return Button(action: pick) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(comparison).font(.caption.weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 1)
                    if on { Image(systemName: "checkmark.circle.fill").font(.caption.weight(.semibold)) }
                }
                Text(Fmt.duration(r.durationSeconds)).font(.title3.weight(.heavy)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.68)
                Text(r.summary ?? Fmt.distance(r.distanceMeters))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                TollRouteCaption(route: r) {
                    Text(L10n.format("arrive %@", Fmt.arrival(r.durationSeconds)))
                }
                .font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(.horizontal, 10)
            .foregroundStyle(KiteColor.ink)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(on ? KiteColor.accentSoft : KiteColor.fill))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(
                on ? KiteColor.accent : .clear, lineWidth: 2
            ))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(r.id == best.id ? "route-summary" : "route-summary-\(r.id)")
    }

    var body: some View {
        if model.detent != .collapsed, let d = model.directions {
            let cards = Self.cards(d)
            if let best = cards.first {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        ModeTabs(model: model, state: d)
                        optionsMenu
                    }
                    HStack(spacing: 6) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { i, r in
                            card(r, best: best, on: r.id == d.route?.id) { model.selectRoute(i) }
                        }
                    }
                    PlanningStatusBanner(model: model, compact: true)
                    closingLine(d)
                    if d.startsFromLocation { goButton }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    if d.transit {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.pickedTrip.map { Fmt.duration($0.durationSeconds) } ?? L10n.text("Transit"))
                                .font(.system(size: 40, weight: .heavy)).foregroundColor(Vela.accentText(scheme))
                            Text("By public transport").font(.system(size: 17, weight: .medium)).foregroundColor(Vela.muted(scheme))
                        }
                    } else if let r = d.route {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.duration(r.durationSeconds))
                                .font(KiteText.digits(44, weight: .heavy))
                                .foregroundColor(TripBody.delayColor(r, scheme))
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .accessibilityIdentifier("route-summary")
                            Text(L10n.format("%@ · arrive %@", String(describing: Fmt.distance(r.distanceMeters)), String(describing: Fmt.arrival(r.durationSeconds))))
                                .font(.system(size: 17, weight: .medium)).foregroundColor(Vela.muted(scheme))
                                .lineLimit(1).minimumScaleFactor(0.8)
                            if r.mode == .drive {
                                TollRouteCaption(route: r) { EmptyView() }
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    } else if d.loading.contains(d.mode) {
                        HStack(spacing: 10) { ProgressView(); Text("Finding routes…").font(.system(size: 19, weight: .semibold)) }
                            .frame(height: 52)
                    } else if model.planningStatusText != nil {
                        PlanningStatusBanner(model: model)
                            .frame(minHeight: 52)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.text(d.errors[d.mode] ?? "No route found.")).font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Vela.muted(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                            if model.location.denied || model.location.servicesOff {
                                PillButton(title: "Open Settings", icon: "location.fill", filled: true) { LocationService.openSettings() }
                            } else if d.errors[d.mode] != nil {
                                PillButton(title: "Try again", icon: "arrow.clockwise") { model.reloadRoutes() }
                            }
                        }
                        .frame(minHeight: 52)
                    }
                    Spacer(minLength: 8)
                    if !d.transit { optionsMenu }
                }
                ModeTabs(model: model, state: d)
                if d.transit, d.trips?.isEmpty == true, d.stops.isEmpty {
                    TransitFallbackLinks(model: model, state: d)
                }
                closingLine(d)
                if !d.transit, d.startsFromLocation, d.route != nil { goButton }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            }
        }
    }
}

struct ModeTabs: View {
    @ObservedObject var model: AppModel
    let state: DirectionsState
    @Environment(\.colorScheme) private var scheme

    private func icon(_ m: TravelMode) -> String {
        switch m {
        case .drive: return "car.fill"
        case .bike: return "bicycle"
        case .walk: return "figure.walk"
        }
    }

    private func modeID(_ m: TravelMode) -> String {
        switch m {
        case .drive: return "drive"
        case .bike: return "bike"
        case .walk: return "walk"
        }
    }

    var body: some View {
        // Four equal tiles, always all in view, so the right one is easy to hit.
        HStack(spacing: 8) {
            ForEach(TravelMode.allCases) { m in
                let on = !state.transit && m == state.mode
                tile(icon: icon(m), on: on, loading: state.loading.contains(m),
                     time: state.routes[m]?.first.map { Fmt.shortDuration($0.durationSeconds) }) { model.setMode(m) }
                    .accessibilityLabel(L10n.text(m.label))
                    .accessibilityIdentifier("mode-\(modeID(m))")
            }
            tile(icon: "tram.fill", on: state.transit, loading: state.trips == nil,
                 // The same trip the header shows (the picked one, else the first), so the two never disagree.
                 time: (state.pickedTrip ?? state.trips?.first).map { Fmt.shortDuration($0.durationSeconds) }) { model.showTransit() }
                .accessibilityLabel("Transit")
                .accessibilityIdentifier("mode-transit")
        }
    }

    private func tile(icon: String, on: Bool, loading: Bool, time: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 21, weight: .semibold))
                if loading {
                    ProgressView().scaleEffect(0.75).frame(height: 20)
                } else {
                    Text(time ?? "–").font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .foregroundColor(on ? KiteColor.onAccent : KiteColor.ink)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(on ? KiteColor.accent : KiteColor.fill))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct TripBody: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var showRoutePreview = false

    var body: some View {
        if model.detent != .collapsed, let d = model.directions {
            ScrollView {
                SheetTopMarker()
                VStack(alignment: .leading, spacing: 12) {
                    PlanningStatusBanner(model: model)
                    if d.transit {
                        TransitBody(model: model, state: d)
                    } else if let r = d.route {
                        if r.mode == .drive { RouteCharges(route: r) }
                        summary(r, d)
                        Button {
                            showRoutePreview = true
                        } label: {
                            Label(L10n.text("Preview this route"), systemImage: "map")
                        }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("route-preview-open")
                        .sheet(isPresented: $showRoutePreview) {
                            RoutePreviewSheet(model: model, route: r)
                        }
                        // More than three routes is rare; the ones past the cards stay reachable here.
                        if d.current.count > 3 { alternates(d, picked: r) }
                        Divider()
                        if let coverage = model.previewCoverage, coverage.routeID == r.id {
                            DisclosureGroup(L10n.text("Road events ahead")) {
                                RoadEventsList(controls: coverage.events,
                                    emptyMessage: coverage.unavailable ? "Road data temporarily unavailable" :
                                        (coverage.complete ? "No mapped road events ahead" : "Checking the route…"))
                            }
                        }
                        Text("Steps").font(.headline)
                        StepsList(route: r)
                        if let url = d.toPlace?.shareURL { shareButton(url).padding(.top, 6) }
                    } else if d.loading.contains(d.mode) {
                        HStack { ProgressView(); Text("Finding routes…").foregroundColor(.secondary) }
                            .padding(.vertical, 20)
                    } else if model.planningStatusText == nil {
                        // The header already explains why (location off, provider down).
                        // The expanded sheet gets a proper empty state, not the same
                        // sentence repeated under it.
                        KiteEmptyState(icon: "map",
                                       title: "No route to show",
                                       detail: "Change the start, the destination or the travel mode, then try again.",
                                       actionTitle: "Try again") { model.reloadRoutes() }
                            .padding(.vertical, KiteSpace.s)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
            .sheetScroll()
        }
    }

    static func delayColor(_ r: Route, _ scheme: ColorScheme) -> Color {
        switch r.delayLevel {
        case 2: return scheme == .dark ? Vela.closedDark : Vela.closed
        case 1: return Color(hex: 0xE37400)
        default: return Vela.accentText(scheme)
        }
    }

    private func delayColor(_ r: Route) -> Color { Self.delayColor(r, scheme) }

    private func summary(_ r: Route, _ d: DirectionsState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let best = d.current.map(\.durationSeconds).min() ?? r.durationSeconds
            let lead = r.durationSeconds <= best + 30 ? (r.trafficSeconds != nil ? "Fastest route now" : "Best route") : "Slower route"
            Text([L10n.text(lead), r.summary.map { L10n.format("via %@", $0) }].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 18, weight: .semibold))
            if r.mode == .drive, r.trafficSeconds != nil {
                Text(r.delayLevel == 0 ? L10n.text("Traffic is light") : L10n.format("%@ slower than usual", Fmt.duration(r.durationSeconds - r.typicalSeconds)))
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(delayColor(r))
            }
            if r.mode == .drive { RouteWazeSummary(route: r).padding(.top, 4) }
            if r.mode == .drive { RouteLiveCams(model: model, route: r).padding(.top, 6) }
        }
    }

    private func shareButton(_ url: URL) -> some View {
        ShareLink(item: url) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .bold))
                Text("Share place").font(KiteText.label(16))
            }
            .padding(.horizontal, 20)
            .frame(height: 50)
            .foregroundColor(KiteColor.accentText)
            .background(Capsule().fill(KiteColor.accentSoft))
        }
        .buttonStyle(.plain)
    }

    private func alternates(_ d: DirectionsState, picked: Route) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(d.current.enumerated()), id: \.element.id) { i, r in
                if i >= 3, r.id != picked.id {
                    Button { model.selectRoute(i) } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.branch").foregroundColor(.secondary).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Fmt.duration(r.durationSeconds)) · \(Fmt.distance(r.distanceMeters))").font(.subheadline.weight(.medium))
                                TollRouteCaption(route: r) {
                                    if let s = r.summary { Text(L10n.format("via %@", s)).font(.caption).foregroundColor(.secondary) }
                                }
                            }
                            Spacer()
                            let diff = r.durationSeconds - picked.durationSeconds
                            // Under half a minute apart would round to "+1 min": call it the same.
                            Text(abs(diff) < 30 ? L10n.text("Same time") : diff > 0 ? "+\(Fmt.duration(diff))" : "−\(Fmt.duration(-diff))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct TollRouteCaption<Fallback: View>: View {
    let route: Route
    @ViewBuilder var fallback: () -> Fallback
    @State private var hasToll = false
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Group {
            if hasToll {
                Label("Toll sections", systemImage: "exclamationmark.circle.fill")
                    .accessibilityIdentifier("route-toll-sections")
            } else {
                fallback()
            }
        }
        .task(id: "\(route.id)-\(settings.avoidTolls)") {
            hasToll = false
            guard route.mode == .drive else { return }
            let found: Bool
            if let reported = route.routerReportedTolls {
                found = reported || VignetteRoads.hasLocallyKnownToll(on: route.polyline, avoidingTolls: settings.avoidTolls)
            } else {
                found = await VignetteRoads.hasMappedToll(on: route.polyline, avoidingTolls: settings.avoidTolls)
            }
            if !Task.isCancelled { hasToll = found }
        }
    }
}

/** Pay-later charges on this route (Dartford, the Mersey bridges, London's zone): there's no barrier to remind you. */
struct RouteCharges: View {
    let route: Route
    @State private var charges: [RoadCharge] = []
    @State private var motorways: [String] = []
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme
    /** Made-up charges for the build's screenshots. */
    static var demo: [RoadCharge] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !motorways.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label(L10n.format("Czech vignette sections: %@", String(describing: motorways.joined(separator: ", "))), systemImage: "road.lanes").font(.headline)
                    Link("Check sections and vehicle exemptions", destination: URL(string: "https://edalnice.gov.cz/cs/kde-plati")!)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Vela.chip(scheme)))
            }
            if route.polyline.contains(where: { (35...71).contains($0.lat) && (-11...31).contains($0.lng) }) {
                Link(destination: URL(string: "https://transport.ec.europa.eu/transport-themes/urban-transport/urban-vehicle-access-regulations_en")!) {
                    Label("Check low-emission zone rules", systemImage: "leaf")
                        .font(.subheadline.weight(.medium))
                }
            }
            ForEach(charges.isEmpty ? Self.demo : charges, id: \.self) { c in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sterlingsign.circle.fill").font(.system(size: 26, weight: .bold))
                        .foregroundColor(Color(hex: 0xE37400))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.format("Charge on this route: %@", String(describing: c.name))).font(.system(size: 17, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L10n.text(c.note)).font(.system(size: 15, weight: .medium)).foregroundColor(Vela.muted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Vela.chip(scheme)))
            }
        }
        .task(id: "\(route.id)-\(settings.avoidTolls)") {
            let line = route.polyline
            motorways = []
            let avoidingTolls = settings.avoidTolls
            let knownCharges = await Task.detached { RoadCharges.on(line) }.value
            let found = await VignetteRoads.czechMotorways(on: line, avoidingTolls: avoidingTolls)
            guard !Task.isCancelled else { return }
            charges = knownCharges
            motorways = found
        }
    }
}

struct StepsList: View {
    let route: Route
    /** While driving: start at the next step, so turns already made aren't listed. */
    var from = 0

    /** The steps worth saying, each with the length of the quiet name changes after it added on. */
    private var shown: [Maneuver] {
        var out: [Maneuver] = []
        for m in route.maneuvers.dropFirst(min(max(from, 0), route.maneuvers.count)) {
            if m.silent, !out.isEmpty { out[out.count - 1].distanceMeters += m.distanceMeters }
            else if !m.silent { out.append(m) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, m in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: maneuverSymbol(m.type))
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.isCzech ? CzechNavigation.prompt(m) : SpokenText.forScreen(m.instruction)).font(.system(size: 18, weight: .medium))
                        if let lane = m.laneHint { Text(lane).font(.subheadline).foregroundColor(.secondary) }
                        if m.distanceMeters > 0 {
                            Text(Fmt.distance(m.distanceMeters)).font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 9)
                Divider().padding(.leading, 40)
            }
        }
    }
}

/** The Transit tab: each trip as a row of line chips with its times, the picked one's legs below. */
struct TransitBody: View {
    @ObservedObject var model: AppModel
    let state: DirectionsState
    @Environment(\.colorScheme) private var scheme

    @State private var kind = 0
    @State private var when = Date()
    @State private var expanded: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $kind) {
                Text("Leave now").tag(0)
                Text("Depart at").tag(1)
                Text("Arrive by").tag(2)
            }
            .pickerStyle(.segmented)
            if kind != 0 {
                DatePicker("Time", selection: $when, in: Date().addingTimeInterval(-3600)..., displayedComponents: [.date, .hourAndMinute])
                    .font(.subheadline)
            }
        }
        .onAppear {
            kind = state.transitTime == nil ? 0 : (state.arriveBy ? 2 : 1)
            when = state.transitTime ?? Date()
        }
        .onChange(of: kind) { k in model.setTransitTime(kind: k, at: when) }
        .onChange(of: when) { w in if kind != 0 { model.setTransitTime(kind: kind, at: w) } }
        trips
    }

    @ViewBuilder
    private var trips: some View {
        if let trips = state.trips, !trips.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(trips.enumerated()), id: \.element.id) { i, t in
                    let open = expanded == t.id
                    Button {
                        model.selectTrip(i)
                        expanded = open ? nil : t.id
                    } label: {
                        HStack(spacing: 3) {
                            TripRow(trip: t, picked: t.id == state.pickedTrip?.id)
                            Image(systemName: open ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.trailing, 8)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(open ? Text("Hide trip details") : Text("Show trip details"))
                    if open {
                        TransitSteps(trip: t).padding(.horizontal, 8)
                    }
                    Divider()
                }
            }
            if let t = state.pickedTrip {
                TransitStartButton { model.startTransit(t) }
            }
            Text("Timetables from \(state.transitProvider)").font(.caption).foregroundColor(.secondary).padding(.top, 4)
        } else if state.trips == nil {
            HStack { ProgressView(); Text("Finding transit…").foregroundColor(.secondary) }
                .padding(.vertical, 20)
        } else {
            Text(L10n.text(state.tripsError ?? "No transit trips found.")).foregroundColor(.secondary).padding(.vertical, 20)
        }
    }
}

private struct TransitFallbackLinks: View {
    @ObservedObject var model: AppModel
    let state: DirectionsState
    @State private var showGoogleTransit = false

    var body: some View {
        if let (from, to) = model.endpoints(state) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Try another transit planner").font(.caption.weight(.semibold))
                HStack(spacing: 8) {
                    Button {
                        let start = MKMapItem(placemark: MKPlacemark(coordinate: coordinate(from)))
                        let end = MKMapItem(placemark: MKPlacemark(coordinate: coordinate(to)))
                        start.name = state.fromPlace?.name ?? L10n.text("My location")
                        end.name = state.toPlace?.name ?? L10n.text("My location")
                        MKMapItem.openMaps(with: [start, end], launchOptions: [
                            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit
                        ])
                    } label: {
                        Label("Apple Maps", systemImage: "arrow.up.right.square")
                    }
                    if !model.settings.noGoogle, let url = googleURL(from: from, to: to) {
                        Button { showGoogleTransit = true } label: { Label("Google Maps", systemImage: "tram") }
                            .fullScreenCover(isPresented: $showGoogleTransit) {
                                GoogleMapsPage(url: url, title: L10n.text("Transit"))
                            }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                if [from, to].allSatisfy({ (35.75...36.12).contains($0.lat) && (14.12...14.64).contains($0.lng) }),
                   let url = URL(string: "https://www.publictransport.com.mt/visiting-malta/") {
                    Link(destination: url) { Label("Tallinja journey planner", systemImage: "arrow.up.right.square") }
                        .font(.subheadline)
                }
                if state.transitTime != nil {
                    Text("Set the departure or arrival time in the other planner.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func coordinate(_ point: LatLng) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng)
    }

    private func googleURL(from: LatLng, to: LatLng) -> URL? {
        var url = URLComponents(string: "https://www.google.com/maps/dir/")!
        url.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: "\(from.lat),\(from.lng)"),
            URLQueryItem(name: "destination", value: "\(to.lat),\(to.lng)"),
            URLQueryItem(name: "travelmode", value: "transit")
        ]
        return url.url
    }
}

private let clock: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    return f
}()

struct TripRow: View {
    let trip: TransitTrip
    let picked: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(times).font(.title3.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(Fmt.duration(trip.durationSeconds)).font(.headline.weight(.semibold)).monospacedDigit()
            }
            // Every ride on its own official color, every walk neutral: one glance says what to take.
            WrapLayout(spacing: 5, lineSpacing: 6) {
                ForEach(Array(trip.legs.enumerated()), id: \.offset) { i, leg in
                    HStack(spacing: 4) {
                        if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary) }
                        if leg.isWalk {
                            HStack(spacing: 1) {
                                Image(systemName: TransitMode.walk.symbol).font(.system(size: 13))
                                if leg.durationSeconds >= 60 { Text("\(Int((leg.durationSeconds / 60).rounded()))").font(.caption2) }
                            }
                            .foregroundColor(.secondary)
                        } else {
                            LineChip(leg: leg)
                        }
                    }
                }
            }
            .lineLimit(1)
            HStack(spacing: 6) {
                Label(summary, systemImage: "arrow.triangle.swap")
                if let first = trip.rides.first, let dep = first.depart {
                    Text(L10n.format("from %@", String(describing: clock.string(from: dep)))).lineLimit(1)
                }
            }
            .font(.caption).foregroundColor(.secondary)
            if let first = trip.rides.first, let direction = first.headsign, !direction.isEmpty {
                Label(direction, systemImage: "arrow.forward.circle")
                    .font(.caption.weight(.medium)).lineLimit(1).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let late = trip.rides.first?.delayMinutes {
                    Text(late > 0 ? "\(late) min late" : late < 0 ? "\(-late) min early" : "On time")
                        .foregroundColor(late > 1 ? Vela.closed : Vela.open)
                }
                if let first = trip.rides.first {
                    Text(liveLabel(first))
                        .foregroundColor(first.liveFreshness == .live || first.liveFreshness == .recent ? Vela.open : .secondary)
                }
                if trip.tightTransfer {
                    Label("Tight transfer", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(Vela.closed)
                }
                Spacer(minLength: 0)
            }
            .font(.caption2.weight(.medium))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(picked ? Vela.routeBlue.opacity(scheme == .dark ? 0.24 : 0.10)
                         : Color(uiColor: .secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(picked ? Vela.routeBlue.opacity(0.55) : Color.secondary.opacity(0.12), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var times: String {
        guard let a = trip.depart, let b = trip.arrive else { return Fmt.duration(trip.durationSeconds) }
        return "\(clock.string(from: a)) – \(clock.string(from: b))"
    }

    /// "2 changes · 6 min walk", the two things that decide between two trips.
    private var summary: String {
        let changes = max(0, trip.transfers)
        let walk = Int((trip.walkSeconds / 60).rounded())
        var parts: [String] = []
        parts.append(changes == 0 ? L10n.text("Direct")
                    : changes == 1 ? L10n.text("1 change")
                    : L10n.format("%@ changes", String(changes)))
        if walk > 0 { parts.append(L10n.format("%@ min walk", String(walk))) }
        return parts.joined(separator: " · ")
    }

    /// Freshness matters more than the bare "live" flag: a feed can be live but a few minutes old.
    private func liveLabel(_ leg: TransitLeg) -> String {
        switch leg.liveFreshness {
        case .live:
            return "Live"
        case .recent:
            if let age = leg.liveAgeSeconds {
                return age >= 120 ? "Live · \(age / 60) min old" : "Live · \(age) s old"
            }
            return "Live · recent"
        case .stale:
            return "Live data stale"
        case .scheduled:
            return "Scheduled"
        case .unavailable:
            return "Live unavailable"
        }
    }
}

/** Lays its views out left to right, starting a new line when the next one doesn't fit. */
struct WrapLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let used = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(used, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                  proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var items: [Int] = [], x: CGFloat = 0, h: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let w = min(size.width, width)
            if !items.isEmpty && x + spacing + w > width {
                rows.append((items, x, h))
                items = []; x = 0; h = 0
            }
            x += (items.isEmpty ? 0 : spacing) + w
            h = max(h, size.height)
            items.append(i)
        }
        if !items.isEmpty { rows.append((items, x, h)) }
        return rows
    }
}

/** A line's name on its own color, with the vehicle kind visible at a glance. */
struct LineChip: View {
    let leg: TransitLeg

    var body: some View {
        let identity = leg.identity
        let bg = Color(hex: identity.color)
        let fg = Color(hex: identity.textColor)
        HStack(spacing: 4) {
            TransitModeGlyph(mode: identity.mode, tint: fg, size: 11)
            Text(identity.shortName.isEmpty ? identity.mode.shortLabel : identity.shortName)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 120, alignment: .leading)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(minHeight: 22)
        .foregroundColor(fg)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(bg))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(fg.opacity(0.18), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L10n.text(identity.mode.label)) \(identity.shortName)")
        .accessibilityIdentifier("transit-line-\(identity.mode.rawValue)-\(identity.shortName)")
    }
}

/** The vehicle icon, with a small badge where two modes share an SF Symbol. */
struct TransitModeGlyph: View {
    let mode: TransitMode
    var tint: Color = .primary
    var size: CGFloat = 12

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: mode.symbol)
                .font(.system(size: size, weight: .bold))
            if let badge = mode.badge {
                Image(systemName: badge)
                    .font(.system(size: size * 0.55, weight: .black))
                    .offset(x: size * 0.32, y: size * 0.18)
            }
        }
        .foregroundColor(tint)
        .frame(width: size * 1.3, height: size * 1.2)
    }
}

func vehicleSymbol(_ v: TransitLeg.Vehicle) -> String {
    switch v {
    case .walk: return TransitMode.walk.symbol
    case .bus: return TransitMode.bus.symbol
    case .trolleybus: return TransitMode.trolleybus.symbol
    case .coach: return TransitMode.coach.symbol
    case .tram: return TransitMode.tram.symbol
    case .lightRail: return TransitMode.lightRail.symbol
    case .metro: return TransitMode.metro.symbol
    case .train: return TransitMode.regionalTrain.symbol
    case .ferry: return TransitMode.ferry.symbol
    case .funicular: return TransitMode.funicular.symbol
    case .cableCar: return TransitMode.cableCar.symbol
    case .aerialLift: return TransitMode.aerialLift.symbol
    case .monorail: return TransitMode.monorail.symbol
    case .bike: return TransitMode.bike.symbol
    case .other: return TransitMode.other.symbol
    }
}

struct TransitSteps: View {
    let trip: TransitTrip
    @State private var passages: [Int: TransitStationAccess.Passage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(trip.legs.enumerated()), id: \.offset) { index, leg in
                let transfer = leg.isWalk && index > 0 && index < trip.legs.count - 1
                HStack(alignment: .top, spacing: 10) {
                    TransitTimelineRail(
                        color: leg.isWalk ? Color.secondary : Color(hex: leg.identity.color),
                        node: leg.isWalk ? (transfer ? .transfer : .walk) : .ride,
                        first: index == 0,
                        last: index == trip.legs.count - 1)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        if leg.isWalk { walk(leg, passage: passages[index], transfer: transfer) }
                        else { ride(leg) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
                }
            }
        }
        .task(id: trip.id) {
            passages = [:]
            guard trip.hasMetroAccessNodes else { return }
            let result = await TransitStationAccess.resolve(trip)
            if !Task.isCancelled { passages = result }
        }
    }

    private func ride(_ leg: TransitLeg) -> some View {
        Group {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                LineChip(leg: leg)
                if let direction = leg.headsign {
                    Text(L10n.format("Direction: %@", direction)).font(.subheadline.weight(.semibold))
                }
            }
            let operatorDetails = [leg.agency, leg.serviceNumber].compactMap { $0 }.joined(separator: " · ")
            if !operatorDetails.isEmpty { Text(operatorDetails).font(.caption).foregroundStyle(.secondary) }
            if let provider = leg.liveProvider, let host = URL(string: provider)?.host,
               leg.liveFreshness == .live || leg.liveFreshness == .recent {
                Text(L10n.format("Live feed: %@", host)).font(.caption2).foregroundStyle(.secondary)
            }
            TransitCallRow(role: "Board at %@", name: leg.fromName, stop: leg.boardStop, time: leg.depart,
                           delay: leg.delayMinutes)
            if !leg.intermediateStops.isEmpty {
                DisclosureGroup(L10n.text("Stops along the way")) {
                    ForEach(Array(leg.intermediateStops.enumerated()), id: \.offset) { _, stop in
                        HStack {
                            Text(stop.name).strikethrough(stop.skipped)
                            if stop.skipped {
                                Text("Skipped stop").foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let time = stop.arrival ?? stop.departure { Text(transitClock(time, stop: stop)).monospacedDigit() }
                        }
                        .font(.caption).padding(.vertical, 3)
                    }
                }
                .font(.subheadline)
            }
            TransitCallRow(role: "Get off at %@", name: leg.toName, stop: leg.exitStop, time: leg.arrive,
                           delay: leg.arrivalDelayMinutes)
            ForEach(leg.serviceAlerts, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func walk(_ leg: TransitLeg, passage: TransitStationAccess.Passage?, transfer: Bool) -> some View {
        Group {
            if leg.toName.isEmpty || leg.toName == "END" {
                Text("Walk to the destination").font(.subheadline.weight(.semibold))
            } else {
                Text(L10n.format(transfer ? "Transfer on foot to %@" : "Walk to %@", leg.toName))
                    .font(.subheadline.weight(.semibold))
            }
            Text("\(Fmt.duration(leg.durationSeconds)) · \(Fmt.distance(leg.distanceMeters))")
                .font(.caption).foregroundStyle(.secondary)
            if let exit = passage?.exit { portal(exit, title: "Metro exit %@", icon: "arrow.up.right.square") }
            if let entrance = passage?.entrance { portal(entrance, title: "Metro entrance %@", icon: "arrow.down.right.square") }

        }
    }

    private func portal(_ portal: TransitStationAccess.Portal, title: String, icon: String) -> some View {
        let details = [portal.reference, portal.name == portal.reference ? nil : portal.name].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 2) {
            Label(L10n.format(title, details.isEmpty ? portal.destination ?? "" : details), systemImage: icon)
                .font(.subheadline.weight(.semibold))
            if let destination = portal.destination, !details.isEmpty {
                Text(L10n.format("Follow signs toward %@", destination)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }


}

/** The vertical journey timeline: a colored rail per ride, a dotted one per walk, a transfer node. */
private struct TransitTimelineRail: View {
    enum Node { case walk, ride, transfer }
    let color: Color
    let node: Node
    let first: Bool
    let last: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch node {
                case .ride:
                    Circle().fill(color).frame(width: 15, height: 15)
                    Circle().fill(.white.opacity(0.85)).frame(width: 5, height: 5)
                case .walk:
                    Circle().strokeBorder(color, lineWidth: 2).frame(width: 12, height: 12)
                case .transfer:
                    Circle().strokeBorder(color, lineWidth: 2).frame(width: 15, height: 15)
                    Circle().fill(color).frame(width: 7, height: 7)
                }
            }
            .frame(height: 22)
            if !last {
                if node == .walk {
                    VStack(spacing: 3) {
                        ForEach(0..<6, id: \.self) { _ in
                            Capsule().fill(color.opacity(0.55)).frame(width: 3, height: 5)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Rectangle().fill(color.opacity(0.85)).frame(width: 4)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct TransitCallRow: View {
    let role: String
    let name: String
    let stop: TransitCall?
    let time: Date?
    var delay: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let time { Text(transitClock(time, stop: stop)).monospacedDigit().fontWeight(.semibold) }
                if !name.isEmpty { Text(L10n.format(role, name)) }
            }
            .font(.subheadline)
            let platform = stop?.track.map { value in
                if let scheduled = stop?.scheduledTrack, scheduled != value {
                    return L10n.format("Platform change: %@ → %@", scheduled, value)
                }
                return L10n.format("Platform %@", value)
            }
            let code = stop?.stopCode.flatMap { $0 == stop?.track ? nil : L10n.format("Stop code %@", $0) }
            let label = [platform, code].compactMap { $0 }.joined(separator: " · ")
            if !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary) }
            if let detail = stop?.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            if let delay, delay != 0 {
                Text(L10n.format(delay > 0 ? "%@ min late" : "%@ min early", String(abs(delay))))
                    .font(.caption).foregroundStyle(delay > 0 ? Color.orange : Color.secondary)
            }
        }
    }
}

private func transitClock(_ time: Date, stop: TransitCall?) -> String {
    guard let zone = stop?.timeZone.flatMap(TimeZone.init(identifier:)) else { return clock.string(from: time) }
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.timeZone = zone
    return formatter.string(from: time)
}

/** Search for a place to stop at on the way. Home, work and saved places are one tap. */
struct StopPicker: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var query = ""
    @State private var found: [Place] = []
    @State private var searching = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            List {
                if !found.isEmpty {
                    Section("Results") { ForEach(found) { row($0, icon: "mappin.circle.fill") } }
                } else if searching {
                    HStack { ProgressView(); Text("Searching…").foregroundColor(.secondary) }
                }
                let mine = [settings.home.map { ($0, "house.fill") }, settings.work.map { ($0, "briefcase.fill") }].compactMap { $0 }
                    + settings.saved.prefix(12).map { ($0, "bookmark.fill") }
                if !mine.isEmpty && found.isEmpty {
                    Section("Your places") { ForEach(mine, id: \.0.id) { row($0.0, icon: $0.1) } }
                }
                if found.isEmpty && !searching {
                    Section("Along the way") {
                        ForEach([Fmt.yards ? "Petrol stations" : "Gas stations", "Coffee", "Restaurants", "EV charging"], id: \.self) { c in
                            Button { query = c; run() } label: { Label(L10n.text(c), systemImage: "magnifyingglass") }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a stop")
            .onSubmit(of: .search) { run() }
            .kiteList()
            .navigationTitle("Add stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func row(_ p: Place, icon: String) -> some View {
        Button {
            model.addStop(p)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).foregroundColor(.primary).lineLimit(1)
                    if let a = p.address { Text(a).font(.caption).foregroundColor(.secondary).lineLimit(1) }
                }
                Spacer()
                if let d = model.userLatLng?.distance(to: p.location) {
                    Text(Fmt.distance(d)).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        found = []
        // Look between you and where you're going, so stops fall along the way.
        let a = model.userLatLng ?? model.viewport.center
        let b = model.directions?.destination.location ?? a
        let mid = LatLng((a.lat + b.lat) / 2, (a.lng + b.lng) / 2)
        let span = max(a.distance(to: b) * 1.2, 5_000)
        let useGoogle = settings.googleSearchEnabled
        Task {
            let r = await PlaceSearch.search(q, center: mid, spanMeters: span, useGoogle: useGoogle, language: L10n.isCzech ? "cs" : "en")
            found = Array(r.places.prefix(30))
            searching = false
        }
    }
}
