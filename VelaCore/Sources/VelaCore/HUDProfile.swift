import Foundation

public enum HUDMode: String, CaseIterable, Identifiable, Sendable {
    case simple, advanced, highway, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
        case .highway: return "Highway"
        case .custom: return "Custom"
        }
    }

    public var detail: String {
        switch self {
        case .simple: return "Only the next turn and the essentials."
        case .advanced: return "Lanes, signs, the next turn and alerts."
        case .highway: return "Long-range exit diagrams, lanes and follow-up turns."
        case .custom: return "Your own mix of lanes, signs and follow-up turns."
        }
    }
}

public struct HUDProfile: Equatable, Sendable {
    public var showLanes: Bool
    public var showThen: Bool
    public var showSpeed: Bool
    public var showRoadName: Bool
    public var showJunction: Bool
    public var showAlerts: Bool
    public var laneLeadMultiplier: Double
    public var alertDensity: Int

    public init(showLanes: Bool, showThen: Bool, showSpeed: Bool, showRoadName: Bool,
                showJunction: Bool, showAlerts: Bool, laneLeadMultiplier: Double,
                alertDensity: Int) {
        self.showLanes = showLanes
        self.showThen = showThen
        self.showSpeed = showSpeed
        self.showRoadName = showRoadName
        self.showJunction = showJunction
        self.showAlerts = showAlerts
        self.laneLeadMultiplier = laneLeadMultiplier
        self.alertDensity = alertDensity
    }
}

public enum HUDCatalog {
    public static func profile(for mode: HUDMode,
                               customLanes: Bool = true,
                               customThen: Bool = true,
                               customJunction: Bool = true) -> HUDProfile {
        switch mode {
        case .simple:
            return HUDProfile(showLanes: false, showThen: false, showSpeed: true,
                              showRoadName: false, showJunction: false,
                              showAlerts: true, laneLeadMultiplier: 0, alertDensity: 1)
        case .advanced:
            return HUDProfile(showLanes: true, showThen: true, showSpeed: true,
                              showRoadName: true, showJunction: true,
                              showAlerts: true, laneLeadMultiplier: 1, alertDensity: 3)
        case .highway:
            return HUDProfile(showLanes: true, showThen: true, showSpeed: true,
                              showRoadName: true, showJunction: true,
                              showAlerts: true, laneLeadMultiplier: 1.45, alertDensity: 4)
        case .custom:
            return HUDProfile(showLanes: customLanes, showThen: customThen, showSpeed: true,
                              showRoadName: true, showJunction: customJunction,
                              showAlerts: true, laneLeadMultiplier: customLanes ? 1 : 0,
                              alertDensity: 2)
        }
    }
}
