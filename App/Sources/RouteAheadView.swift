import SwiftUI
import VelaCore

enum AheadStyle: String, CaseIterable, Identifiable {
    case line, card, symbols
    var id: String { rawValue }
    var title: String {
        switch self {
        case .line: return "Classic"
        case .card: return "Event cards"
        case .symbols: return "Bare line"
        }
    }
}

enum AheadPosition: String, CaseIterable, Identifiable {
    case bottom, top, left, right
    var id: String { rawValue }
}

struct RouteAheadView: View {
    @ObservedObject var nav: Navigator
    @ObservedObject var settings: AppSettings
    let events: [RouteRoadEvent]
    let vertical: Bool

    @Environment(\.colorScheme) private var scheme

    private struct Marker: Identifiable {
        let id: String
        let image: String
        let title: String
        let meters: Double
        var accent: Color = .primary
        var scale: Double = 1
    }

    private var markers: [Marker] {
        let traveled = nav.progress?.alongMeters ?? 0
        let walking = nav.route.mode == .walk
        let horizon = walking ? Double(settings.walkingAheadRange) : 4_000.0
        let categories = walking ? settings.walkingRoadEvents : settings.roadEvents
        var all = events.filter { categories.contains($0.kind) }.map {
            Marker(id: "osm:\($0.id)", image: $0.kind.icon, title: $0.kind.title, meters: $0.along - traveled)
        }
        if nav.route.mode == .drive {
            all += nav.route.trafficSpans.filter { $0.level >= 2 && $0.startMeters + $0.lengthMeters > traveled }.map {
                Marker(id: "traffic:\($0.startMeters)", image: "car.2.fill", title: "Slow traffic",
                       meters: max(0, $0.startMeters - traveled), accent: .red)
            }
        }
        if nav.route.mode == .drive || (walking && settings.walkingAheadCameras) {
            all += nav.roadStripCameras.map {
                Marker(id: "camera:\($0.camera.id)", image: "camera.fill", title: "Speed camera",
                       meters: $0.along - traveled, accent: .orange,
                       scale: WazeCameras.isWaze($0.camera) ? settings.wazeStripScale : 1)
            }
        }
        if nav.route.mode == .drive || (walking && settings.walkingAheadWaze) {
            all += nav.roadStripReports.filter { settings.shows($0.alert) }.map {
                let report = $0.alert
                let icon: String
                switch report.kind {
                case .police: icon = "shield.lefthalf.filled"
                case .accident: icon = "car.side.fill"
                case .roadworks: icon = "hammer.fill"
                case .closure: icon = "xmark.circle.fill"
                case .jam: icon = "car.2.fill"
                case .weather: icon = "cloud.rain.fill"
                case .hazard: icon = "exclamationmark.triangle.fill"
                }
                return Marker(id: report.id, image: icon, title: report.kind.rawValue.capitalized,
                              meters: $0.along - traveled, accent: .orange, scale: settings.wazeStripScale)
            }
        }
        return Array(all.filter { $0.meters >= 0 && $0.meters <= horizon }
            .sorted { $0.meters < $1.meters }.prefix(vertical ? 3 : 5))
    }

    var body: some View {
        let upcoming = markers
        if !upcoming.isEmpty {
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 5)) : AnyLayout(HStackLayout(spacing: 7))
            let congested = nav.route.trafficSpans.contains {
                let position = nav.progress?.alongMeters ?? 0
                return $0.startMeters < position + 1_000 && $0.startMeters + $0.lengthMeters > position && $0.level >= 2
            }
            layout {
                ForEach(upcoming) { marker in
                    VStack(spacing: 3) {
                        if marker.image == RouteRoadEvent.Kind.trafficLight.icon {
                            let size = 21 * settings.alertScale
                            Image(uiImage: MapIcons.trafficLight()).resizable().frame(width: size, height: size)
                        } else {
                            Image(systemName: marker.image).font(.system(size: 17 * settings.alertScale * marker.scale, weight: .bold))
                                .foregroundStyle(marker.accent)
                        }
                        Text(Fmt.distance(marker.meters)).font(.caption2.weight(.semibold)).monospacedDigit()
                    }
                    .frame(minWidth: 42, minHeight: 40)
                    .padding(settings.aheadStyle == .card ? 4 : 0)
                    .background {
                        if settings.aheadStyle == .card {
                            RoundedRectangle(cornerRadius: 12).fill(Vela.sheet(scheme))
                        }
                    }
                    .accessibilityLabel("\(marker.title), \(Fmt.distance(marker.meters))")
                }
            }
            .padding(6)
            .background(alignment: vertical ? .leading : .bottom) {
                if settings.aheadStyle != .card {
                    if settings.aheadStyle == .line { RoundedRectangle(cornerRadius: 13).fill(Vela.sheet(scheme)) }
                    Capsule().fill(congested ? Color.red : Vela.accent(scheme))
                        .frame(width: vertical ? 3 : nil, height: vertical ? nil : 3)
                }
            }
            .padding(vertical ? .vertical : .horizontal, 4)
        }
    }
}
