import SwiftUI
import UIKit
import VelaCore

struct UpcomingRoadControl: Equatable, Identifiable {
    let control: RouteControl
    let meters: Double
    var id: RouteControl { control }
}

struct RoadControlTimeline: View {
    let controls: [UpcomingRoadControl]
    var emptyMessage = "Checking the route…"
    var compactStatus = false
    @State private var expanded = false

    var body: some View {
        if controls.isEmpty {
            if compactStatus {
                Image(systemName: emptyMessage == "Road data temporarily unavailable" ? "exclamationmark.circle" : "road.lanes")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
                    .glass(Circle())
                    .accessibilityLabel(L10n.text(emptyMessage))
            } else {
                Label(L10n.text(emptyMessage), systemImage: "road.lanes")
                    .font(.caption.weight(.medium))
                    .padding(10)
                    .glass(RoundedRectangle(cornerRadius: 14))
            }
        } else {
            Button {
                if controls.count > 3 { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
            } label: {
                VStack(spacing: 0) {
                    ForEach(Array(controls.prefix(expanded ? 6 : 3).enumerated()), id: \.element.id) { index, event in
                        if index > 0 {
                            Capsule().fill(.secondary.opacity(0.32)).frame(width: 2, height: 10)
                        }
                        let kind = event.control.kind
                        VStack(spacing: 2) {
                            if kind == .light {
                                TrafficLightGlyph().frame(width: 20, height: 24)
                            } else {
                                Image(systemName: kind.icon).font(.system(size: 19, weight: .semibold))
                                    .frame(width: 29, height: 25)
                            }
                            Text(Fmt.distance(event.meters)).lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(minWidth: 44, minHeight: 38)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("\(L10n.text(kind.title)), \(Fmt.distance(event.meters))")
                    }
                    if controls.count > 3 {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }
                .font(.caption2.weight(.semibold).monospacedDigit())
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .glass(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

}

struct RoadEventsList: View {
    let controls: [UpcomingRoadControl]
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Road events ahead").font(.headline)
            if controls.isEmpty {
                Text(L10n.text(emptyMessage)).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(controls) { event in
                    HStack {
                        let kind = event.control.kind
                        if kind == .light {
                            TrafficLightGlyph().frame(width: 20, height: 24).frame(width: 28)
                        } else {
                            Image(systemName: kind.icon).frame(width: 28)
                        }
                        Text(L10n.text(kind.title))
                        Spacer(minLength: 4)
                        Text(Fmt.distance(event.meters)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/** A small traffic light: three lenses in a dark housing. SF Symbols has no traffic-light symbol. */
private struct TrafficLightGlyph: View {
    var body: some View {
        VStack(spacing: 2) {
            Circle().fill(Color(hex: 0xE11D48)).frame(width: 5, height: 5)
            Circle().fill(Color(hex: 0xF59E0B)).frame(width: 5, height: 5)
            Circle().fill(Color(hex: 0x16A34A)).frame(width: 5, height: 5)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(hex: 0x111827)))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

private extension RouteControl.Kind {
    /// An SF Symbol that actually exists in this iOS version. A missing name
    /// draws nothing, which looked like an empty road-event row.
    var icon: String {
        UIImage(systemName: symbol) == nil ? "circle.fill" : symbol
    }

    var title: String {
        switch self {
        case .light: return "Traffic lights ahead"
        case .stop: return "Stop sign"
        case .railway: return "Railway crossing"
        case .tram: return "Tram crossing"
        case .crossing: return "Pedestrian crossing"
        case .oneWay: return "One-way street (vehicles)"
        case .yield: return "Give way"
        }
    }

    var symbol: String {
        switch self {
        case .light: return "trafficlight"
        case .stop: return "octagon.fill"
        case .railway: return "train.side.front.car"
        case .tram: return "tram.fill"
        case .crossing: return "figure.walk"
        case .oneWay: return "arrow.right"
        case .yield: return "triangle"
        }
    }
}
