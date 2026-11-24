import ActivityKit
import SwiftUI
import WidgetKit

struct TransitLiveActivity: Widget {
    private let accent = Color(red: 0.08, green: 0.72, blue: 0.65)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransitActivityAttributes.self) { context in
            let state = context.state
            HStack(spacing: 14) {
                Image(systemName: state.symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.phase).font(.headline).lineLimit(2)
                    Text(state.detail.isEmpty ? context.attributes.destination : state.detail)
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    if !state.line.isEmpty { Text(state.line).font(.headline) }
                    if let time = state.time { Text(time, style: .time).font(.subheadline) }
                }.monospacedDigit()
            }
            .padding(16)
            .foregroundStyle(.white)
            .activityBackgroundTint(Color(red: 0.06, green: 0.09, blue: 0.16))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol).font(.title2.bold()).foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let time = state.time { Text(time, style: .time).font(.headline).monospacedDigit() }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.phase).font(.headline).lineLimit(1)
                        Text(state.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: state.symbol).foregroundStyle(accent)
            } compactTrailing: {
                if state.line.isEmpty, let time = state.time {
                    Text(time, style: .time).font(.caption2).monospacedDigit()
                } else {
                    Text(state.line).font(.caption.bold()).lineLimit(1)
                }
            } minimal: {
                Image(systemName: state.symbol).foregroundStyle(accent)
            }
        }
    }
}
