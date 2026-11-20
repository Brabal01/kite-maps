import SwiftUI
import VelaCore

/** Turn-by-turn: the see-through turn strip, map buttons, and the slim trip bar. */
struct NavigationOverlay: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: Navigator
    @State private var showSteps = false
    @State private var showAlong = false
    @State private var showParking = false
    @State private var showMedia = false
    @State private var confirmEnd = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.sidePanel) private var panel

    /** "On my way to X, arriving around 5:42 PM (25 min)" with a map link. */
    private var etaText: String {
        let left = nav.progress?.remainingSeconds ?? nav.route.durationSeconds
        let link = nav.destination.shareURL.map { "\n\($0.absoluteString)" } ?? ""
        return L10n.format("On my way to %@, arriving around %@ (%@ away).", nav.destination.name, Fmt.arrival(left), Fmt.duration(left)) + link
    }

    /** The voice or map view just picked, shown by its button for a moment. */
    @State private var buttonNote: ButtonNote?
    @ObservedObject private var settings = AppSettings.shared
    /** The warning shown for a few seconds after tapping the "also ahead" pill. */
    @State private var peek: NavAlert?

    /**
     * Every warning that's up, most important first. Only the first gets the big card, like Waze;
     * the rest wait in one small pill. Whatever you'll reach first along the route wins, except a
     * camera while you're over its limit, which always wins (that's the one that costs a fine).
     * An average check and a police aircraft aren't a spot on the road ahead, so they only get the
     * big card when nothing else is up.
     */
    private var alertsUp: [NavAlert] {
        guard !nav.arrived else { return [] }
        var ahead: [(NavAlert, Double)] = []
        if let c = nav.cameraAhead { ahead.append((.camera, c.meters)) }
        // Traffic jams don't get a card up top: they show as a small line over the trip bar instead.
        if let w = nav.wazeAhead, w.alert.kind != .jam { ahead.append((.waze, w.meters)) }
        var list = ahead.sorted { $0.1 < $1.1 }.map(\.0)
        if let c = nav.cameraAhead, let limit = c.limitKmh ?? nav.speedLimitKmh, nav.speedMps * 3.6 > limit + 3,
           let i = list.firstIndex(of: .camera), i > 0 {
            list.remove(at: i)
            list.insert(.camera, at: 0)
        }
        if nav.averageCheck != nil { list.append(.average) }
        if nav.aircraftNear != nil { list.append(.aircraft) }
        return list
    }

    private var roadEventsStatus: String {
        if nav.controlsUnavailable { return "Road data temporarily unavailable" }
        return nav.routeControls == nil ? "Checking the route…" : "No mapped road events ahead"
    }

    /** The one warning on the big card. */
    private var mainAlert: NavAlert? {
        let list = alertsUp
        if let peek, list.contains(peek) { return peek }
        return list.first
    }

    /** A traffic jam ahead, shown small over the trip bar rather than as a big card. */
    private var trafficAhead: WazeAhead? {
        guard !nav.arrived, let w = nav.wazeAhead, w.alert.kind == .jam else { return nil }
        return w
    }

    /** The police risk chip, only worth a look while driving when it isn't low. */
    private var showRiskChip: Bool {
        guard settings.wazeOn, settings.policeRisk, settings.wazePolice,
              let risk = nav.policeRisk, !nav.arrived else { return false }
        return PoliceRisk.level(risk) != .low
    }

    /** iPhone SE and the like, where the banner, a warning card and the chips can't all fit. */
    static var shortScreen: Bool {
        (UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.bounds.height ?? 800) < 700
    }

    /** A chip above the speed badge sits where the road name goes, so the name steps aside for it. */
    private var chipShowing: Bool { showRiskChip }

    var body: some View {
        // One column, so however many warnings are up, they push the map buttons down rather than cover them.
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                if let journey = model.transitJourney, journey.leg.isWalk, !nav.arrived {
                    HStack {
                        Label("Walk to the stop", systemImage: "figure.walk").font(.caption.weight(.semibold))
                        Spacer()
                        Button("At the stop") { model.advanceTransit() }
                            .font(.caption.weight(.semibold))
                    }
                    .padding(8)
                    .glass(RoundedRectangle(cornerRadius: 12))
                }
                if nav.arrived {
                    if nav.route.mode == .drive {
                        HStack {
                            if let side = nav.destinationSide { Label(L10n.format("Destination on the %@", L10n.text(side.capitalized).lowercased()), systemImage: "mappin.circle") }
                            Spacer()
                            Button("Find visitor parking") { showParking = true }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .glass(RoundedRectangle(cornerRadius: 14))
                    }
                    ArrivedCard(name: nav.destination.name, onPark: nav.route.mode == .drive ? { model.saveParking() } : nil,
                                note: nav.wazeWarned > 0 ? "Waze drivers warned you about \(nav.wazeWarned) report\(nav.wazeWarned == 1 ? "" : "s") on the way" : nil) { model.endNavigation() }
                } else {
                    InstructionBanner(nav: nav)
                        .fixedSize(horizontal: false, vertical: true)

                }
                // One warning at a time; the others wait in the pill under it.
                switch mainAlert {
                case .camera?:
                    if let cam = nav.cameraAhead {
                        CameraCard(alert: cam, speedKmh: nav.speedMps * 3.6, roadLimitKmh: nav.speedLimitKmh)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                case .waze?:
                    if let w = nav.wazeAhead {
                        WazeCard(ahead: w)
                            .fixedSize(horizontal: false, vertical: true)
                            .onTapGesture { withAnimation { nav.dismissWaze() } }
                            .accessibilityHint("Tap to hide")
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                case .average?:
                    if let check = nav.averageCheck { AverageCheckCard(check: check) }
                case .aircraft?:
                    if let air = nav.aircraftNear { AircraftCard(aircraft: air.aircraft, meters: air.meters) }
                case nil:
                    EmptyView()
                }
                let others = alertsUp.filter { $0 != mainAlert }
                if !others.isEmpty {
                    AlsoAheadPill(nav: nav, alerts: others) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { peek = others.first }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
                // On a short phone (SE) with a warning card and lane arrows up there's no room for a third
                // row: the card matters more, and the GPS and rerouting notes come back once it's gone.
                if mainAlert != nil && Self.shortScreen {
                    EmptyView()
                } else if nav.estimating, !nav.arrived {
                    // In a tunnel Kite carries on along the route at the speed you went in: say it's a best guess.
                    Label("No GPS · estimated", systemImage: "location.slash")
                        .font(.system(size: 16, weight: .bold))
                        .padding(.horizontal, 16).frame(height: 38)
                        .glass(Capsule())
                } else if nav.gpsLost, !nav.arrived {
                    // In a tunnel the speed and the next turn stop moving: say why, so it doesn't look live.
                    Label("GPS signal lost", systemImage: "location.slash.fill")
                        .font(.system(size: 16, weight: .bold))
                        .padding(.horizontal, 16).frame(height: 38)
                        .glass(Capsule())
                } else if nav.rerouting {
                    Label("Rerouting…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .bold))
                        .padding(.horizontal, 16).frame(height: 38)
                        .glass(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .inSidePanel(panel)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: nav.cameraAhead?.startMeters)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: nav.wazeAhead?.alert.id)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mainAlert)
            .task(id: peek) {
                // A peek at the next warning lasts a few seconds, then the nearest one comes back.
                guard peek != nil else { return }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { peek = nil }
            }

            if !nav.arrived {
                HStack {
                    RoadControlTimeline(controls: nav.upcomingControls, emptyMessage: roadEventsStatus,
                                        compactStatus: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .inSidePanel(panel)
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    // A Waze police card already says it louder; the chip comes back when it's gone.
                    // Only worth a look while driving when it isn't low; it would otherwise sit by the road name.
                    // On a short phone (SE) a warning card plus lanes leaves no room: the chip gives way to the card.
                    // The same when the next speed limit is up: on a short phone the column would reach the cards.
                    if showRiskChip, !((mainAlert != nil || nav.limitDropAhead != nil) && Self.shortScreen), let risk = nav.policeRisk { PoliceRiskChip(score: risk) }
                    if settings.showNavSpeed && !settings.speedOnRight {
                        SpeedBadge(mps: nav.speedMps, limitKmh: nav.speedLimitKmh, coming: nav.limitDropAhead)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    if let note = buttonNote {
                        // Says which of the three the speaker (or the map view) is on now, for a moment.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.text(note.title)).font(.system(size: 18, weight: .bold)).foregroundColor(Vela.accentText(.dark))
                            Text(L10n.text(note.detail)).font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x0F172A).opacity(0.95)))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
                    }
                    HStack(spacing: 10) {
                        if !nav.arrived {
                            MapFab(icon: nav.showingOverview ? "location.north.fill" : "arrow.up.left.and.arrow.down.right", size: 52) {
                                model.overviewNav()
                            }
                            .accessibilityLabel(nav.showingOverview ? "Follow your location" : "Show remaining route")
                        }
                        MapLookButton(look: settings.driveLook, size: 52) {
                            model.cycleDriveLook()
                            let look = settings.driveLook
                            withAnimation(.easeOut(duration: 0.2)) { buttonNote = ButtonNote(title: look.title, detail: look.detail) }
                        }
                    }
                    HStack(spacing: 6) {
                        MapFab(icon: "minus", size: 44) { model.adjustNavZoom(wider: true) }
                            .accessibilityLabel("Zoom out")
                        MapFab(icon: "plus", size: 44) { model.adjustNavZoom(wider: false) }
                            .accessibilityLabel("Zoom in")
                    }
                    MapFab(icon: nav.voiceMode.icon, tint: nav.voiceMode == .alerts ? Vela.accentText(scheme) : .primary, size: 52) {
                        nav.voiceMode = nav.voiceMode.next
                        let v = nav.voiceMode
                        withAnimation(.easeOut(duration: 0.2)) { buttonNote = ButtonNote(title: v.title, detail: v.detail) }
                    }
                    .accessibilityLabel(L10n.format("Voice: %@", L10n.text(nav.voiceMode.title)))
                    .accessibilityHint("Switches between voice on, alerts only and voice off")
                }
                .task(id: buttonNote) {
                    guard buttonNote != nil else { return }
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation(.easeIn(duration: 0.25)) { buttonNote = nil }
                }
                if settings.showNavSpeed && settings.speedOnRight {
                    SpeedBadge(mps: nav.speedMps, limitKmh: nav.speedLimitKmh, coming: nav.limitDropAhead)
                }
            }
            .padding(.horizontal, 16)
            if settings.showMusicControls && nav.route.mode == .drive && !nav.arrived {
                DriveMusicPanel().padding(.horizontal, 16).inSidePanel(panel)
            }
            if !nav.following && !nav.showingOverview {
                Button { model.recenterNav() } label: {
                    Label("Re-centre", systemImage: "location.north.line.fill")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.horizontal, 22).frame(height: 52)
                        .foregroundColor(Vela.onAccent(scheme))
                        .background(Capsule().fill(Vela.accent(scheme)))
                        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                // Under the car, which drives beside the side panel when there is one.
                .frame(maxWidth: .infinity)
                .padding(.leading, panel)
            }
            if let offer = nav.fasterOffer, !nav.arrived {
                // A faster way: two big buttons instead of the route just changing under you.
                FasterRouteCard(offer: offer,
                                onKeep: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { nav.keepRoute() } },
                                onTake: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { nav.takeFaster() } })
                    .inSidePanel(panel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if confirmEnd, !nav.arrived {
                // Arriving answers the question: the trip bar's Done takes over.
                EndTripCard(destination: nav.destination.name,
                            onKeep: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { confirmEnd = false } },
                            onEnd: { model.endNavigation() })
                    .inSidePanel(panel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                if let jam = trafficAhead {
                    TrafficLine(ahead: jam)
                        .onTapGesture { withAnimation { nav.dismissWaze() } }
                        .accessibilityHint("Tap to hide")
                        .inSidePanel(panel)
                        .transition(.opacity)
                }
                TripBar(nav: nav, onEnd: {
                    if nav.arrived { model.endNavigation() } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { confirmEnd = true }
                    }
                }, onSteps: { showSteps = true }, onAddStop: { showAlong = true })
                .inSidePanel(panel)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(
            // The road you're on, just under the arrow (the map keeps the arrow at this height while following).
            GeometryReader { g in
                if settings.showNavRoad, nav.following, !nav.arrived, !chipShowing, let road = nav.currentRoad {
                    Text(road)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 12).frame(height: 30)
                        .foregroundColor(.primary)
                        .glass(Capsule())
                        // Between the speed sign and the mute button, which sit level with it now the car is lower.
                        .frame(maxWidth: panel > 0 ? g.size.width - panel - 80 : g.size.width - 240)
                        .position(x: panel + (g.size.width - panel) / 2, y: roadPillY(g.size.height, north: settings.driveLook == .north))
                }
            }
            .ignoresSafeArea()
        )
        .task {
            // Screenshot run: the end trip question.
            if DemoScript.step == "endtrip" {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { confirmEnd = true }
            }
        }
        .alert("Couldn’t add the stop", isPresented: Binding(
            get: { nav.stopFailed }, set: { if !$0 { nav.stopFailed = false } }
        )) {
            Button("OK", role: .cancel) { nav.stopFailed = false }
        }
        .sheet(isPresented: $showParking) {
            ArrivalParkingSheet(model: model, destination: nav.destination).kiteType()
        }
        .sheet(isPresented: $showAlong) {
            AlongRouteSheet(nav: nav).kiteType()
        }
        .sheet(isPresented: $showSteps) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // The things that used to be buttons on the map, out of the way until wanted.
                        HStack(spacing: 10) {
                            tripAction("magnifyingglass", "Find on route") {
                                showSteps = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showAlong = true }
                            }
                            ShareLink(item: etaText) { tripActionLabel("square.and.arrow.up", "Share ETA") }
                                .buttonStyle(.plain)
                            tripAction("arrow.up.left.and.arrow.down.right", "Overview") {
                                showSteps = false
                                model.overviewNav()
                            }
                        }
                        if nav.route.mode == .drive {
                            Button {
                                showMedia.toggle()
                            } label: {
                                Label("Media controls", systemImage: "play.rectangle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            if showMedia { DriveMusicPanel(initiallyExpanded: true) }
                        }
                        tripSummary
                        RoadEventsList(controls: nav.allUpcomingControls, emptyMessage: roadEventsStatus)
                        Text("Steps").font(.headline)
                        StepsList(route: nav.route, from: nav.progress?.nextIndex ?? 0)
                    }
                    .padding(.horizontal, 16)
                }
                .navigationTitle("Your trip")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSteps = false } } }
            }
            .kiteType()
        }
    }

    private var tripSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(nav.destination.name, systemImage: "mappin.circle.fill")
                .font(.headline).lineLimit(2)
            let seconds = nav.progress?.remainingSeconds ?? nav.route.durationSeconds
            let meters = nav.progress?.remainingMeters ?? nav.route.distanceMeters
            Text(L10n.format("%@ · arrive %@", Fmt.distance(meters), Fmt.arrival(seconds)))
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            if let next = nav.stops.first {
                Label(L10n.format("Next stop: %@", next.name), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.subheadline).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Vela.chip(scheme)))
    }

    private func tripAction(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tripActionLabel(icon, title) }.buttonStyle(.plain)
    }

    private func tripActionLabel(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22, weight: .bold))
            Text(L10n.text(title)).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(RoundedRectangle(cornerRadius: 18).fill(Vela.chip(scheme)))
    }
}

