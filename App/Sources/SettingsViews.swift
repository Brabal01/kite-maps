import SwiftUI
import VelaCore

struct LayersSheet: View {
    @ObservedObject var settings: AppSettings
    /** How many live Waze reports are on the map now (it used to be a label on the map itself). */
    var liveCount: Int? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Layers").font(.system(size: 26, weight: .heavy))
                Spacer()
                CircleIconButton(icon: "xmark") { dismiss() }
            }
            Text("Map style").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(MapPreset.allCases) { preset in
                    presetTile(preset)
                }
            }
            Text("Map type").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
            HStack(spacing: 14) {
                tile("Default", icon: "map", on: !settings.satellite) { settings.satellite = false }
                tile("Satellite", icon: "globe.americas.fill", on: settings.satellite) { settings.satellite = true }
            }
            Text("Map details").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 14) {
                tile("Traffic", icon: "car.2.fill", on: settings.traffic) { settings.traffic.toggle() }
                tile("Transit", icon: "tram.fill", on: settings.transitLines) { settings.transitLines.toggle() }
                tile("Terrain", icon: "mountain.2.fill", on: settings.terrain) { settings.terrain.toggle() }
                tile("Speed cameras", badge: .speed, on: settings.speedCameras) { settings.speedCameras.toggle() }
                tile("Plate cameras", badge: .plate, on: settings.plateCameras) { settings.plateCameras.toggle() }
                tile("Surveillance", icon: "video.fill", on: settings.surveillanceCameras) { settings.surveillanceCameras.toggle() }
                tile("Road alerts", waze: Waze.shares.contains(.police) ? .police : .closure, on: settings.wazeOn && settings.wazeOnMap) {
                    if settings.waze && settings.wazeOnMap { settings.wazeOnMap = false } else { settings.waze = true; settings.wazeOnMap = true }
                }
                tile("Live cameras", icon: "web.camera.fill", on: settings.liveCams && (settings.liveRoadCams || settings.showsWebcams)) {
                    // On turns road cameras and webcams both back on, even if one was switched off in Settings.
                    if settings.liveCams && (settings.liveRoadCams || settings.showsWebcams) { settings.liveCams = false }
                    else { settings.liveCams = true; settings.liveRoadCams = true; settings.liveWebcams = true }
                }
                if Waze.shares.contains(.police) {
                    tile("Police heat map", icon: "flame.fill", on: settings.wazeOn && settings.wazeHeatmap) {
                        if settings.waze && settings.wazeHeatmap { settings.wazeHeatmap = false } else { settings.waze = true; settings.wazeHeatmap = true }
                    }
                }
            }
            if let n = liveCount, settings.wazeOn, settings.wazeOnMap || settings.wazeHeatmap {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: 0x22C55E)).frame(width: 10, height: 10)
                    Text(L10n.format("Live from Waze · %@ report%@ on the map", String(describing: n), String(describing: n == 1 || L10n.isCzech ? "" : "s"))).font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
        }
        .padding(20)
        .background(Vela.sheet(scheme).ignoresSafeArea())
        .presentationDetents([.height(590)])
    }

    private func presetTile(_ preset: MapPreset) -> some View {
        let on = settings.mapPreset == preset
        return Button { settings.applyMapPreset(preset) } label: {
            VStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.system(size: 23, weight: .semibold))
                    .frame(height: 30)
                Text(L10n.text(preset.title)).font(.caption2.weight(on ? .bold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(on ? Vela.accent(scheme) : .primary)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 12).fill(Vela.chip(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Vela.accent(scheme) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("map-preset-\(preset.rawValue)")
    }

    private func tile(_ title: String, icon: String = "", badge: RoadCamera.Kind? = nil, waze: WazeAlert.Kind? = nil,
                      on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let badge { CameraBadge(kind: badge, size: 34) }
                    else if let waze { WazeBadge(kind: waze, size: 34) }
                    else { Image(systemName: icon).font(.system(size: 26)) }
                }
                    .frame(width: 74, height: 64)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Vela.chip(scheme)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Vela.accent(scheme) : .clear, lineWidth: 3))
                Text(L10n.text(title)).font(.caption.weight(on ? .semibold : .regular))
                    .foregroundColor(on ? Vela.accent(scheme) : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @AppStorage("walkingSpeed") private var walkingSpeed = 5.0
    @AppStorage("safeMode") private var safeModeNext = false
    @ObservedObject var settings: AppSettings
    /** For "Share diagnostics" in About. */
    var model: AppModel? = nil
    /** A page of the dock rather than a sheet: no Done button. */
    var inTab = false
    /** Opens the search for choosing home or work (the dock's page has it). */
    var pick: ((PickKind) -> Void)? = nil
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if DemoScript.step == "wazesettings" {
            // Straight into the Waze screen, for the build's screenshot of it.
            NavigationView { WazeSettingsView(settings: settings) }.navigationViewStyle(.stack)
        } else if DemoScript.step == "mapsettings" {
            // Straight into Map & display, for the screenshot of the map zoom setting.
            NavigationView { mapPage }.navigationViewStyle(.stack)
        } else {
            main
        }
    }

    private var main: some View {
        NavigationView {
            // A short menu like Waze's: a few big rows, each opening a page with its switches.
            Form {
                Section {
                    Picker("Language", selection: $settings.language) {
                        Text("System language").tag(KiteLanguage.system)
                        Text(verbatim: "Čeština").tag(KiteLanguage.czech)
                        Text(verbatim: "English").tag(KiteLanguage.english)
                    }
                    menuRow("Voice & driving", detail: L10n.format("Voice, travel mode, avoid tolls and %@", String(describing: Fmt.yards ? "motorways" : "highways")),
                            icon: "speaker.wave.2.fill", color: 0x0F766E) { drivingPage }
                    menuRow("Cameras & speed", detail: "Camera warnings, speeding alert", icon: "camera.fill", color: 0xDC2626) { camerasPage }
                    menuRow("Road alerts", detail: Waze.shares.contains(.police) ? "Police, crashes, closures" : "Closures, police aircraft",
                            value: settings.wazeOn ? "On" : "Off", icon: "exclamationmark.triangle.fill", color: 0x7C3AED) {
                        WazeSettingsView(settings: settings)
                    }
                    menuRow("Live cameras", detail: "Road camera photos and scenic webcams", value: settings.liveCams ? "On" : "Off",
                            icon: "web.camera.fill", color: 0x0284C7) { liveCamsPage }
                    menuRow("Map & display", detail: "Map presets, HUD, theme, units and zoom", icon: "circle.lefthalf.filled", color: 0x334155) { mapPage }
                    menuRow("Public transport", detail: "Live feeds, discovery and timetable fallback", value: settings.autoTransitFeeds ? "Auto" : nil,
                            icon: "tram.fill", color: 0x7C3AED) { transitPage }
                    menuRow("My places", detail: "Home and work", icon: "house.fill", color: 0x16A34A) { placesPage }
                    menuRow("Privacy", detail: "Use Kite without Google", value: settings.noGoogle ? "On" : nil,
                            icon: "lock.fill", color: 0x475569) { privacyPage }
                    if let model {
                        menuRow("Diagnostics", detail: "Provider checks and a shareable report", icon: "stethoscope", color: 0x0F766E) {
                            DataDiagnosticsView(model: model)
                        }
                    }
                    menuRow("About", detail: "Version " + version, icon: "info.circle.fill", color: 0x64748B) { aboutPage }
                }
            }
            .kiteList()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(inTab ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !inTab {
                        Button("Done") {
                            onChange()
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /** One big row of the menu: an icon, the name, what's inside in small, and the page it opens. */
    private func menuRow<Page: View>(_ title: String, detail: String, value: String? = nil, icon: String, color: UInt32,
                                     @ViewBuilder page: @escaping () -> Page) -> some View {
        NavigationLink {
            page()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: color)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(title)).font(.system(size: 17, weight: .semibold))
                    Text(L10n.text(detail)).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer(minLength: 4)
                if let value { Text(L10n.text(value)).foregroundColor(.secondary) }
            }
            .padding(.vertical, 6)
        }
    }

    private var drivingPage: some View {
        Form {
            Section {
                // Switched here it means everything or nothing: "Alerts only" is the drive screen's button.
                Picker(selection: Binding(
                    get: { VoiceLevel(voice: settings.voice, alertsOnly: settings.voiceAlertsOnly, maneuversOnly: settings.voiceManeuversOnly) },
                    set: { level in
                        let stored = level.storedSwitches
                        settings.voice = stored.voice
                        settings.voiceAlertsOnly = stored.alertsOnly
                        settings.voiceManeuversOnly = stored.maneuversOnly
                    })) {
                    ForEach(VoiceLevel.allCases, id: \.self) { level in
                        Text(L10n.text(level.title)).tag(level)
                    }
                } label: { SettingLabel("Voice guidance", icon: "speaker.wave.2.fill", color: 0x0F766E) }
                Toggle(isOn: $settings.haptics) {
                    SettingLabel("Haptic cues", icon: "iphone.radiowaves.left.and.right", color: 0x7C3AED)
                }
                Picker(selection: $settings.defaultMode) {
                    ForEach(TravelMode.allCases) { Text(L10n.text($0.label)).tag($0) }
                } label: { SettingLabel("Default travel mode", icon: "car.fill", color: 0x2563EB) }
            }
            Section("Routes") {
                NavigationLink {
                    LaneGuidancePreview()
                } label: {
                    SettingLabel("Lane guidance preview", icon: "road.lanes", color: 0x2563EB)
                }
                Toggle(isOn: $settings.suggestFasterRoutes) {
                    SettingLabel("Suggest faster routes", icon: "arrow.triangle.branch", color: 0x0F766E)
                }
                Stepper(value: $walkingSpeed, in: 2...8, step: 0.5) {
                    LabeledContent(L10n.text("Walking speed"), value: "\(walkingSpeed.formatted()) km/h")
                }.onChange(of: walkingSpeed) { _ in model?.refreshWalkingRoutes() }
                Toggle(isOn: $settings.avoidTolls) { SettingLabel("Avoid tolls", icon: "sterlingsign.circle.fill", color: 0xF59E0B) }
                Toggle(isOn: $settings.avoidHighways) {
                    SettingLabel(Fmt.yards ? "Avoid motorways" : "Avoid highways", icon: "road.lanes", color: 0x1D4ED8)
                }
            }
        }
        .kiteList()
        .navigationTitle("Voice & driving")
    }

    private var transitPage: some View {
        Form {
            Section {
                TextField("GTFS-Realtime feed URL", text: $settings.gtfsRealtimeURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Toggle("Discover public live feeds", isOn: $settings.autoTransitFeeds)
            } header: {
                Text("Live transit")
            } footer: {
                Text("Optional. Any public GTFS-Realtime feed can add delays, service alerts and vehicle positions to the Transitous timetable. With discovery on, Kite checks the keyless Mobility Database catalog for an active feed covering the journey. Feeds that need an API key are never used, and a failed feed falls back to the timetable.")
            }
            Section {
                LabeledContent("Planner", value: "Transitous")
                LabeledContent("Live data", value: settings.autoTransitFeeds ? "Automatic discovery" : "Planner data only")
                LabeledContent("Fallback", value: "Scheduled timetable")
            } footer: {
                Text("Live delays are matched by feed, agency, trip, route, direction, service date and stop sequence. A feed that does not match is ignored rather than attached to the wrong vehicle.")
            }
        }
        .kiteList()
        .navigationTitle("Public transport")
    }

    private var camerasPage: some View {
        Form {
            Section("Warnings") {
                Toggle(isOn: $settings.cameraWarnings) { SettingLabel("Say when a speed camera is ahead", icon: "speaker.wave.3.fill", color: 0xDC2626) }
                Toggle(isOn: $settings.speedingAlert) { SettingLabel("Say when I'm over the speed limit", icon: "gauge.with.dots.needle.67percent", color: 0xEA580C) }
            }
            Section {
                Toggle(isOn: $settings.speedCameras) { SettingLabel("Speed cameras", icon: "camera.fill", color: 0xDC2626) }
                Toggle(isOn: $settings.surveillanceCameras) { SettingLabel("Surveillance cameras", icon: "video.fill", color: 0x16A34A) }
                Toggle(isOn: $settings.plateCameras) {
                    SettingLabel(Fmt.yards ? "Number plate cameras" : "License plate cameras", icon: "number", color: 0x6B7280)
                }
            } header: {
                Text("Show on the map and route")
            } footer: {
                Text("Camera locations come from OpenStreetMap, and speed cameras from Waze's map too while Road alerts are on. General surveillance cameras are not necessarily plate readers and are shown only on the map. Some countries, like France and Germany, don't allow warnings of speed cameras, so check before you turn the voice on there.")
            }
        }
        .kiteList()
        .navigationTitle("Cameras & speed")
    }

    private var liveCamsPage: some View {
        Form {
            Section {
                Toggle(isOn: $settings.liveCams) { SettingLabel("Live cameras", icon: "web.camera.fill", color: 0x0284C7) }
            } footer: {
                Text("See the latest photo from traffic cameras and webcams: tap a camera on the map, or look at the ones on your route before you go. Never shown while you're driving.")
            }
            if settings.liveCams {
                Section {
                    Toggle(isOn: $settings.liveRoadCams) { SettingLabel("Road cameras (UK)", icon: "car.fill", color: 0x0284C7) }
                    Toggle(isOn: $settings.liveWebcams) { SettingLabel("Scenic webcams", icon: "sun.horizon.fill", color: 0x7C3AED) }
                        .disabled(!WindyKey.present)
                    Toggle(isOn: $settings.liveCamsOnRoute) { SettingLabel("Cameras on your route", icon: "point.topleft.down.curvedto.point.bottomright.up.fill", color: 0x0F766E) }
                } header: {
                    Text("Show")
                } footer: {
                    Text(WindyKey.present
                         ? "Road cameras: National Highways, Transport for London, Traffic Scotland, Traffic Wales and TrafficWatch NI, listed by OpenHighways. Webcams: Windy.com, worldwide."
                         : "Road cameras: National Highways, Transport for London, Traffic Scotland, Traffic Wales and TrafficWatch NI, listed by OpenHighways. Scenic webcams aren't set up in this version of Kite yet.")
                }
                if let status = LiveCamStore.shared.status {
                    Section { LabeledContent("Camera list", value: status) }
                }
            }
        }
        .kiteList()
        .navigationTitle("Live cameras")
    }

    private var mapPage: some View {
        Form {
            if !settings.noGoogle {
                Section("Google Places") {
                    Toggle("Search places with Google Maps", isOn: $settings.preferGoogleSearch)
                    PlacesKeySettings()
                }
            }
            Section {
                TextField("GTFS-Realtime feed URL", text: $settings.gtfsRealtimeURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Toggle("Discover public live feeds", isOn: $settings.autoTransitFeeds)
            } header: {
                Text("Live transit")
            } footer: {
                Text("Optional. Any public GTFS-Realtime feed can add delays, service alerts and vehicle positions to the Transitous timetable. Leave empty to use the planner's own live data. With discovery on, Kite checks the keyless Mobility Database catalog for an active feed covering the journey area. Feeds that need an API key are never used, and a failed feed falls back to the timetable.")
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    ForEach(MapPreset.allCases) { preset in
                        Button { settings.applyMapPreset(preset) } label: {
                            VStack(spacing: 5) {
                                Image(systemName: preset.icon).font(.system(size: 21, weight: .semibold))
                                Text(L10n.text(preset.title)).font(.caption.weight(.semibold)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .foregroundColor(settings.mapPreset == preset ? KiteColor.onAccent : KiteColor.ink)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(settings.mapPreset == preset ? KiteColor.accent : KiteColor.fill))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings-map-preset-\(preset.rawValue)")
                    }
                }
            } header: {
                Text("Map style")
            } footer: {
                Text("Classic is the full map. Navigation keeps roads and buildings but removes distractions. Minimal is the quietest. Explore adds places and transit; Outdoors adds terrain and paths; Satellite uses imagery. Apple Maps supports the same POI and building choices, not every MapLibre detail.")
            }
            Section("Map background") {
                Toggle("Apple Maps", isOn: $settings.useAppleMaps)
            }
            Section("Mapbox") {
                MapboxSettings(settings: settings)
                    .disabled(settings.useAppleMaps)
            }
            Section {
                Picker(selection: $settings.theme) {
                    ForEach(ThemeMode.allCases) { Text(L10n.text($0.label)).tag($0) }
                } label: { SettingLabel("Theme", icon: "circle.lefthalf.filled", color: 0x334155) }
                Picker(selection: $settings.units) {
                    ForEach(UnitsMode.allCases) { Text(L10n.text($0.label)).tag($0) }
                } label: { SettingLabel("Distance units", icon: "ruler.fill", color: 0x0891B2) }
            }
            Section {
                ForEach(QuickActionKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { settings.quickActions.contains(kind) },
                        set: { on in setQuickAction(kind, on) }
                    )) {
                        SettingLabel(L10n.text(kind.title), icon: kind.icon, color: 0x0F766E)
                    }
                    .disabled(settings.quickActions.count == 1 && settings.quickActions.contains(kind))
                }
            } header: {
                Text("Shortcuts on the map")
            } footer: {
                Text("Shown under the search field. Tap a shortcut's own checkbox to add it back. The order follows the order you add them in; hiding a shortcut keeps its place in your saved data.")
            }
            Section {
                Picker(selection: $settings.hudMode) {
                    ForEach(HUDMode.allCases) { mode in
                        Text(L10n.text(mode.title)).tag(mode)
                    }
                } label: {
                    SettingLabel("Navigation HUD", icon: "rectangle.topthird.inset.filled", color: 0x0F766E)
                }
                Text(L10n.text(settings.hudMode.detail)).font(.caption).foregroundColor(.secondary)
                if settings.hudMode == .custom {
                    Toggle("Show lane guidance", isOn: $settings.hudCustomLanes)
                    Toggle("Show the next turn", isOn: $settings.hudCustomThen)
                    Toggle("Show junction diagrams", isOn: $settings.hudCustomJunction)
                }
                NavigationLink { HUDPreview() } label: {
                    SettingLabel("Live HUD preview", icon: "eye.fill", color: 0x2563EB)
                }
            } header: {
                Text("Navigation HUD 3.0")
            } footer: {
                Text("Simple keeps only the next turn. Advanced adds lanes, signs and the follow-up turn. Highway shows lane and exit guidance earlier. Custom uses your own choices.")
            }
            Section {
                Toggle(isOn: $settings.navBuildings) {
                    SettingLabel("Buildings while navigating", icon: "building.2.fill", color: 0x64748B)
                }
                VStack(alignment: .leading, spacing: 10) {
                    SettingLabel("Map zoom while driving", icon: "plus.magnifyingglass", color: 0x0F766E)
                    Picker("Map zoom while driving", selection: $settings.mapZoom) {
                        ForEach(MapZoom.allCases, id: \.self) { Text(L10n.text($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
                Picker("Navigation arrow size", selection: $settings.navArrowScale) {
                    Text("Small").tag(0.75)
                    Text("Normal").tag(1.0)
                    Text("Large").tag(1.35)
                }
                Toggle("Show speedometer", isOn: $settings.showNavSpeed)
                if settings.showNavSpeed {
                    Picker("Speedometer side", selection: $settings.speedOnRight) {
                        Text("Left").tag(false)
                        Text("Right").tag(true)
                    }
                }
                Toggle("Show current road name", isOn: $settings.showNavRoad)
                Toggle("Announce lower speed limits", isOn: $settings.speakLimitDrops)
                Toggle("Media controls", isOn: $settings.showMusicControls)
                HStack {
                    if settings.showNavSpeed && !settings.speedOnRight { Text("58").font(.headline.monospacedDigit()) }
                    Spacer()
                    VStack {
                        Image(systemName: "location.north.fill").font(.system(size: 25 * settings.navArrowScale))
                        if settings.showNavRoad { Text("Current road").font(.caption) }
                    }.foregroundColor(Vela.routeBlue)
                    Spacer()
                    if settings.showNavSpeed && settings.speedOnRight { Text("58").font(.headline.monospacedDigit()) }
                }
                .accessibilityLabel("Navigation layout preview")
            } header: {
                Text("While driving")
            } footer: {
                Text("Kite still zooms in for turns and out on long roads. Closer shows the streets bigger; Wider shows more road ahead. Normal is how Kite has always been.")
            }
        }
        .kiteList()
        .navigationTitle("Map & display")
    }

    private func setQuickAction(_ kind: QuickActionKind, _ on: Bool) {
        if on {
            guard !settings.quickActions.contains(kind) else { return }
            settings.quickActions.append(kind)
        } else {
            guard settings.quickActions.count > 1 else { return }
            settings.quickActions.removeAll { $0 == kind }
        }
    }

    private var placesPage: some View {
        Form {
            Section {
                if let pick {
                    Button { pick(.home) } label: {
                        LabeledContent { Text(settings.home?.name ?? "Set") } label: { SettingLabel("Home", icon: "house.fill", color: 0x16A34A) }
                    }
                    .foregroundColor(.primary)
                    Button { pick(.work) } label: {
                        LabeledContent { Text(settings.work?.name ?? "Set") } label: { SettingLabel("Work", icon: "briefcase.fill", color: 0x9333EA) }
                    }
                    .foregroundColor(.primary)
                } else {
                    if let h = settings.home {
                        LabeledContent { Text(h.name) } label: { SettingLabel("Home", icon: "house.fill", color: 0x16A34A) }
                        Button("Remove home", role: .destructive) { settings.home = nil }
                    }
                    if let w = settings.work {
                        LabeledContent { Text(w.name) } label: { SettingLabel("Work", icon: "briefcase.fill", color: 0x9333EA) }
                        Button("Remove work", role: .destructive) { settings.work = nil }
                    }
                    if settings.home == nil && settings.work == nil {
                        Text("Set home and work from the Saved page.").foregroundColor(.secondary)
                    }
                }
            }
        }
        .kiteList()
        .navigationTitle("My places")
    }

    private var privacyPage: some View {
        Form {
            Section {
                Toggle(isOn: $settings.noGoogle) { SettingLabel("Use Kite without Google", icon: "lock.fill", color: 0x475569) }
            } footer: {
                Text("Off (the usual): search, place details, routes and live traffic come from Google, asked anonymously with no account. On: everything comes from free open-data services instead and nothing goes to Google, but search and routes are less complete.")
            }
        }
        .kiteList()
        .navigationTitle("Privacy")
    }

    private var aboutPage: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                Link("Kite Maps on GitHub", destination: URL(string: "https://github.com/matteofx1/kite-maps")!)
                Link("Based on Vela Maps for Android", destination: URL(string: "https://github.com/PimpinPumpkin/Vela")!)
                Link("Live Waze reports the way SABRE Plus gets them (MIT)", destination: URL(string: "https://github.com/nicglazkov/highway-radar-sabre-plus")!)
                Text("Free software under the GPL-3.0. Map © OpenFreeMap, OpenMapTiles, OpenStreetMap contributors. Routing © FOSSGIS OSRM. Imagery © Esri.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section {
                Toggle("Start in safe mode next time", isOn: $safeModeNext)
            } footer: {
                Text("Safe mode skips the map, navigation, location updates, live transit and background services. It is for diagnosing a launch crash; close Kite completely after changing this.")
            }
            if let model {
                Section {
                    NavigationLink { DataDiagnosticsView(model: model) } label: {
                        Label("Share diagnostics", systemImage: "doc.text.magnifyingglass")
                    }
                } footer: {
                    Text("Makes a small file to send with a bug report.")
                }
            }
            Section {
                Link("Surveillance cameras, saved-place matching, GPS warnings and diagnostics from Ausbloke's Kite fork", destination: URL(string: "https://github.com/NotDiscordOfficial/kite-maps")!)
                Link("UK road camera list from OpenHighways (MIT)", destination: URL(string: "https://github.com/JamesDillonDev/openhighways")!)
                Link("Webcams provided by Windy.com", destination: URL(string: "https://www.windy.com/webcams")!)
            } header: { Text("Thanks to") }
        }
        .kiteList()
        .navigationTitle("About")
    }
}

/** A settings row's name with a small coloured icon in front, like the iPhone's own Settings. */
struct SettingLabel: View {
    let title: String
    let icon: String
    let color: UInt32

    init(_ title: String, icon: String, color: UInt32) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 29, height: 29)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: color)))
            Text(L10n.text(title))
        }
    }
}

