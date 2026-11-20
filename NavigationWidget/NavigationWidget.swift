import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NavigationWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivity.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.symbol).font(.title).foregroundStyle(.mint)
                VStack(alignment: .leading) {
                    Text(context.state.detail).font(.title2.bold()).lineLimit(1)
                    Text(context.state.instruction).font(.headline).lineLimit(2)
                    if let summary = context.state.summary {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: context.state.symbol) }
                DynamicIslandExpandedRegion(.center) { Text(context.state.instruction) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.detail) }
            } compactLeading: { Image(systemName: context.state.symbol) } compactTrailing: {
                Text(context.state.detail).lineLimit(1)
            } minimal: { Image(systemName: context.state.symbol) }
        }
    }
}