/**
 * The next turn, as big as it can be: the real roundabout drawn with every exit and yours lit,
 * the distance, the road, and below it which lane to be in.
 */
struct InstructionBanner: View {
    @ObservedObject var nav: Navigator
    @Environment(\.colorScheme) private var scheme
    @State private var preview = 0

    var body: some View {
        Group {
            if preview > 0, nav.upcomingInstructions.indices.contains(preview) {
                previewCard(nav.upcomingInstructions[preview])
            } else {
                liveBanner
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { gesture in
            let x = gesture.translation.width
            guard abs(x) > abs(gesture.translation.height) * 1.5 else { return }
            let maxIndex = max(0, nav.upcomingInstructions.count - 1)
            preview = max(0, min(maxIndex, preview + (x < 0 ? 1 : -1)))
        })
        .onChange(of: nav.progress?.nextIndex) { _ in preview = 0 }
        .onChange(of: nav.route.id) { _ in preview = 0 }
        .accessibilityAction(named: Text("Repeat instruction")) { nav.repeatInstruction() }
    }

    private func previewCard(_ step: Maneuver) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Upcoming turn", systemImage: maneuverSymbol(step.type)).font(.headline)
                Spacer()
                Button("Back to navigation") { preview = 0 }.font(.subheadline.weight(.semibold))
            }
            Text(Self.headline(step)).font(.title3.weight(.bold)).lineLimit(2)
            let distance = max(0, step.alongMeters - (nav.progress?.alongMeters ?? 0))
            Text(Fmt.distance(distance)).font(.subheadline.monospacedDigit())
            if let lanes = LaneGuide.lanes(for: step, leftTraffic: Geo.drivesOnLeft(step.location)),
               !lanes.lanes.isEmpty {
                LaneStrip(lanes: lanes.lanes, turn: step.type)
            }
        }
        .padding(14)
        .glass(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var liveBanner: some View {
        let m = nav.nextManeuver
        let leftTraffic = Geo.drivesOnLeft(m?.location ?? LatLng(0, 0))
        let refs = RoadRefs.find(m?.instruction ?? "")
        // A long way to the next turn (over 2 miles, on a motorway say): one slim line, and the map gets
        // the room. It grows back to full size well before the first spoken heads-up.
        if nav.route.mode == .drive, let p = nav.progress, p.distanceToNext > 3200, m?.type != .arrive {
            HStack(spacing: 10) {
                Image(systemName: maneuverSymbol(m?.type ?? .straight)).font(.system(size: 22, weight: .heavy))
                    .foregroundColor(Vela.accentText(scheme))
                Text(Fmt.distance(p.distanceToNext)).font(.system(size: 24, weight: .heavy)).monospacedDigit()
                if !refs.isEmpty {
                    ForEach(refs.prefix(2), id: \.self) { RoadShield(ref: $0) }
                } else {
                    Text(Self.split(Self.headline(m))?.1 ?? Self.headline(m))
                        .font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 16).frame(height: 48)
            .foregroundColor(.primary)
            .glass(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("In %@, %@", String(describing: Fmt.distance(p.distanceToNext)), String(describing: Self.headline(m))))
        } else {
            full(m, leftTraffic: leftTraffic, refs: refs)
        }
    }

    /**
     * Navigation HUD 2.0: one strong card with a single hierarchy.

       [maneuver]  [distance]           <- the biggest two things
                   [what to do, road or signed destination]
                   [exit number and destinations, when the data has them]
                   [recommended lanes]
                   [Then: next maneuver in 80 m]

     Everything the driver needs is in one surface; warnings are shown by the
     alert coordinator below, not stacked into this card.
     */
    private func full(_ m: Maneuver?, leftTraffic: Bool, refs: [String]) -> some View {
        let lanes: (lanes: [Lane], words: String)? = {
            guard let m, nav.route.mode == .drive, let p = nav.progress,
                  LaneApproach.showsStrip(distance: p.distanceToNext, speed: nav.speedMps,
                                          laneCount: m.lanes.count, offRoute: p.offRoute) else { return nil }
            return LaneGuide.lanes(for: m, leftTraffic: leftTraffic)
        }()
        return VStack(alignment: .leading, spacing: KiteSpace.s) {
            HStack(alignment: .center, spacing: KiteSpace.s) {
                maneuverTile(m, leftTraffic: leftTraffic)
                VStack(alignment: .leading, spacing: 2) {
                    if let p = nav.progress {
                        Text(Fmt.distance(p.distanceToNext))
                            .font(KiteText.digits(40, weight: .heavy))
                            .foregroundColor(KiteColor.ink)
                            .lineLimit(1).minimumScaleFactor(0.55)
                    } else if let step = m?.distanceMeters, step > 0 {
                        // Before the first matched fix there is no "distance to the
                        // turn" yet; the length of this step is the honest number.
                        Text(Fmt.distance(step))
                            .font(KiteText.digits(40, weight: .heavy))
                            .foregroundColor(KiteColor.ink)
                            .lineLimit(1).minimumScaleFactor(0.55)
                    }
                    if let parts = Self.split(Self.headline(m)) {
                        // "At the end of the road, turn left" small, the road you turn onto big.
                        Text(parts.0)
                            .font(KiteText.label(14)).foregroundColor(KiteColor.inkSecondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text(parts.1)
                            .font(KiteText.headline(22))
                            .foregroundColor(KiteColor.ink)
                            .lineLimit(2).minimumScaleFactor(0.7)
                    } else {
                        Text(Self.headline(m))
                            .font(KiteText.headline(20))
                            .foregroundColor(KiteColor.ink)
                            .lineLimit(2).minimumScaleFactor(0.75)
                    }
                    if m?.exitSign == nil && !refs.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(refs.prefix(4), id: \.self) { RoadShield(ref: $0) }
                        }
                        .padding(.top, 1)
                    }
                }
                Spacer(minLength: 0)
            }

            if let sign = m?.exitSign {
                exitSign(sign, refs: refs)
            }

            if let lanes {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "road.lanes")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(KiteColor.accentText)
                        Text(L10n.text("Recommended lanes"))
                            .font(KiteText.label(13)).foregroundColor(KiteColor.inkSecondary)
                        Spacer(minLength: 0)
                        Text(lanes.words).font(KiteText.label(13))
                            .foregroundColor(KiteColor.ink).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    LaneStrip(lanes: lanes.lanes, turn: m?.type ?? .straight, exitAngle: m?.roundabout.flatMap { shape in
                        shape.exits.indices.contains(shape.taken) ? shape.exits[shape.taken] : nil
                    })
                }
            }

            if let then = nav.thenManeuver {
                thenRow(then)
            }
        }
        .padding(.horizontal, KiteSpace.m)
        .padding(.vertical, KiteSpace.s)
        .background(
            RoundedRectangle(cornerRadius: KiteRadius.sheet, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: KiteRadius.sheet, style: .continuous)
                        .fill(KiteColor.surface.opacity(scheme == .dark ? 0.86 : 0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: KiteRadius.sheet, style: .continuous)
                        .strokeBorder(KiteColor.strokeStrong, lineWidth: 0.75)
                )
                .shadow(color: KiteElevation.high.color, radius: 18, y: 8)
        )
        .accessibilityElement(children: .combine)
    }

    /// The arrow (or the real roundabout) in one tinted tile, so the eye lands there first.
    @ViewBuilder
    private func maneuverTile(_ m: Maneuver?, leftTraffic: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(KiteColor.accentSoft)
            if m?.type == .roundabout {
                RoundaboutDiagram(shape: m?.roundabout, exit: m?.exit ?? 1, clockwise: leftTraffic)
                    .frame(width: 70, height: 70)
            } else {
                Image(systemName: maneuverSymbol(m?.type ?? .straight))
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(KiteColor.accentText)
            }
        }
        .frame(width: 74, height: 74)
        .accessibilityHidden(true)
    }

    /// A motorway-style sign: exit number, road refs, and the real signed destinations.
    private func exitSign(_ sign: ExitSign, refs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let number = sign.number {
                    Text(L10n.format("Exit %@", number))
                        .font(KiteText.label(14))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundColor(Color(hex: 0x0B3B2A))
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white))
                }
                ForEach(Array((sign.references.isEmpty ? refs : sign.references).prefix(3).enumerated()), id: \.offset) { _, reference in
                    RoadShield(ref: reference)
                }
            }
            if !sign.destinations.isEmpty {
                Text(sign.destinations.joined(separator: " · "))
                    .font(KiteText.headline(16))
                    .foregroundColor(.white)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x0B5D3B)))
    }

    /// The next maneuver, kept visible when two turns come close together.
    private func thenRow(_ then: Maneuver) -> some View {
        let close = (nav.thenDistanceMeters ?? .infinity) < 180
        return HStack(spacing: 8) {
            Text(L10n.text("Then"))
                .font(KiteText.label(13))
                .foregroundColor(close ? KiteColor.warning : KiteColor.inkSecondary)
            Image(systemName: maneuverSymbol(then.type))
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(KiteColor.ink)
            if then.type == .roundabout, let n = then.exit {
                Text("\(n)").font(KiteText.label(13)).foregroundColor(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Circle().fill(KiteColor.accent))
            }
            if let meters = nav.thenDistanceMeters, meters >= 10 {
                Text(L10n.format("in %@", Fmt.distance(meters)))
                    .font(KiteText.label(13))
                    .foregroundColor(KiteColor.ink)
            }
            Text(Self.headline(then))
                .font(KiteText.caption())
                .foregroundColor(KiteColor.inkSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(close ? KiteColor.warningSoft : KiteColor.fill)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("Then %@ in %@", Self.headline(then), String(describing: Fmt.distance(nav.thenDistanceMeters ?? 0))))
    }

    /**
     * A long instruction split into what to do and where: "At the end of the road, turn left onto
     * Burgess Road" is "At the end of the road, turn left" and "Burgess Road". Short ones stay whole.
     */
    static func split(_ text: String) -> (String, String)? {
        guard text.count > 26 else { return nil }
        for word in [" onto ", " towards ", " toward "] {
            guard let r = text.range(of: word, options: .backwards) else { continue }
            let place = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
            // "Take the exit toward" keeps its last word, so it still reads as a sentence.
            let action = word == " onto " ? String(text[..<r.lowerBound]) : String(text[..<r.upperBound]).trimmingCharacters(in: .whitespaces)
            guard !place.isEmpty, action.count >= 4 else { continue }
            return (action, place)
        }
        return nil
    }

    /** "6th exit" for a roundabout (the picture says the rest), else the instruction. */
    static func headline(_ m: Maneuver?) -> String {
        guard let m else { return L10n.text("Follow the route") }
        if L10n.isCzech { return CzechNavigation.prompt(m) }
        if m.type == .roundabout, let n = m.exit { return "\(ordinal(n)) exit" }
        return SpokenText.forScreen(m.instruction)
    }

    static func ordinal(_ n: Int) -> String {
        switch n % 100 {
        case 11, 12, 13: return "\(n)th"
        default: break
        }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}

/** Which lanes to show under the turn: the mapped ones, or at a roundabout with none mapped, the Highway Code's. */
enum LaneGuide {
    static func lanes(for m: Maneuver, leftTraffic: Bool) -> (lanes: [Lane], words: String)? {
        if m.lanes.count > 1 { return named(m.lanes) }
        // Google's own advice ("Use the right lane") where the open map has no lanes: words only.
        if let hint = m.laneHint, !hint.localizedCaseInsensitiveContains("any lane"), m.type != .roundabout {
            let words = hint.replacingOccurrences(of: "use the ", with: "", options: .caseInsensitive)
            if L10n.isCzech {
                let lower = words.lowercased()
                if lower == "right lane" { return ([], "Pravý pruh") }
                if lower == "left lane" { return ([], "Levý pruh") }
                if lower == "middle lane" { return ([], "Prostřední pruh") }
            }
            return ([], words.prefix(1).uppercased() + words.dropFirst())
        }
        // The road's painted arrows, Google's advice, or the Highway Code's lanes, as many as the road in has.
        guard m.type == .roundabout, !m.leavesRoundabout, let lanes = m.roundabout?.ruleLanes(leftTraffic: leftTraffic, hint: m.laneHint) else { return nil }
        return named(lanes)
    }

    /** The lanes with words for the good ones, by the edge they touch: two of three on the left are "Left 2 lanes", not "Middle". */
    static func named(_ lanes: [Lane]) -> (lanes: [Lane], words: String)? {
        let valid = lanes.enumerated().filter(\.element.valid).map(\.offset)
        guard lanes.count > 1 else { return nil }
        if valid.count == lanes.count { return (lanes, L10n.text("Any marked lane")) }
        guard let first = valid.first, let last = valid.last else { return (lanes, L10n.text("Lane recommendation unavailable")) }
        let n = lanes.count, count = valid.count, many = count > 1 ? "\(count) lanes" : "lane"
        if last - first + 1 != count {
            let numbers = valid.map { String($0 + 1) }.joined(separator: ", ")
            return (lanes, L10n.format("Lanes %@ from left", numbers))
        }
        if L10n.isCzech {
            if count == 1 && first == 0 { return (lanes, "Levý pruh") }
            if count == 1 && last == n - 1 { return (lanes, "Pravý pruh") }
            if count == 1 { return (lanes, "Pruh číslo \(first + 1) zleva") }
            if first == 0 { return (lanes, "\(count) pruhy vlevo") }
            if last == n - 1 { return (lanes, "\(count) pruhy vpravo") }
            return (lanes, "Prostřední pruhy")
        }
        let words: String
        if first == 0 { words = "Left \(many)" }
        else if last == n - 1 { words = "Right \(many)" }
        else if count == 1 && n > 3 { words = "Lane \(first + 1) from left" }
        else { words = count > 1 ? "Middle lanes" : "Middle lane" }
        return (lanes, words)
    }
}

/**
 * The limit as its road sign with your speed in a small see-through tile under it. The tile turns red
 * when you're over, so that's the only loud thing about it.
 */
struct SpeedBadge: View {
    let mps: Double
    var limitKmh: Double?
    /** A lower limit coming up, shown small above the sign. */
    var coming: LimitDrop?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let metric = Fmt.metric
        let v = Int((mps * (metric ? 3.6 : 2.23694)).rounded())
        // Red once more than a little over the limit.
        let over = limitKmh.map { mps * 3.6 > $0 + 5 } ?? false
        let tile = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let speed = VStack(spacing: -2) {
            Text("\(v)").font(.system(size: 30, weight: .heavy)).monospacedDigit()
                .foregroundColor(over ? .white : .primary)
            Text(metric ? "km/h" : "mph").font(.system(size: 13, weight: .semibold))
                .foregroundColor(over ? .white.opacity(0.85) : Vela.muted(scheme))
        }
        .frame(width: 68, height: 62)
        .background(tile.fill(over ? Vela.closed : Color.clear))
        .glass(tile)
        Group {
            if let limitKmh {
                VStack(spacing: 6) {
                    // The next limit sits in the same column as the signs, never out toward the arrow.
                    if let coming {
                        NextLimitTile(drop: coming)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    SpeedLimitSign(kmh: limitKmh, size: 66)
                    speed
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(v) \(metric ? "kilometres" : "miles") an hour" + (over ? ", over the limit" : "")
                                    + (coming.map { ", limit drops to \(SpeedLimitSign.number($0.kmh)) in \(Fmt.distance($0.meters))" } ?? ""))
            } else {
                speed
            }
        }
        .animation(.easeOut(duration: 0.25), value: over)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: coming != nil)
    }
}

