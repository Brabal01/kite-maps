import SwiftUI
import VelaCore

struct IndoorOverlay: View {
    @ObservedObject var model: AppModel
    let plan: IndoorPlan
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(plan.name ?? model.selected?.name ?? "Floor plan", systemImage: "building.2")
                    .font(.headline)
                Spacer()
                Button("Done") { model.closeIndoor() }.buttonStyle(.bordered)
            }
            .padding(12).background(Vela.ground(scheme), in: RoundedRectangle(cornerRadius: 16))
            Spacer()
            HStack {
                Spacer()
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(plan.floors, id: \.self) { floor in
                            Button {
                                model.indoorFloor = floor
                                model.indoorFeature = nil
                            } label: {
                                Text(floor).bold().frame(width: 42, height: 40)
                                    .background(model.indoorFloor == floor ? Vela.routeBlue : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(model.indoorFloor == floor ? Color.white : Color.primary)
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Floor \(floor)")
                        }
                    }.padding(5)
                }
                .frame(width: 54, height: CGFloat(min(plan.floors.count, 6)) * 46 + 10)
                .background(Vela.ground(scheme), in: RoundedRectangle(cornerRadius: 16))
            }
            Spacer()
            if let feature = model.indoorFeature, let name = feature.name {
                HStack {
                    Image(systemName: feature.kind == "shop" ? "storefront" : "mappin.circle.fill")
                    VStack(alignment: .leading) {
                        Text(name).font(.headline)
                        Text("Floor \(model.indoorFloor) · \(feature.kind.capitalized)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Details") {
                        var place = Place(id: "osm-indoor:\(feature.id)", name: name, location: feature.center, source: "osm")
                        place.category = feature.kind
                        model.closeIndoor()
                        model.select(place)
                    }.buttonStyle(.bordered)
                }.padding(12).background(Vela.ground(scheme), in: RoundedRectangle(cornerRadius: 16))
            }
        }.padding(12)
    }
}
