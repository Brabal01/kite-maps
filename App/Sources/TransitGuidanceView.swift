import SwiftUI
import VelaCore

struct TransitGuidance {
    let trip: TransitTrip
    var index = 0
    var leg: TransitLeg { trip.legs[index] }
}

struct TransitGuidanceView: View {
    @ObservedObject var model: AppModel
    let guide: TransitGuidance

    var body: some View {
        let leg = guide.leg
        VStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(leg.isWalk ? "Walk" : leg.line.isEmpty ? "Public transport" : leg.line,
                          systemImage: vehicleSymbol(leg.vehicle))
                        .font(.title2.bold())
                    Spacer()
                    Button("End", role: .destructive) { model.endNavigation() }
                }
                if let headsign = leg.headsign { Text(headsign).font(.headline) }
                if !leg.isWalk {
                    stop(leg.fromName, time: leg.depart, symbol: "arrow.up.circle")
                    Label("Vehicle position is estimated from stop times", systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                stop(leg.toName, time: leg.arrive, symbol: "mappin.circle")
                HStack {
                    Text("Leg \(guide.index + 1) of \(guide.trip.legs.count)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.frameTransit() } label: {
                        Label("Overview", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
            .padding(16)
            .glass(RoundedRectangle(cornerRadius: 20))
            Spacer()
            Button { model.advanceTransit() } label: {
                Label(leg.isWalk ? "Reached the next stop" : "I've got off", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private func stop(_ name: String, time: Date?, symbol: String) -> some View {
        HStack {
            Label(name, systemImage: symbol)
            Spacer()
            if let time { Text(time, style: .time).monospacedDigit() }
        }
    }
}