/**
 The next lower limit, a little sign with how far to go under it, in a small tile the width of the
 speed tile below. It counts down, and goes once the new limit starts and takes the big sign's place.
 */
struct NextLimitTile: View {
    let drop: LimitDrop

    var body: some View {
        VStack(spacing: 3) {
            SpeedLimitSign(kmh: drop.kmh, size: 40)
            Text(Fmt.distance(drop.meters))
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundColor(.primary)
        }
        .padding(.top, 8).padding(.bottom, 6)
        .frame(width: 68)
        .glass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/** The posted limit: a US-style white sign in miles, a round red-ringed one in kilometers. */
struct SpeedLimitSign: View {
    let kmh: Double
    var size: CGFloat = 56

    /** The number on the sign. */
    static func number(_ kmh: Double) -> Int { Fmt.metric ? Int(kmh.rounded()) : Fmt.postedMph(kmh) }

    var body: some View {
        if Fmt.metric || Fmt.yards {
            // Round red ring: kilometers on the Continent, miles in Britain.
            Text("\(Fmt.metric ? Int(kmh.rounded()) : Fmt.postedMph(kmh))")
                .font(.system(size: size * 0.4, weight: .heavy))
                .foregroundColor(.black)
                .frame(width: size, height: size)
                .background(Circle().fill(.white))
                .overlay(Circle().inset(by: size * 0.055).stroke(Color(hex: 0xD93025), lineWidth: size * 0.11))
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
        } else {
            // OSM limits in the US are mapped in mph; round back to the posted number.
            let mph = Fmt.postedMph(kmh)
            VStack(spacing: 0) {
                Text("SPEED\nLIMIT").font(.system(size: size * 0.14, weight: .bold)).multilineTextAlignment(.center)
                Text("\(mph)").font(.system(size: size * 0.4, weight: .heavy))
            }
            .foregroundColor(.black)
            .frame(width: size * 0.86, height: size * 1.07)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 6).inset(by: 2).stroke(.black, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
        }
    }
}

/** The bottom card while driving: end, time left (big), and the trip menu. */
/** Asks before ending a trip, in place of the trip bar: two big buttons, easy to hit in a phone holder. */
struct EndTripCard: View {
    let destination: String
    let onKeep: () -> Void
    let onEnd: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("End this trip?").font(.system(size: 24, weight: .heavy))
                Text(L10n.format("to %@", String(describing: destination))).font(.system(size: 16, weight: .medium))
                    .foregroundColor(Vela.muted(scheme)).lineLimit(1)
            }
            HStack(spacing: 12) {
                Button(action: onKeep) {
                    Text("Keep going").font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 60)
                        .foregroundColor(Vela.onAccent(scheme))
                        .background(Capsule().fill(Vela.accent(scheme)))
                }
                Button(action: onEnd) {
                    Text("End trip").font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 60)
                        .foregroundColor(.white)
                        .background(Capsule().fill(Vela.closed))
                }
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.primary)
        .padding(18)
        .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