/** Settings › Road alerts: which live Waze reports to show and warn about, the police heat map and police aircraft. */
struct WazeSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var remembered = 0
    @State private var confirmClear = false

    private let kinds: [(WazeAlert.Kind, String)] = [
        (.police, "Police and mobile speed traps"),
        (.accident, "Crashes"),
        (.hazard, "Hazards (stopped cars, objects, potholes)"),
        (.weather, "Weather (fog, ice, flooding)"),
        (.roadworks, "Roadworks"),
        (.closure, "Road closures"),
        (.jam, "Traffic jams reported by drivers"),
    ]

    private let ages: [(Int, String)] = [(30, "30 minutes"), (60, "1 hour"), (120, "2 hours"), (240, "4 hours"), (0, "Keep them all")]

    /** Whether Waze answered last time, so it's easy to tell when it has stopped working. */
    private var connection: (text: String, color: Color) {
        guard let s = Waze.lastStatus else { return ("Closures: checked once you open the map at city zoom", .gray) }
        let mins = Int(Date().timeIntervalSince(s.at) / 60)
        let when = mins < 1 ? "just now" : "\(mins) min ago"
        switch s.code {
        case 200: return ("Closures working: \(s.count) reports, \(when)", Color(hex: 0x188038))
        case 0: return ("Closures: no connection (\(when))", .orange)
        case 401, 403: return ("Closures: Waze turned Kite away (\(when)). It may work again later.", .red)
        case -1: return ("Closures: Waze sent something Kite can't read (\(when))", .red)
        default: return ("Closures: Waze error \(s.code) (\(when))", .orange)
        }
    }

    /** How Waze's app servers answered last time (police, crashes and the rest). */
    private var live: (text: String, color: Color) {
        guard let s = WazeLive.lastStatus else { return ("Driver reports: checked once you open the map at city zoom", .gray) }
        let mins = Int(Date().timeIntervalSince(s.at) / 60)
        let when = mins < 1 ? "just now" : "\(mins) min ago"
        switch s.code {
        case 200: return ("Driver reports working: \(s.summary), \(when)", Color(hex: 0x188038))
        case 0: return ("Driver reports: no connection (\(when))", .orange)
        case 401: return ("Driver reports: Waze turned Kite away (\(when)). It may work again later.", .red)
        case 440: return ("Driver reports: reconnecting to Waze (\(when))", .orange)
        case -1: return ("Driver reports: Waze sent something Kite can't read (\(when))", .red)
        default: return ("Driver reports: Waze error \(s.code) (\(when))", .orange)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use Waze reports", isOn: $settings.waze).disabled(settings.noGoogle)
            } footer: {
                Text(settings.noGoogle
                     ? "Off while \"Use Kite without Google\" is on, since Waze belongs to Google."
                     : "Kite asks Waze for drivers' reports the way the Waze app does, for the map on screen and along your route, with an anonymous account Waze makes for it (no name, email or phone). Closures also come from the Waze live map. Waze sees roughly where you are, anonymously. It doesn't allow other apps to do this, so it may stop working one day.")
            }
            if settings.wazeOn {
                Section {
                    HStack(spacing: 8) {
                        Circle().fill(connection.color).frame(width: 10, height: 10)
                        Text(L10n.text(connection.text)).font(.subheadline)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(live.color).frame(width: 10, height: 10)
                        Text(L10n.text(live.text)).font(.subheadline)
                    }
                    if let s = Waze.lastStatus, s.code == 200 {
                        // What Waze actually sent, so it's easy to see if a kind has gone missing.
                        LabeledContent("Closures, last answer", value: s.summary).font(.subheadline)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    if let s = Waze.lastStatus, s.code != 200 {
                        // What the hidden live map page saw, to send to whoever looks into it.
                        Text(L10n.format("Details: %@", WazeWeb.shared.note)).font(.caption2.monospaced())
                    }
                }
                Section("Show and warn about") {
                    // Only what Waze still shares (see Waze.shares): no switches that can't do anything.
                    ForEach(kinds.filter { Waze.shares.contains($0.0) }, id: \.0) { item in
                        let k = item.0
                        Toggle(isOn: Binding(
                            get: { settings.wazeKinds.contains(k) },
                            set: { on in if on { settings.wazeKinds.insert(k) } else { settings.wazeKinds.remove(k) } }
                        )) {
                            HStack(spacing: 10) {
                                WazeBadge(kind: k, size: 26)
                                Text(L10n.text(item.1))
                            }
                        }
                    }
                }
                Section {
                    Toggle("Show reports on the map", isOn: $settings.wazeOnMap)
                    Toggle("Chime and say them while navigating", isOn: $settings.wazeVoice)
                    Picker("Ignore reports older than", selection: $settings.wazeMaxAge) {
                        ForEach(ages, id: \.0) { Text(L10n.text($0.1)).tag($0.0) }
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("While navigating, a card pops up for reports on your route, only ones made by drivers going your way.")
                }
                if Waze.shares.contains(.police) {
                    Section {
                        Toggle("Police heat map", isOn: $settings.wazeHeatmap)
                        Toggle("Police risk score while driving", isOn: $settings.policeRisk)
                        LabeledContent("Police reports remembered", value: "\(remembered)")
                        if remembered > 0 {
                            Button("Forget them all", role: .destructive) { confirmClear = true }
                        }
                    } footer: {
                        Text("Heat map: where police get reported most, across the whole UK, from Highway Radar's own map (built from its drivers' reports; it may stop working one day). Risk score: low, medium or high for the road ahead (counting reports made at this time of day most), from the Waze reports Kite remembers on this phone, for 90 days and never anywhere else.")
                    }
                }
            }
            Section {
                Toggle("Police planes and helicopters", isOn: $settings.policeAircraft)
            } header: {
                Text("Aircraft")
            } footer: {
                Text("While navigating, warns when a police aircraft is within about 10 km, from open flight tracking (adsb.lol), not Waze. It spots them by their police callsign (like NPAS in the UK), and some don't broadcast at all, so no warning doesn't mean the sky is clear.")
            }
        }
        .kiteList()
        .navigationTitle("Road alerts")
        .onAppear { remembered = WazeHistory.shared.sightings.count }
        .confirmationDialog(L10n.format("Forget the %@ police reports Kite remembered? The risk score starts again from nothing.", String(describing: remembered)),
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Forget them", role: .destructive) {
                WazeHistory.shared.clear()
                remembered = 0
            }
        }
    }
}

