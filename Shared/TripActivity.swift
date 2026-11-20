import ActivityKit

@available(iOS 16.2, *)
struct TripActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let instruction: String
        let detail: String
        let symbol: String
        var summary: String? = nil
    }
}