/**
 * Where the road-name pill sits: just under the car, but on a phone with little height (iPhone mini)
 * that touches the trip bar, so it's kept 8 pt above the bar (64 tall, 4 off the bottom).
 */
private func roadPillY(_ height: CGFloat, north: Bool = false) -> CGFloat {
    let safeBottom = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.bottom ?? 0
    return min(NavGlide.carY(height, north: north) + 46, height - safeBottom - 68 - 8 - 15)
}

/** A word by a map button for a moment after a tap: what it's on now. */
struct ButtonNote: Equatable {
    var title: String
    var detail: String
}

struct TripBar: View {
    @ObservedObject var nav: Navigator
    let onEnd: () -> Void
    let onSteps: () -> Void
    var onAddStop: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let remaining = nav.progress?.remainingSeconds ?? nav.route.durationSeconds
        let meters = nav.progress?.remainingMeters ?? nav.route.distanceMeters
        HStack(spacing: KiteSpace.xs) {
            Button(action: onEnd) {
                Image(systemName: "xmark")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(scheme == .dark ? Color(hex: 0xFCA5A5) : KiteColor.danger)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(KiteColor.danger.opacity(0.10)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End trip")

            VStack(alignment: .leading, spacing: 1) {
                if nav.arrived {
                    Text(L10n.text("Arrived"))
                        .font(KiteText.digits(24, weight: .heavy))
                        .foregroundColor(KiteColor.accentText)
                } else {
                    let arrive = TripBar.arrivalParts(remaining)
                    let left = TripBar.timeParts(remaining)
                    let dist = TripBar.distanceParts(meters)
                    let color = TripBody.delayColor(nav.route, scheme)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        (Text(arrive.time).font(KiteText.digits(25, weight: .heavy))
                            + Text(arrive.suffix).font(KiteText.label(13)))
                            .foregroundColor(color)
                        Text("\(left.value) \(left.unit) · \(dist.value) \(dist.unit)")
                            .font(KiteText.label(15))
                            .foregroundColor(KiteColor.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .monospacedDigit()
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 12, weight: .semibold))
                        Text(nav.destination.name).lineLimit(1)
                        if let stop = nav.stops.first {
                            Text("·").foregroundColor(KiteColor.inkSecondary)
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.system(size: 11, weight: .semibold))
                            Text(stop.name).lineLimit(1)
                        }
                    }
                    .font(KiteText.caption())
                    .foregroundColor(KiteColor.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(nav.arrived ? L10n.text("Arrived") : L10n.format("Arrive at %@, %@, %@ to go",
                String(describing: Fmt.arrival(remaining)),
                String(describing: Fmt.duration(remaining)),
                String(describing: Fmt.distance(meters))))

            if !nav.arrived {
                Button(action: onAddStop) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(KiteColor.accentText)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(KiteColor.accentSoft))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add stop")
            }

            Button(action: onSteps) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KiteColor.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(KiteColor.fill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trip and steps")
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(KiteColor.surface.opacity(scheme == .dark ? 0.88 : 0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(KiteColor.strokeStrong, lineWidth: 0.75)
                )
                .shadow(color: KiteElevation.high.color, radius: 16, y: 6)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    /** "9:18" and " pm" (nothing on a 24 hour clock), so the time stays big and the pm small. */
    static func arrivalParts(_ s: Double) -> (time: String, suffix: String) {
        let f = DateFormatter()
        f.locale = AppSettings.shared.language.locale
        f.timeStyle = .short
        let full = f.string(from: Date().addingTimeInterval(s))
        for sym in [f.amSymbol, f.pmSymbol].compactMap({ $0 }) where !sym.isEmpty && full.contains(sym) {
            let time = full.replacingOccurrences(of: sym, with: "").trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{202F}")))
            return (time, " " + sym.lowercased())
        }
        return (full, "")
    }

    /** "8" min, or "1:20" hr once it's an hour or more. */
    static func timeParts(_ s: Double) -> (value: String, unit: String) {
        let mins = max(1, Int((s / 60).rounded()))
        if mins < 60 { return ("\(mins)", "min") }
        return (String(format: "%d:%02d", mins / 60, mins % 60), L10n.isCzech ? "h" : "hr")
    }

    /** "2.1" and "mi" from "2.1 mi". */
    static func distanceParts(_ m: Double) -> (value: String, unit: String) {
        let s = Fmt.distance(m)
        guard let i = s.lastIndex(of: " ") else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }
}

/** A faster route found on the way, in place of the trip bar: keep yours or take it. Left alone, it expires. */
struct FasterRouteCard: View {
    /** The chips under the title: further or shorter, and any charge it adds. */
    struct Fact: Hashable {
        var text: String
        var icon: String
        var warn: Bool
    }

    static func facts(_ o: FasterOffer) -> [Fact] {
        var out: [Fact] = []
        // Under a quarter of a mile either way isn't worth a word.
        if abs(o.extraMeters) >= 400 {
            let d = Fmt.distance(abs(o.extraMeters))
            out.append(o.extraMeters > 0 ? Fact(text: L10n.format("%@ longer", d), icon: "arrow.left.and.right", warn: true)
                                         : Fact(text: L10n.format("%@ shorter", d), icon: "arrow.left.and.right", warn: false))
        }
        for c in o.newCharges { out.append(Fact(text: c, icon: "sterlingsign.circle.fill", warn: true)) }
        return out
    }

    let offer: FasterOffer
    let onKeep: () -> Void
    let onTake: () -> Void
    @Environment(\.colorScheme) private var scheme
    /** How much of the wait is left, as the bar under the words. */
    @State private var left: CGFloat = 1

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(L10n.format("Faster route · saves %@ min", String(describing: offer.minutes))).font(.system(size: 23, weight: .heavy))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text((offer.via.map { L10n.format("via %@", $0) + " · " } ?? "") + L10n.text("Choose whether to switch")).font(.system(size: 16, weight: .medium))
                    .foregroundColor(Vela.muted(scheme)).lineLimit(1).minimumScaleFactor(0.75)
            }
            // What else changes: only shown when something does, so a plain faster way looks as before.
            if !Self.facts(offer).isEmpty {
                HStack(spacing: 8) {
                    ForEach(Self.facts(offer), id: \.self) { f in
                        Label(f.text, systemImage: f.icon)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .padding(.horizontal, 10).frame(height: 32)
                            .foregroundColor(f.warn ? Vela.warnText(scheme) : .primary)
                            .background(Capsule().fill(f.warn ? Vela.warnFill(scheme) : Vela.chip(scheme)))
                    }
                }
            }
            Capsule().fill(Vela.accent(scheme)).frame(height: 4)
                .scaleEffect(x: left, y: 1, anchor: .leading)
                .onAppear {
                    withAnimation(.linear(duration: max(0.1, offer.until.timeIntervalSinceNow))) { left = 0 }
                }
            HStack(spacing: 12) {
                Button(action: onKeep) {
                    Text("Keep mine").font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 60)
                        .foregroundColor(.primary)
                        .background(Capsule().fill(Vela.chip(scheme)))
                }
                Button(action: onTake) {
                    Text("Take it").font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 60)
                        .foregroundColor(Vela.onAccent(scheme))
                        .background(Capsule().fill(Vela.accent(scheme)))
                }
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.primary)
        .padding(18)
        .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

struct ArrivedCard: View {
    let name: String
    var onPark: (() -> Void)?
    var note: String?
    let done: () -> Void
    @State private var parked = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // The whole card on one row when it fits; on a narrow screen the flag goes first, then the
        // buttons move under the words, so "You've arrived" and the name are never cut short.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { flag; words(fit: true); Spacer(minLength: 0); buttons }
            HStack(spacing: 14) { words(fit: true); Spacer(minLength: 0); buttons }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) { flag; words(fit: false) }
                HStack(spacing: 14) { Spacer(minLength: 0); buttons }
            }
        }
        .foregroundColor(.primary)
        .padding(16)
        .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var flag: some View {
        Image(systemName: "flag.checkered").font(.system(size: 34, weight: .bold)).foregroundColor(Vela.accentText(scheme))
    }

    /** [fit]: at full width or not at all, so the row is only used when nothing is cut short. */
    private func words(fit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("You've arrived").font(.system(size: 26, weight: .heavy)).lineLimit(1).minimumScaleFactor(fit ? 1 : 0.7)
                .fixedSize(horizontal: fit, vertical: false)
            Text(name).font(.system(size: 18, weight: .semibold)).lineLimit(fit ? 1 : 3)
                .fixedSize(horizontal: fit, vertical: !fit)
            if let note { Text(note).font(.subheadline).opacity(0.85).lineLimit(2) }
        }
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            if let onPark, !parked {
                Button { onPark(); parked = true } label: {
                    Image(systemName: "parkingsign").font(.system(size: 22, weight: .bold))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Vela.chip(scheme)))
                }
                .accessibilityLabel("Save parking")
            }
            Button(action: done) {
                Text("Done").font(.system(size: 20, weight: .bold)).lineLimit(1).fixedSize()
                    .padding(.horizontal, 18).frame(height: 56)
                    .foregroundColor(Vela.onAccent(scheme))
                    .background(Capsule().fill(Vela.accent(scheme)))
            }
        }
    }
}

