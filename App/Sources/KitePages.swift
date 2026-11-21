import SwiftUI
import UniformTypeIdentifiers
import VelaCore

/**
 The bar along the bottom: Map, Routes, Saved and Settings.

 One floating surface, four equal targets (72×56 on a phone). The selected page
 gets a soft teal capsule behind its icon and label, so the current page is
 readable at a glance without a second navigation control anywhere else.
 */
struct KiteDock: View {
    @ObservedObject var model: AppModel
    let bottomInset: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 64
    /** How far the dock sits above the screen's bottom edge. */
    static func bottomGap(_ inset: CGFloat) -> CGFloat { max(inset - 12, 10) }

    var body: some View {
        HStack(spacing: 2) {
            item(.map, "map.fill", "Map")
            item(.routes, "arrow.triangle.turn.up.right.diamond.fill", "Routes")
            item(.saved, "bookmark.fill", "Saved")
            item(.settings, "gearshape.fill", "Settings")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(KiteColor.surface.opacity(scheme == .dark ? 0.82 : 0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(KiteColor.strokeStrong, lineWidth: 0.75)
                )
                .shadow(color: KiteElevation.medium.color, radius: 16, y: 6)
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.bottom, Self.bottomGap(bottomInset))
    }

    private func item(_ tab: AppTab, _ icon: String, _ title: String) -> some View {
        let on = model.tab == tab
        return Button {
            if tab != model.tab, model.tab == .settings { model.reloadRoutes() }
            withAnimation(reduceMotion ? nil : KiteMotion.snap) { model.tab = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(L10n.text(title)).font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(on ? KiteColor.accentText : KiteColor.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(on ? KiteColor.accentSoft : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text(title))
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

/**
 The Routes page: start a new journey, carry on the one Kite remembers, or go
 again where you went last. It deliberately does not repeat the map's search
 field; "Plan a route" opens the same field on the map.
 */
struct RoutesPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme
    @State private var importingGPX = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                KiteColor.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: KiteSpace.xl) {
                        header
                        planCard
                        if let trip = model.resumeOffer {
                            resumeCard(trip)
                        }
                        savedJourneys
                        homeWork
                        recent
                        if settings.recentPlaces.isEmpty && settings.savedJourneys.isEmpty {
                            KiteEmptyState(icon: "clock.arrow.circlepath",
                                           title: "No recent journeys yet",
                                           detail: "Places you open or navigate to will be listed here, ready for the next trip.",
                                           actionTitle: "Find a place") { model.requestSearch() }
                        }
                    }
                    .padding(.horizontal, KiteSpace.m)
                    .padding(.top, KiteSpace.s)
                    .padding(.bottom, KiteDock.height + 44)
                }
                KiteDock(model: model, bottomInset: geo.safeAreaInsets.bottom)
            }
        }
        .fileImporter(isPresented: $importingGPX,
                      allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.importGPX(from: url)
            }
        }
    }

    private var savedJourneys: some View {
        VStack(alignment: .leading, spacing: KiteSpace.s) {
            KiteSectionHeader(title: "Saved journeys", actionTitle: "Import GPX") {
                importingGPX = true
            }
            if settings.savedJourneys.isEmpty {
                Text(L10n.text("Save a planned trip from its menu to keep every stop, or import a GPX track. Imported tracks are shown as a route between their ends, not turn-by-turn track guidance."))
                    .font(KiteText.caption()).foregroundColor(KiteColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .kiteCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(settings.savedJourneys.enumerated()), id: \.element.id) { index, journey in
                        if index > 0 { Divider().padding(.leading, 54) }
                        savedJourneyRow(journey)
                    }
                }
                .background(RoundedRectangle(cornerRadius: KiteRadius.card, style: .continuous)
                    .fill(KiteColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: KiteRadius.card, style: .continuous)
                        .strokeBorder(KiteColor.stroke, lineWidth: 1)))
            }
        }
    }

    private func savedJourneyRow(_ journey: SavedJourney) -> some View {
        Button { model.openSavedJourney(journey) } label: {
            HStack(spacing: KiteSpace.s) {
                Image(systemName: journey.isGPXTrack ? "point.topleft.down.to.point.bottomright.curvepath" : "bookmark.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(KiteColor.accentText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(KiteColor.accentSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(journey.displayName).font(KiteText.label(16)).foregroundColor(KiteColor.ink).lineLimit(1)
                    let details: [String?] = [
                        L10n.text(journey.mode.label),
                        journey.stops.isEmpty ? nil : L10n.format("%@ stops", String(journey.stops.count)),
                        journey.isGPXTrack ? L10n.text("GPX track") : nil
                    ]
                    Text(details.compactMap { $0 }.joined(separator: " · "))
                        .font(KiteText.caption()).foregroundColor(KiteColor.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    .foregroundColor(KiteColor.inkSecondary)
            }
            .padding(.horizontal, KiteSpace.m)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("saved-journey-\(journey.id.uuidString)")
        .contextMenu {
            Button { model.reverseSavedJourney(journey) } label: {
                Label("Reverse", systemImage: "arrow.left.arrow.right")
            }
            Button(role: .destructive) { model.deleteSavedJourney(journey) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text("Routes")).font(KiteText.display(34)).foregroundColor(KiteColor.ink)
            Text(L10n.text("Plan, resume or repeat a journey."))
                .font(KiteText.body(15)).foregroundColor(KiteColor.inkSecondary)
        }
    }

    private var planCard: some View {
        Button { model.requestSearch() } label: {
            HStack(spacing: KiteSpace.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(KiteColor.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(KiteColor.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("Where to?")).font(KiteText.headline()).foregroundColor(KiteColor.ink)
                    Text(L10n.text("Search a place, an address or a category"))
                        .font(KiteText.caption()).foregroundColor(KiteColor.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundColor(KiteColor.inkSecondary)
            }
            .kiteCard()
            .contentShape(RoundedRectangle(cornerRadius: KiteRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("Plan a route"))
    }

    private func resumeCard(_ trip: SavedTrip) -> some View {
        VStack(alignment: .leading, spacing: KiteSpace.s) {
            KiteSectionHeader(title: "Carry on", subtitle: trip.destination.name)
            Button { model.resumeTrip() } label: {
                Label("Carry on", systemImage: "location.north.fill")
            }
            .buttonStyle(KitePrimaryButtonStyle(height: 52))
        }
        .kiteCard()
    }

    private var homeWork: some View {
        VStack(alignment: .leading, spacing: KiteSpace.s) {
            KiteSectionHeader(title: "Favourites")
            HStack(spacing: KiteSpace.s) {
                destinationTile("Home", icon: "house.fill", place: settings.home) { model.picking = .home }
                destinationTile("Work", icon: "briefcase.fill", place: settings.work) { model.picking = .work }
            }
        }
    }

    private func destinationTile(_ title: String, icon: String, place: Place?, unset: @escaping () -> Void) -> some View {
        Button {
            if let place { model.openDirections(to: place) } else { unset() }
        } label: {
            VStack(alignment: .leading, spacing: KiteSpace.xs) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(KiteColor.accentText)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(KiteColor.accentSoft))
                Text(L10n.text(title)).font(KiteText.headline(16)).foregroundColor(KiteColor.ink)
                Text(place.map { subtitle($0, title: title) } ?? L10n.text("Tap to set"))
                    .font(KiteText.caption()).foregroundColor(KiteColor.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .kiteCard(padding: KiteSpace.s)
            .contentShape(RoundedRectangle(cornerRadius: KiteRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(place == nil ? "Set \(L10n.text(title))" : "\(L10n.text(title)), \(place?.name ?? "")")
        .accessibilityIdentifier(title == "Home" ? "favourite-home" : "favourite-work")
    }

    /** Never repeat "Home / Home": show the street or category instead. */
    private func subtitle(_ place: Place, title: String) -> String {
        let same = { (value: String) in value.caseInsensitiveCompare(title) == .orderedSame }
        if !same(place.name) { return place.name }
        if let address = place.address, !same(address) { return address }
        if let category = place.category, !same(category) { return category }
        return L10n.text("Tap to go")
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: KiteSpace.s) {
            KiteSectionHeader(title: "Recent", actionTitle: settings.recentPlaces.isEmpty ? nil : "Clear") {
                settings.recentPlaces = []
                settings.recents = []
            }
            if !settings.recentPlaces.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(settings.recentPlaces.prefix(8).enumerated()), id: \.element.id) { index, place in
                        if index > 0 { Divider().padding(.leading, 58) }
                        recentRow(place)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: KiteRadius.card, style: .continuous)
                        .fill(KiteColor.surface)
                        .overlay(RoundedRectangle(cornerRadius: KiteRadius.card, style: .continuous)
                            .strokeBorder(KiteColor.stroke, lineWidth: 1))
                )
            }
        }
    }

    private func recentRow(_ place: Place) -> some View {
        Button { model.openDirections(to: place) } label: {
            HStack(spacing: KiteSpace.s) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(KiteColor.inkSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(KiteColor.fill))
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name).font(KiteText.label(16)).foregroundColor(KiteColor.ink).lineLimit(1)
                    if let detail = place.address ?? place.category {
                        Text(detail).font(KiteText.caption()).foregroundColor(KiteColor.inkSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let here = model.userLatLng {
                    Text(Fmt.distance(here.distance(to: place.location)))
                        .font(KiteText.caption()).foregroundColor(KiteColor.inkSecondary)
                }
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(KiteColor.accentText)
            }
            .padding(.horizontal, KiteSpace.m)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                settings.recentPlaces.removeAll { $0.id == place.id }
            } label: { Label("Remove from recents", systemImage: "trash") }
        }
    }
}

/**
 * Bottom left of the map, with Waze on. One label at most, so the map stays clear: the police risk
 * here, and only when it isn't low. The heat map's key shows for a few seconds after the heat map
 * is switched on, then goes; the count of live reports is on the Layers screen.
 */
struct WazeMapChips: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme
    /** The heat map was just switched on: its key is showing. */
    @State private var legend = false

    var body: some View {
        if settings.wazeOn {
            VStack(alignment: .leading, spacing: 8) {
                if legend, settings.wazeHeatmap, settings.wazePolice { HeatLegend().transition(.opacity) }
                if settings.wazeOn, settings.policeRisk, settings.wazePolice,
                   let risk = model.areaRisk, PoliceRisk.level(risk) != .low {
                    let level = PoliceRisk.level(risk)
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled").font(.system(size: 17, weight: .bold))
                        Text(L10n.format("Police risk: %@", String(describing: level.rawValue.capitalized))).font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(level == .medium ? Color(hex: 0x1F1300) : .white)
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(Capsule().fill(PoliceRiskChip.color(level)))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                    .accessibilityElement(children: .combine)
                }
            }
            .onChange(of: settings.wazeHeatmap) { on in withAnimation { legend = on } }
            // Six seconds once the Layers screen is out of the way, so the key is actually seen.
            .task(id: "\(legend)\(model.showLayers)") {
                guard legend, !model.showLayers else { return }
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { legend = false }
            }
        }
    }
}

/** The Saved page of the dock: Home and Work as big tiles, then every saved place with its own Go. */
struct SavedPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme
    @State private var renaming: Place?
    @State private var newName = ""

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Vela.ground(scheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Saved").font(.system(size: 36, weight: .heavy)).padding(.horizontal, 4)
                        HStack(spacing: 12) {
                            mineTile("house.fill", Vela.routeBlue, "Home", settings.home)
                            mineTile("briefcase.fill", Color(hex: 0x8B5CF6), "Work", settings.work)
                        }
                        if let car = settings.parking {
                            row(car, icon: "parkingsign", color: Vela.routeBlue, editable: false)
                                .background(card)
                        }
                        if settings.saved.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "bookmark").font(.system(size: 40, weight: .semibold)).foregroundColor(Vela.muted(scheme))
                                Text("No saved places yet").font(.title3.weight(.bold))
                                Text("Open any place and tap Save to keep it here.").font(.body).foregroundColor(Vela.muted(scheme))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(settings.saved.enumerated()), id: \.element.id) { i, p in
                                    if i > 0 { Divider().padding(.leading, 78) }
                                    row(p, icon: "bookmark.fill", color: Color(hex: 0xF59E0B), editable: true)
                                }
                            }
                            .background(card)
                            Text("Hold a place to rename or remove it.").font(.subheadline).foregroundColor(Vela.muted(scheme))
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, KiteDock.height + 40)
                }
                KiteDock(model: model, bottomInset: geo.safeAreaInsets.bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .offset(y: geo.safeAreaInsets.bottom)
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") {
                if let p = renaming { settings.renameSaved(p.id, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Vela.surface(scheme))
    }

    private func distance(_ p: Place) -> String? {
        model.userLatLng.map { Fmt.distance($0.distance(to: p.location)) }
    }

    private func mineTile(_ icon: String, _ color: Color, _ title: String, _ place: Place?) -> some View {
        Button {
            if let p = place { go(p) } else {
                model.picking = title == "Home" ? .home : .work
            }
        } label: {
            VStack(alignment: .leading) {
                Image(systemName: icon).font(.system(size: 21, weight: .bold)).foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(place == nil ? Color.gray : color))
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.text(title)).font(.system(size: 21, weight: .bold))
                    Spacer()
                    Text(place.flatMap(distance) ?? (place == nil ? "Set" : "")).font(.system(size: 16, weight: .medium))
                        .foregroundColor(Vela.muted(scheme))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(card)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .contextMenu {
            if place != nil {
                Button { model.picking = title == "Home" ? .home : .work } label: { Label(L10n.format("Change %@", String(describing: title.lowercased())), systemImage: "pencil") }
            }
        }
        .accessibilityLabel(place == nil ? "\(title), not set" : "Go \(title)")
    }

    private func row(_ p: Place, icon: String, color: Color, editable: Bool) -> some View {
        HStack(spacing: 14) {
            Button { show(p) } label: {
                HStack(spacing: 14) {
                    Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(color))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 20, weight: .bold)).lineLimit(2)
                        if let line = [distance(p), p.address ?? p.category].compactMap({ $0 }).first {
                            Text(line).font(.system(size: 16)).foregroundColor(Vela.muted(scheme)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { go(p) } label: {
                Image(systemName: "location.north.fill").font(.system(size: 24, weight: .bold))
                    .foregroundColor(Vela.onAccent(scheme))
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Vela.accent(scheme)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.format("Go to %@", String(describing: p.name)))
        }
        .foregroundColor(.primary)
        .padding(.leading, 14).padding(.trailing, 12)
        .frame(minHeight: 88)
        .contextMenu {
            if editable {
                Button { newName = p.name; renaming = p } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) { settings.saved.removeAll { $0.id == p.id } } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private func go(_ p: Place) {
        model.tab = .map
        model.openDirections(to: p)
    }

    private func show(_ p: Place) {
        model.tab = .map
        model.openSaved(p)
    }
}

/** The Settings page of the dock. */
struct SettingsPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Vela.ground(scheme).ignoresSafeArea()
                SettingsView(settings: settings, model: model, inTab: true, pick: { model.picking = $0 }, onChange: { model.reloadRoutes() })
                    // Inside the page's own lists (the NavigationView swallows an inset put on it from out here).
                    .environment(\.kiteDockSpace, KiteDock.height + 10)
                KiteDock(model: model, bottomInset: geo.safeAreaInsets.bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .offset(y: geo.safeAreaInsets.bottom)
            }
        }
    }
}