/** A simulated HUD screen, so the density choice can be seen before a drive. */
struct HUDPreview: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme

    private var sample: Maneuver {
        Maneuver(type: .rampRight, instruction: "Take exit 8 towards Oxford",
                 location: LatLng(51.5, -0.1), alongMeters: 300, distanceMeters: 220,
                 lanes: [Lane(indications: ["straight"], valid: false),
                         Lane(indications: ["slight right"], valid: true),
                         Lane(indications: ["right"], valid: true)],
                 exit: 8)
    }

    var body: some View {
        let hud = settings.hudProfile
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text(settings.hudMode.title)).font(KiteText.title())
                Text(L10n.text(settings.hudMode.detail))
                    .font(KiteText.body(15)).foregroundColor(KiteColor.inkSecondary)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 38, weight: .heavy))
                            .foregroundColor(KiteColor.accentText)
                            .frame(width: 68, height: 68)
                            .background(RoundedRectangle(cornerRadius: 18).fill(KiteColor.accentSoft))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("300 m").font(KiteText.digits(38, weight: .heavy))
                            Text("Take exit 8 towards Oxford")
                                .font(KiteText.headline(20)).lineLimit(2)
                        }
                    }
                    if hud.showJunction {
                        HStack(spacing: 8) {
                            Text("Exit 8").font(KiteText.label(13))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .foregroundColor(Color(hex: 0x0B3B2A))
                                .background(RoundedRectangle(cornerRadius: 5).fill(.white))
                            Text("M40 · Oxford · Bicester").font(KiteText.headline(15))
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x0B5D3B)))
                        .foregroundColor(.white)
                    }
                    if hud.showLanes,
                       let guide = LaneGuidanceEngine.guide(for: sample, distance: 300,
                                                            speed: 28, offRoute: false,
                                                            leftTraffic: false) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.text(guide.title)).font(KiteText.caption())
                                .foregroundColor(KiteColor.inkSecondary)
                            LaneStrip(lanes: guide.lanes.map { Lane(indications: $0.indications,
                                                                    valid: $0.use == .recommended) },
                                      turn: .rampRight)
                        }
                    }
                    if hud.showThen {
                        HStack(spacing: 8) {
                            Text("Then").font(KiteText.label(13)).foregroundColor(KiteColor.warning)
                            Image(systemName: "arrow.turn.up.left").font(.system(size: 16, weight: .heavy))
                            Text("in 120 m · A40").font(KiteText.caption())
                            Spacer()
                        }
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(KiteColor.warningSoft))
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(KiteColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(KiteColor.stroke, lineWidth: 1))
                .shadow(color: KiteElevation.medium.color, radius: 12, y: 5)

                Text("This preview uses made-up junction data; the live banner only draws a diagram when the route supplies real signs or lanes.")
                    .font(KiteText.caption()).foregroundColor(KiteColor.inkSecondary)
            }
            .padding(KiteSpace.m)
        }
        .background(KiteColor.canvas.ignoresSafeArea())
        .navigationTitle("HUD preview")
    }
}
