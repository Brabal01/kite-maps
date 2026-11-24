import SwiftUI
import VelaCore

struct RoadAheadStrip: View {
    let event: WazeAhead
    let style: RoadAheadStyle
    let scale: Double

    var body: some View {
        HStack(spacing: 10) {
            Label("Ahead", systemImage: "location.north.fill")
                .font(.caption.weight(.semibold))
            Capsule()
                .fill(style == .contrast ? Color.primary : Color.accentColor.opacity(0.65))
                .frame(height: style == .minimal ? 3 : style == .contrast ? 8 : 6)
            WazeBadge(kind: event.alert.kind, size: CGFloat(22 * scale))
            Text(Fmt.distance(event.meters))
                .monospacedDigit().font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .glass(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.alert.title), \(Fmt.distance(event.meters)) ahead")
    }
}
