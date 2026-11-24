import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct TransitActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let symbol: String
        let phase: String
        let detail: String
        let line: String
        let time: Date?
    }

    let destination: String
}