/**
 * The camera warning, the one loud thing on the driving screen: a bright orange pill with the
 * camera, the distance and the limit it checks. It pulses as it appears, and turns red while you're over.
 */
struct CameraCard: View {
    let alert: CameraAlert
    let speedKmh: Double
    /** The limit by the speed badge: when the camera checks the same one, it isn't shown twice. */
    var roadLimitKmh: Double? = nil
    @State private var pulse = false

    var body: some View {
        let over = alert.limitKmh.map { speedKmh > $0 + 3 } ?? false
        // A fixed deep red in both appearances: the adaptive "danger" red is
        // pale in dark mode, and white on pale red is not readable at a glance.
        let fill: Color = over ? Color(hex: 0xB91C1C) : (alert.kind == .speed ? Vela.camera : Color(hex: 0x8E44AD))
        // Dark words on the orange, the way a road sign does it; white on the red and the purple.
        let ink: Color = (!over && alert.kind == .speed) ? Color(hex: 0x1F1300) : .white
        // The limit by the speed badge isn't shown twice.
        let sign: Double? = {
            guard let limit = alert.limitKmh else { return nil }
            if let road = roadLimitKmh, abs(road - limit) <= 1 { return nil }
            return limit
        }()
        // One bright pill, only as wide as it needs: the camera, how far, and the limit it checks.
        HStack(spacing: 10) {
            CameraBadge(kind: alert.kind, size: 40)
            VStack(alignment: .leading, spacing: -2) {
                Text(Fmt.distance(alert.meters)).font(.system(size: 28, weight: .heavy)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(over ? "Slow down" : alert.kind == .speed ? "Speed camera" : "Plate camera")
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            if let sign { SpeedLimitSign(kmh: sign, size: 46) }
        }
        .foregroundColor(ink)
        .padding(.leading, 10).padding(.trailing, sign == nil ? 18 : 8)
        .frame(height: 62)
        .fixedSize()
        .background(Capsule().fill(fill))
        .overlay(Capsule().stroke(Color.white.opacity(pulse ? 0.9 : 0), lineWidth: 3))
        .scaleEffect(pulse ? 1.04 : 1)
        .animation(.easeOut(duration: 0.3), value: over)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .task(id: alert.startMeters) {
            // Two quick pulses when it first shows, so it catches the eye.
            for _ in 0..<2 {
                withAnimation(.easeOut(duration: 0.25)) { pulse = true }
                try? await Task.sleep(nanoseconds: 300_000_000)
                withAnimation(.easeIn(duration: 0.3)) { pulse = false }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }
}

/** A Waze report on the road ahead, as loud as the camera card, in the report's own color. */
struct WazeCard: View {
    let ahead: WazeAhead

    var body: some View {
        let a = ahead.alert
        let left = min(max(ahead.meters / ahead.startMeters, 0), 1)
        let detail = [a.reportedText, a.thumbsUp > 0 ? "\(a.thumbsUp) 👍" : nil, a.street].compactMap { $0 }.joined(separator: " · ")
        let fill = Color(uiColor: MapIcons.wazeColor(a.kind))
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                WazeBadge(kind: a.kind, size: 58)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Fmt.distance(ahead.meters)).font(.system(size: 38, weight: .heavy)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(L10n.text(a.title)).font(.system(size: 21, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(L10n.text(detail)).font(.system(size: 15, weight: .medium)).opacity(0.9).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("Waze").font(.system(size: 13, weight: .heavy)).opacity(0.8)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.3))
                    Capsule().fill(Color.white).frame(width: g.size.width * left)
                }
            }
            .frame(height: 8)
        }
        .foregroundColor(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(fill))
        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
        .accessibilityElement(children: .combine)
    }
}

/**
 * A traffic jam ahead, kept small and calm just over the trip bar: "Standstill traffic in 140 yd".
 * The top of the screen stays for the next turn and the cameras.
 */
struct TrafficLine: View {
    let ahead: WazeAhead
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            WazeBadge(kind: ahead.alert.kind, size: 20)
            Text(L10n.format("%@ in %@", L10n.text(ahead.alert.title), String(describing: Fmt.distance(ahead.meters))))
                .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundColor(scheme == .dark ? Color(hex: 0xFF8A80) : Vela.closed)
        .padding(.horizontal, 14).frame(height: 34)
        .glass(Capsule())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension WazeAlert {
    /** "Reported 12 min ago". */
    var reportedText: String {
        let mins = max(Int(Date().timeIntervalSince(reportedAt) / 60), 0)
        let when = mins < 1 ? "just now" : mins < 60 ? "\(mins) min ago" : mins < 1440 ? "\(mins / 60) h ago" : "\(mins / 1440) d ago"
        return "Reported \(when)"
    }
}

/** A Waze report tapped on the map: what, where, how fresh, how many drivers agree. */
struct WazeInfoCard: View {
    let alert: WazeAlert
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            WazeBadge(kind: alert.kind, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(alert.title)).font(.headline)
                Text([alert.street, alert.reportedText].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    if alert.thumbsUp > 0 {
                        Label(L10n.format("%@ confirmed", String(describing: alert.thumbsUp)), systemImage: "hand.thumbsup.fill")
                    }
                    // Waze's 0-10 trust in the report, as five dots.
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { i in
                            Circle().fill(i < (alert.reliability + 1) / 2 ? Color(uiColor: MapIcons.wazeColor(alert.kind)) : Color.secondary.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .accessibilityLabel(L10n.format("Reliability %@ out of 10", String(describing: alert.reliability)))
                    Text("via Waze")
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(14)
        .glass(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
    }
}

/**
 * Before starting a drive: what Waze drivers have reported along this route right now, like
 * "2 police · 1 crash". Quiet when Waze is off or didn't answer.
 */
struct RouteWazeSummary: View {
    let route: Route
    @ObservedObject private var settings = AppSettings.shared
    @State private var counts: [(WazeAlert.Kind, Int)]?
    /** For the build's screenshots, since Waze turns away the build's computers. */
    static var demo: [(WazeAlert.Kind, Int)]?

    var body: some View {
        // A VStack, not a Group: an empty Group has nothing to hang .task on, so it would never ask.
        VStack(alignment: .leading, spacing: 0) {
            if let counts {
                if counts.isEmpty {
                    Label("No road closures on this route", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(Vela.open)
                } else {
                    WrapLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(counts, id: \.0) { item in
                            let tint = Color(uiColor: MapIcons.wazeColor(item.0))
                            HStack(spacing: 6) {
                                WazeBadge(kind: item.0, size: 24)
                                Text("\(item.1) \(Self.label(item.0, item.1))").font(.system(size: 16, weight: .bold))
                            }
                            .padding(.leading, 6).padding(.trailing, 12)
                            .frame(height: 38)
                            .background(Capsule().fill(tint.opacity(0.18)))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .task(id: route.id) {
            if let demo = Self.demo { counts = demo; return }
            guard settings.wazeOn, route.mode == .drive else { counts = nil; return }
            counts = nil
            guard let found = await Waze.alongRoute(route.polyline) else { return }
            let on = Waze.project(found, on: route.polyline).map(\.alert).filter { settings.shows($0) }
            let grouped = Dictionary(grouping: on, by: \.kind)
            counts = WazeAlert.Kind.allCases.compactMap { k in grouped[k].map { (k, $0.count) } }
        }
    }

    static func label(_ k: WazeAlert.Kind, _ n: Int) -> String {
        switch k {
        case .police: return "police"
        case .accident: return n == 1 ? "crash" : "crashes"
        case .hazard: return n == 1 ? "hazard" : "hazards"
        case .weather: return "weather"
        case .roadworks: return "roadworks"
        case .closure: return n == 1 ? "closure" : "closures"
        case .jam: return n == 1 ? "jam" : "jams"
        }
    }
}

/** The heat map's key, top left of the map while it's on: blue for a few police reports, violet to pink for many. */
struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: 0x8B5CF6))
            Text("Police").font(.caption2.weight(.semibold))
            LinearGradient(colors: [Color(hex: 0x3B82F6), Color(hex: 0x8B5CF6), Color(hex: 0xE879F9)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 54, height: 6).clipShape(Capsule())
            Text("often").font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 10).frame(height: 28)
        .glass(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Police heat map on: brightest where police are reported most often")
    }
}

/** "Police risk: High" over the speed badge, from past and live Waze police reports ahead. */
struct PoliceRiskChip: View {
    let score: Int

    static func color(_ level: PoliceRisk.Level) -> Color {
        switch level {
        case .high: return Color(hex: 0xDC2626)
        case .medium: return Color(hex: 0xF59E0B)
        case .low: return Color(hex: 0x16A34A)
        }
    }

    var body: some View {
        let level = PoliceRisk.level(score)
        let color = Self.color(level)
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 15, weight: .bold))
            Text(L10n.format("Police risk: %@", String(describing: level.rawValue.capitalized))).font(.system(size: 15, weight: .bold))
        }
        .foregroundColor(level == .medium ? Color(hex: 0x1F1300) : .white)
        .padding(.horizontal, 12).frame(height: 36)
        .background(Capsule().fill(color))
        .accessibilityLabel(L10n.format("Police risk %@, %@ out of 100", String(describing: level.rawValue), String(describing: score)))
    }
}

/** The warnings that can take the big card while driving. */
enum NavAlert: Equatable { case camera, waze, average, aircraft }

/** "Also ahead": the warnings waiting their turn, small, in one pill. Tap to peek at the next one. */
struct AlsoAheadPill: View {
    @ObservedObject var nav: Navigator
    let alerts: [NavAlert]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // Two at most, with "+1" for any more. On a small phone the words "Also ahead" go first,
            // then the second warning, so the pill never runs off the screen.
            ViewThatFits(in: .horizontal) {
                row(label: true, shown: 2)
                row(label: false, shown: 2)
                row(label: false, shown: 1)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 14).frame(height: 40)
            .glass(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the next warning")
    }

    private func row(label: Bool, shown: Int) -> some View {
        HStack(spacing: 12) {
            if label { Text("Also ahead").font(.system(size: 15, weight: .medium)).foregroundColor(.secondary) }
            ForEach(alerts.prefix(shown), id: \.self) { item($0) }
            if alerts.count > shown { Text("+\(alerts.count - shown)").font(.system(size: 16, weight: .heavy)) }
        }
        .lineLimit(1)
        .fixedSize()
    }

    @ViewBuilder
    private func item(_ a: NavAlert) -> some View {
        HStack(spacing: 6) {
            switch a {
            case .camera:
                if let c = nav.cameraAhead {
                    CameraBadge(kind: c.kind, size: 24)
                    Text(Fmt.distance(c.meters))
                }
            case .waze:
                if let w = nav.wazeAhead {
                    WazeBadge(kind: w.alert.kind, size: 24)
                    Text(Fmt.distance(w.meters))
                }
            case .average:
                if let c = nav.averageCheck {
                    Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 17, weight: .bold))
                    Text(L10n.format("Avg %@ %@", String(describing: Fmt.speed(c.averageKmh)), String(describing: Fmt.speedUnit)))
                }
            case .aircraft:
                if let air = nav.aircraftNear {
                    Image(systemName: air.aircraft.helicopter ? "fanblades.fill" : "airplane").font(.system(size: 17, weight: .bold))
                    Text(Fmt.distance(air.meters))
                }
            }
        }
        .font(.system(size: 16, weight: .bold)).monospacedDigit()
        .lineLimit(1)
    }
}

/** The aircraft card made small, for when the screen is already full of warnings. */
struct AircraftChip: View {
    let aircraft: PoliceAircraft
    let meters: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: aircraft.helicopter ? "fanblades.fill" : "airplane").font(.system(size: 17, weight: .bold))
            Text("\(aircraft.title) · \(Fmt.distance(meters))").font(.system(size: 16, weight: .bold)).lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14).frame(height: 40)
        .background(Capsule().fill(Color(hex: 0x1E88E5)))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .accessibilityElement(children: .combine)
    }
}

