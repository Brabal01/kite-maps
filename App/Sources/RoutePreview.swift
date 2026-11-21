import SwiftUI
import VelaCore

/**
 A planning-time walk through the route. It moves the map camera to each manoeuvre and shows the
 information Kite actually has (maneuver, lanes, roundabout exit, mapped road events). It is a preview
 of a plan: it never creates a GPS source and never starts navigation, so it cannot be confused with
 the developer GPS replay in Diagnostics.
 */
struct RoutePreviewSheet: View {
    @ObservedObject var model: AppModel
    let route: Route
    @State private var index = 0
    @State private var walking = false
    @Environment(\.dismiss) private var dismiss

    private var steps: [Maneuver] { route.maneuvers.filter { !$0.silent } }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                if steps.isEmpty {
                    Text(L10n.text("This route has no listed manoeuvres.")).foregroundColor(.secondary)
                } else {
                    Picker("Manoeuvre", selection: $index) {
                        ForEach(steps.indices, id: \.self) { i in
                            Text("\(i + 1)/\(steps.count)").tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: index) { _ in focus() }
                    TabView(selection: $index) {
                        ForEach(steps.indices, id: \.self) { i in
                            stepCard(steps[i]).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(minHeight: 260)
                    HStack(spacing: 12) {
                        Button(walking ? "Stop walk-through" : "Walk through route") { walking.toggle() }
                        Spacer()
                        Button("Go to step") { walking = false; focus() }
                    }
                    Text("Preview only. No GPS is simulated and navigation is not started.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle(L10n.text("Route preview"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { walking = false; dismiss() } }
            }
            .task(id: walking) {
                guard walking else { return }
                while !Task.isCancelled, walking, !steps.isEmpty {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled, walking else { break }
                    if index + 1 < steps.count { index += 1; focus() } else { walking = false }
                }
            }
            .onAppear { focus() }
        }
        .navigationViewStyle(.stack)
    }

    private func focus() {
        guard steps.indices.contains(index) else { return }
        model.focusManeuver(steps[index])
    }

    @ViewBuilder
    private func stepCard(_ step: Maneuver) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: maneuverSymbol(step.type))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(KiteColor.accent)
                Text(L10n.isCzech ? CzechNavigation.prompt(step) : SpokenText.forScreen(step.instruction))
                    .font(.title3.weight(.semibold))
            }
            LabeledContent("Distance to this step", value: Fmt.distance(step.distanceMeters))
            if let road = step.road { LabeledContent("Road", value: road) }
            if let exit = step.exit {
                LabeledContent("Roundabout exit", value: "\(exit)")
            }
            if let hint = step.laneHint {
                Text("Lanes: \(hint)").font(.subheadline)
            } else if let lanes = LaneGuidanceEngine.guide(for: step, distance: step.distanceMeters,
                                                            speed: 0, offRoute: false,
                                                            leftTraffic: Geo.drivesOnLeft(step.location)) {
                Text("Lanes: \(lanes.title) — \(lanes.detail)").font(.subheadline)
            }
            let events = (model.previewCoverage?.events ?? []).filter {
                abs($0.meters - step.alongMeters) < 120
            }
            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mapped road events here").font(.subheadline.weight(.semibold))
                    ForEach(events, id: \.control.osmID) { event in
                        Text("\(event.control.kind.rawValue) · \(Int(abs(event.meters - step.alongMeters))) m away")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(KiteColor.fill))
    }
}
