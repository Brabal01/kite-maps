import SwiftUI
import VelaCore

struct SavedRoadPlan: Codable, Identifiable {
    var id = UUID()
    let name: String
    let places: [Place]
    let mode: Int

    var shareText: String {
        let rows = places.map { "\($0.name) · \($0.location.lat),\($0.location.lng)" }
        return ([name] + rows).joined(separator: "\n")
    }
}

struct SavedPlaceList: Codable, Identifiable {
    var id = UUID()
    var name: String
    var places: Set<String> = []
}

struct RoadPlanEditor: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var ordered: [Place]
    @State private var name: String
    let mode: TravelMode

    init(model: AppModel, ordered: [Place], mode: TravelMode) {
        self.model = model
        self.mode = mode
        _ordered = State(initialValue: ordered)
        _name = State(initialValue: "\(ordered.first?.name ?? "Start") → \(ordered.last?.name ?? "Destination")")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Drag to reorder") {
                    ForEach(Array(ordered.enumerated()), id: \.offset) { i, place in
                        Label(place.name, systemImage: i == 0 ? "circle" : i == ordered.count - 1 ? "mappin.circle.fill" : "circle.fill")
                    }.onMove { ordered.move(fromOffsets: $0, toOffset: $1) }
                }
                Section("Save for later") {
                    TextField("Route name", text: $name)
                    Button {
                        settings.savedRoadPlans.insert(plan, at: 0)
                        apply()
                    } label: { Label("Save route", systemImage: "bookmark") }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ShareLink(item: plan.shareText) { Label("Share route", systemImage: "square.and.arrow.up") }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply", action: apply) }
            }
        }
    }

    private var plan: SavedRoadPlan { SavedRoadPlan(name: name, places: ordered, mode: mode.rawValue) }
    private func apply() { model.openRoadPlan(plan, resolveCurrentPosition: true); dismiss() }
}