/** A police plane or helicopter nearby: what, how far, how high. */
struct AircraftCard: View {
    let aircraft: PoliceAircraft
    let meters: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let detail = [aircraft.altitudeFeet.map { !Fmt.metric ? "\(Int($0)) ft up" : "\(Int($0 * 0.3048)) m up" },
                      aircraft.callsign ?? aircraft.registration].compactMap { $0 }.joined(separator: " · ")
        HStack(spacing: 12) {
            Image(systemName: aircraft.helicopter ? "fanblades.fill" : "airplane")
                .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x1E88E5)))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.distance(meters)).font(.system(size: 22, weight: .bold)).monospacedDigit()
                    Text(L10n.text(aircraft.title)).font(.headline)
                }
                if !detail.isEmpty { Text(L10n.text(detail)).font(.subheadline).foregroundColor(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Vela.sheet(scheme))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2))
        .accessibilityElement(children: .combine)
    }
}

struct WazeBadge: View {
    let kind: WazeAlert.Kind
    var size: CGFloat = 28

    var body: some View {
        Image(uiImage: MapIcons.waze(kind)).resizable().frame(width: size, height: size)
    }
}

/** Inside an average speed check: your average so far against the limit, and how much is left. */
struct AverageCheckCard: View {
    let check: AverageCheck
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let over = check.limitKmh.map { check.averageKmh > $0 + 2 } ?? false
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(over ? .white : Color(hex: 0xF9AB00))
            VStack(alignment: .leading, spacing: 1) {
                Text("Average speed check").font(.subheadline.weight(.semibold))
                Text(L10n.format("%@ left", String(describing: Fmt.distance(max(check.metersLeft, 0))))).font(.caption)
                    .foregroundColor(over ? .white.opacity(0.9) : .secondary)
            }
            Spacer(minLength: 4)
            VStack(spacing: -2) {
                Text("\(Fmt.speed(check.averageKmh))").font(.system(size: 24, weight: .bold)).monospacedDigit()
                Text(L10n.format("avg %@", String(describing: Fmt.speedUnit))).font(.system(size: 10, weight: .medium))
                    .foregroundColor(over ? .white.opacity(0.9) : .secondary)
            }
            if let limit = check.limitKmh { SpeedLimitSign(kmh: limit) }
        }
        .foregroundColor(over ? .white : .primary)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(over ? Vela.closed : Vela.sheet(scheme))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2))
        .accessibilityElement(children: .combine)
    }
}