/** Choosing home or work: type an address or postcode, or use where you are now. */
struct PlacePicker: View {
    @ObservedObject var model: AppModel
    let kind: PickKind
    @ObservedObject private var settings = AppSettings.shared
    @State private var query = ""
    @State private var found: [Place] = []
    @State private var searching = false
    @State private var task: Task<Void, Never>?
    @State private var locating = false
    @State private var locateTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var title: String { kind == .home ? "Home" : "Work" }
    private var current: Place? { kind == .home ? settings.home : settings.work }

    var body: some View {
        NavigationView {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Button { useHere() } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "location.fill").font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white).frame(width: 40, height: 40)
                                    .background(Circle().fill(Vela.routeBlue))
                                Text("Use where I am now").font(.system(size: 19, weight: .semibold)).foregroundColor(.primary)
                                Spacer()
                                if locating { ProgressView() }
                            }
                        }
                        .disabled(model.userLatLng == nil || locating)
                    } footer: {
                        Text(model.location.denied ? "Location is off for Kite, so type the address instead."
                             : "Or type the address or postcode above.")
                    }
                    if let p = current {
                        Section("Now set to") {
                            row(p)
                            Button(role: .destructive) {
                                if kind == .home { model.setHome(nil) } else { model.setWork(nil) }
                                dismiss()
                            } label: { Label(L10n.format("Remove %@", String(describing: title.lowercased())), systemImage: "trash") }
                        }
                    }
                } else if !found.isEmpty {
                    Section { ForEach(found) { row($0) } }
                } else if searching {
                    HStack(spacing: 10) { ProgressView(); Text("Searching…").foregroundColor(.secondary) }
                } else {
                    Text(Connectivity.explain("Nothing found yet. Keep typing, or try the postcode."))
                        .foregroundColor(.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Address or postcode")
            .onChange(of: query) { q in lookUp(q, full: false) }
            .onSubmit(of: .search) { lookUp(query, full: true) }
            .kiteList()
            .navigationTitle(L10n.format("Set %@", String(describing: title.lowercased())))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            // Cancelled while the address was still loading: don't save it anyway.
            .onDisappear { locateTask?.cancel() }
        }
    }

    private func row(_ p: Place) -> some View {
        Button { pick(p) } label: {
            HStack(spacing: 14) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 26)).foregroundColor(Vela.closed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 18, weight: .semibold)).foregroundColor(.primary).lineLimit(2)
                    if let a = p.address, a != p.name {
                        Text(a).font(.system(size: 15)).foregroundColor(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if let d = model.userLatLng?.distance(to: p.location) {
                    Text(Fmt.distance(d)).font(.system(size: 15)).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func pick(_ p: Place) {
        if kind == .home { model.setHome(p) } else { model.setWork(p) }
        dismiss()
    }

    private func useHere() {
        guard let me = model.userLatLng else { return }
        locating = true
        locateTask = Task {
            let near = await Photon.reverse(me)
            guard !Task.isCancelled else { return }
            var p = Place(id: "\(kind.rawValue):\(me.lat),\(me.lng)", name: near?.name ?? title, location: me, source: "osm")
            p.address = near?.address
            locating = false
            pick(p)
        }
    }

    /** As you type: quick suggestions. On Search: a full search, postcodes included. */
    private func lookUp(_ text: String, full: Bool) {
        task?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { found = []; searching = false; return }
        searching = true
        let center = model.userLatLng ?? model.viewport.center
        let useGoogle = settings.googleSearchEnabled
        task = Task {
            if !full { try? await Task.sleep(nanoseconds: 300_000_000) }
            guard !Task.isCancelled else { return }
            var places: [Place] = []
            if full {
                places = await PlaceSearch.search(q, center: center, spanMeters: 50_000, useGoogle: useGoogle, language: L10n.isCzech ? "cs" : "en").places
            } else {
                if let pc = await Postcodes.lookup(q) { places = [pc] }
                if places.isEmpty, useGoogle {
                    places = (try? await GoogleClient.shared.suggest(q, near: center, spanMeters: 50_000, language: L10n.isCzech ? "cs" : "en"))?.places ?? []
                }
                if places.isEmpty { places = (try? await Photon.search(q, near: center, limit: 10)) ?? [] }
            }
            guard !Task.isCancelled else { return }
            found = Array(places.prefix(20))
            searching = false
        }
    }
}