struct CameraBadge: View {
    let kind: RoadCamera.Kind
    var size: CGFloat = 28

    var body: some View {
        Image(uiImage: kind == .speed ? MapIcons.speedCamera() : MapIcons.plateCamera())
            .resizable()
            .frame(width: size, height: size)
    }
}

/** Find a stop ahead without leaving navigation: gas, food, coffee… near the road still to drive. */
struct AlongRouteSheet: View {
    @ObservedObject var nav: Navigator
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var found: [(place: Place, ahead: Double)] = []
    @State private var detours: [String: Double] = [:]
    @State private var task: Task<Void, Never>?
    @State private var search = ""
    @State private var searching = false
    @State private var picked: String?

    private let kinds: [(String, String, String)] = [
        (Fmt.yards ? "Petrol" : "Gas", "fuelpump.fill", Fmt.yards ? "petrol station" : "gas station"), ("EV charging", "bolt.car.fill", "ev charging station"),
        ("Coffee", "cup.and.saucer.fill", "coffee"), ("Food", "fork.knife", "restaurants"),
        (Fmt.yards ? "Supermarket" : "Groceries", "cart.fill", Fmt.yards ? "supermarket" : "grocery store"),
        (Fmt.yards ? "Toilets" : "Restrooms", "toilet.fill", Fmt.yards ? "public toilets" : "public restroom"),
        ("Parking", "parkingsign", "parking"), ("Rest areas", "road.lanes", "motorway rest area"), ("Pharmacy", "cross.case.fill", "pharmacy"),
    ]

    var body: some View {
        NavigationView {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(kinds, id: \.0) { k in
                            Button { run(k.2, label: k.0) } label: {
                                Label(k.0, systemImage: k.1)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).frame(height: 40)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(picked == k.0 ? Vela.routeBlue.opacity(0.22) : Color.secondary.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                if searching {
                    HStack { ProgressView(); Text("Looking along your route…").foregroundColor(.secondary) }
                } else if picked != nil && found.isEmpty {
                    Text("Nothing found close to the road ahead.").foregroundColor(.secondary)
                }
                if !found.isEmpty {
                    Section("Ahead on your route") {
                        ForEach(found, id: \.place.id) { f in
                            Button {
                                nav.addStop(f.place)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.place.name).foregroundColor(.primary).lineLimit(1)
                                        HStack(spacing: 6) {
                                            if let r = f.place.rating { Text(String(format: "%.1f ★", r)) }
                                            if let st = f.place.statusText { Text(st).lineLimit(1) }
                                        }
                                        .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(L10n.format("in %@", String(describing: Fmt.distance(f.ahead)))).font(.subheadline.weight(.medium)).foregroundColor(.primary)
                                        if let extra = detours[f.place.id] {
                                            Text(extra < 30 ? "< 1 min extra" : "+\(Fmt.duration(extra))")
                                                .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                                        }
                                        Text("Add stop").font(.caption.weight(.semibold)).foregroundColor(Vela.routeBlue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search along your route")
            .onSubmit(of: .search) {
                let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
                if !term.isEmpty { run(term, label: term) }
            }
            .onDisappear { task?.cancel() }
            .navigationTitle("Search along route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func run(_ query: String, label: String) {
        task?.cancel()
        picked = label
        searching = true
        found = []
        detours = [:]
        let line = nav.route.polyline
        let cum = Geo.cumulative(line)
        let here = nav.progress?.alongMeters ?? 0
        let total = cum.last ?? 0
        // The next stretch of road, up to 40 km: search around its middle, wide enough to cover it.
        let end = min(total, here + 40_000)
        let mid = Geo.point(along: line, meters: (here + end) / 2, cumulative: cum)
        let span = max(end - here, 3_000)
        let useGoogle = settings.googleSearchEnabled
        task = Task {
            let r = await PlaceSearch.search(query, center: mid, spanMeters: span, useGoogle: useGoogle, language: L10n.isCzech ? "cs" : "en")
            guard !Task.isCancelled else { return }
            var out: [(Place, Double)] = []
            for p in r.places {
                let at = Geo.project(p.location, on: line, cumulative: cum)
                // Close to the road (a short detour) and still ahead of you.
                guard at.offset < 800, at.along > here + 100 else { continue }
                out.append((p, at.along - here))
            }
            found = out.sorted { $0.1 < $1.1 }.prefix(12).map { (place: $0.0, ahead: $0.1) }
            searching = false
            for row in found {
                guard !Task.isCancelled else { return }
                let at = here + row.ahead
                let approach = Geo.point(along: line, meters: max(here, at - 600), cumulative: cum)
                let returnPoint = Geo.point(along: line, meters: min(total, at + 800), cumulative: cum)
                async let direct = Directions.routes(from: approach, to: returnPoint, mode: .drive, useGoogle: false)
                async let via = Directions.routes(from: approach, to: returnPoint, mode: .drive, useGoogle: false, via: [row.place.location])
                let (normal, withStop) = await (direct, via)
                guard !Task.isCancelled else { return }
                if let a = normal.routes.first, let b = withStop.routes.first {
                    detours[row.place.id] = max(0, b.durationSeconds - a.durationSeconds)
                }
            }
        }
    }
}

/** Road numbers in an instruction ("I-80", "US 50", "CA 113", "A9"), for shields in the banner. */
enum RoadRefs {
    static func find(_ text: String) -> [String] {
        let pattern = #"\b(I|US|CA|SR|State Route|Route|Hwy|Highway|A|B|M|E|N|D|B|SS)[- ]?(\d{1,4}[A-Z]?)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var out: [String] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let net = ns.substring(with: m.range(at: 1)), num = ns.substring(with: m.range(at: 2))
            let ref: String
            switch net {
            case "I": ref = "I-\(num)"
            case "US": ref = "US \(num)"
            case "CA", "SR", "State Route", "Route", "Hwy", "Highway": ref = "SR \(num)"
            default: ref = net + num
            }
            if !out.contains(ref) { out.append(ref) }
        }
        return Array(out.prefix(3))
    }
}

/** A road number drawn like its sign: Interstate blue-and-red, US white, others a plain plate. */
struct RoadShield: View {
    let ref: String

    var body: some View {
        if ref.hasPrefix("I-") {
            let n = String(ref.dropFirst(2))
            ZStack(alignment: .top) {
                Color(hex: 0x003F87)
                Color(hex: 0xC8102E).frame(height: 9)
                Text(n).font(.system(size: 14, weight: .heavy)).foregroundColor(.white).padding(.top, 10)
            }
            .frame(width: n.count > 2 ? 40 : 32, height: 32)
            .mask(InterstateShape())
            .overlay(InterstateShape().stroke(.white, lineWidth: 1.5))
        } else if ref.hasPrefix("US ") {
            Text(String(ref.dropFirst(3)))
                .font(.system(size: 14, weight: .heavy)).foregroundColor(.black)
                .frame(minWidth: 30).frame(height: 30).padding(.horizontal, 2)
                .background(InterstateShape().fill(.white))
                .overlay(InterstateShape().inset(by: 2).stroke(.black, lineWidth: 1.5))
        } else if let uk = Self.british(ref) {
            // British plates: blue for motorways, green with yellow numbers for primary A roads.
            Text(ref)
                .font(.system(size: 14, weight: .heavy)).foregroundColor(uk == .motorway ? .white : Color(hex: 0xFFD200))
                .padding(.horizontal, 7).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 4).fill(uk == .motorway ? Color(hex: 0x0079C1) : Color(hex: 0x00703C)))
                .overlay(RoundedRectangle(cornerRadius: 4).inset(by: 1.5).stroke(.white, lineWidth: 1))
        } else {
            Text(ref.hasPrefix("SR ") ? String(ref.dropFirst(3)) : ref)
                .font(.system(size: 14, weight: .heavy)).foregroundColor(.black)
                .padding(.horizontal, 7).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 5).inset(by: 1.5).stroke(.black, lineWidth: 1.5))
        }
    }
}

extension RoadShield {
    enum British { case motorway, primary }

    /** "M4" or "A1(M)" are motorways, "A470" a primary road; only where units are British. */
    static func british(_ ref: String) -> British? {
        guard Fmt.yards else { return nil }
        if ref.range(of: #"^(M\d+|A\d+\(M\))$"#, options: .regularExpression) != nil { return .motorway }
        if ref.range(of: #"^A\d+$"#, options: .regularExpression) != nil { return .primary }
        return nil
    }
}

/** A shield outline: flat top with dips, sides curving into a point. */
struct InterstateShape: InsettableShape {
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> InterstateShape { var s = self; s.inset += amount; return s }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.08))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.06), control: CGPoint(x: r.minX + r.width * 0.25, y: r.minY - r.height * 0.04))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.08), control: CGPoint(x: r.maxX - r.width * 0.25, y: r.minY - r.height * 0.04))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX + r.width * 0.05, y: r.minY + r.height * 0.6),
                   control2: CGPoint(x: r.midX + r.width * 0.3, y: r.maxY - r.height * 0.05))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.08), control1: CGPoint(x: r.midX - r.width * 0.3, y: r.maxY - r.height * 0.05),
                   control2: CGPoint(x: r.minX - r.width * 0.05, y: r.minY + r.height * 0.6))
        p.closeSubpath()
        return p
    }
}

struct LaneGuidancePreview: View {
    private var examples: [(String, ManeuverType, [Lane])] {
        [
            ("Motorway exit", .rampRight, [
                Lane(indications: ["straight"], valid: false),
                Lane(indications: ["straight", "slight right"], valid: true),
                Lane(indications: ["slight right"], valid: true),
            ]),
            ("Left turn at a junction", .turnLeft, [
                Lane(indications: ["left"], valid: true),
                Lane(indications: ["straight"], valid: false),
                Lane(indications: ["straight", "right"], valid: false),
            ]),
        ]
    }

    var body: some View {
        List {
            ForEach(Array(examples.enumerated()), id: \.offset) { _, sample in
                Section(L10n.text(sample.0)) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let lanes = LaneGuide.named(sample.2) {
                            Text(lanes.words).font(.subheadline.weight(.bold))
                            LaneStrip(lanes: lanes.lanes, turn: sample.1)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Text("During a drive, the highlighted lanes appear below the next turn as you approach it, where lane data is available.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .kiteList()
        .navigationTitle("Lane guidance preview")
    }
}

/** Which lanes to be in, the way Waze and Google draw it: the right ones lit up, the rest dim. */
struct LaneStrip: View {
    let lanes: [Lane]
    let turn: ManeuverType
    /** At a roundabout: where the exit is (degrees clockwise from straight ahead). */
    var exitAngle: Double?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                let main = pick(lane)
                let alternate = lane.indications.first { direction in direction != main }
                VStack(spacing: 2) {
                    Image(systemName: main == "none" && lane.valid ? "checkmark" : Self.symbol(main))
                        .font(.system(size: lanes.count > 6 ? 17 : 23, weight: .heavy))
                        .foregroundColor(lane.valid ? Vela.onAccent(scheme) : Vela.muted(scheme))
                    if let alternate, lanes.count <= 7 {
                        Image(systemName: Self.symbol(alternate))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(lane.valid ? Vela.onAccent(scheme).opacity(0.78) : Vela.muted(scheme))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(lane.valid ? Vela.accent(scheme) : Color.primary.opacity(0.08)))
                .accessibilityLabel(lane.valid ? Text("Recommended lane") : Text("Other lane"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Use the highlighted lanes")
    }

    /** A lane that goes several ways shows the way this turn goes when it's a good lane. */
    private func pick(_ lane: Lane) -> String {
        guard lane.valid, lane.indications.count > 1 else { return lane.indications.first ?? "none" }
        let want: [String]
        var t = turn
        if t == .roundabout, let a = exitAngle {
            t = a > 200 && a < 340 ? .turnLeft : (a > 20 && a < 160 ? .turnRight : .straight)
        }
        switch t {
        case .turnLeft, .sharpLeft, .rampLeft: want = ["left", "sharp left", "slight left"]
        case .slightLeft, .forkLeft, .keepLeft: want = ["slight left", "left"]
        case .turnRight, .sharpRight, .rampRight: want = ["right", "sharp right", "slight right"]
        case .slightRight, .forkRight, .keepRight: want = ["slight right", "right"]
        case .uturn: want = ["uturn"]
        default: want = ["straight"]
        }
        return want.first { lane.indications.contains($0) } ?? lane.indications[0]
    }

    static func symbol(_ indication: String) -> String {
        switch indication {
        case "left": return "arrow.turn.up.left"
        case "sharp left": return "arrow.turn.left.down"
        case "slight left": return "arrow.up.left"
        case "right": return "arrow.turn.up.right"
        case "sharp right": return "arrow.turn.right.down"
        case "slight right": return "arrow.up.right"
        case "uturn": return "arrow.uturn.down"
        case "none": return "minus"
        default: return "arrow.up"
        }
    }
}

/**
 * The roundabout as it really is: the way in at the bottom, every road around the circle, and
 * only your way round and out lit up. Without the real layout, the exits are spread evenly.
 */
struct RoundaboutDiagram: View {
    let shape: RoundaboutShape?
    let exit: Int
    /** Traffic goes round clockwise (keep-left countries). */
    let clockwise: Bool
    @Environment(\.colorScheme) private var scheme

    private var layout: RoundaboutShape {
        if let shape, shape.exits.indices.contains(shape.taken) { return shape }
        // Evenly spread up to yours, a little short of the full circle.
        let n = max(exit, 1)
        let step = min(90, 300 / Double(n + 1))
        let sign: Double = clockwise ? 1 : -1
        var exits: [Double] = []
        for k in 1...n {
            let a: Double = 180 + sign * Double(k) * step
            exits.append((a + 360).truncatingRemainder(dividingBy: 360))
        }
        return RoundaboutShape(exits: exits, taken: n - 1, clockwise: clockwise, complete: false)
    }

    var body: some View {
        // Your way round in teal, every other road dim, on the see-through strip (dark or light).
        let lit = Vela.accentText(scheme)
        let ink: Color = scheme == .dark ? .white : Color(hex: 0x0F172A)
        Canvas { ctx, size in
            let l = layout
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let ring = size.width * 0.2
            let edge = size.width * 0.47
            func pt(_ deg: Double, _ r: CGFloat) -> CGPoint {
                let a: Double = deg * .pi / 180
                let dx = CGFloat(sin(a)) * r
                let dy = CGFloat(cos(a)) * r
                return CGPoint(x: c.x + dx, y: c.y - dy)
            }
            let faint = GraphicsContext.Shading.color(ink.opacity(0.26))
            let road = StrokeStyle(lineWidth: size.width * 0.075, lineCap: .round)
            // Every road and the circle, dim.
            for a in l.exits + l.entriesOnly + [180] {
                var p = Path()
                p.move(to: pt(a, ring))
                p.addLine(to: pt(a, l.entriesOnly.contains(a) ? edge * 0.85 : edge))
                ctx.stroke(p, with: faint, style: road)
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)), with: faint, style: road)
            // Yours: in from the bottom, round the way traffic goes, and out.
            let out = l.exits[l.taken]
            let sweep = l.turn(l.taken)
            var path = Path()
            path.move(to: pt(180, edge))
            path.addLine(to: pt(180, ring))
            let steps = max(Int(sweep / 6), 2)
            let sign: Double = l.clockwise ? 1 : -1
            for i in 1...steps {
                let f = Double(i) / Double(steps)
                let a: Double = 180 + sign * sweep * f
                path.addLine(to: pt(a, ring))
            }
            let tip = pt(out, edge - size.width * 0.07)
            path.addLine(to: tip)
            ctx.stroke(path, with: .color(lit), style: StrokeStyle(lineWidth: size.width * 0.1, lineCap: .round, lineJoin: .round))
            // The arrowhead on the way out.
            let a = out * .pi / 180
            let dir = CGPoint(x: CGFloat(sin(a)), y: CGFloat(-cos(a)))
            let side = CGPoint(x: -dir.y, y: dir.x)
            let w = size.width * 0.12, len = size.width * 0.14
            let base = CGPoint(x: tip.x - dir.x * 2, y: tip.y - dir.y * 2)
            let nose = CGPoint(x: base.x + dir.x * len, y: base.y + dir.y * len)
            let left = CGPoint(x: base.x + side.x * w, y: base.y + side.y * w)
            let right = CGPoint(x: base.x - side.x * w, y: base.y - side.y * w)
            var head = Path()
            head.move(to: nose)
            head.addLine(to: left)
            head.addLine(to: right)
            head.closeSubpath()
            ctx.fill(head, with: .color(lit))
            // The exit number in the middle, as well as "6th exit" beside the picture.
            let digits = Text("\(exit)")
                .font(.system(size: size.width * (exit >= 10 ? 0.17 : 0.22), weight: .heavy))
                .foregroundColor(ink)
            ctx.draw(digits, at: c)
        }
        .accessibilityLabel(L10n.format("Roundabout, take exit %@", String(describing: exit)))
    }
}
