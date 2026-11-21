import Foundation

/** What a spoken line is for; the voice level decides whether it is said. */
public enum SpeechKind: Equatable, Sendable {
    /** A turn, a continue-straight reminder, a reroute or the arrival. */
    case maneuver
    /** A warning: cameras, police, hazards, speeding. */
    case alert
    /** Everything else (limit changes, offers, status). */
    case info
}

/** How much the navigation voice says. The speaker button cycles through these. */
public enum VoiceLevel: String, CaseIterable, Equatable, Sendable {
    case all, maneuvers, alerts, off

    public func allows(_ kind: SpeechKind) -> Bool {
        switch self {
        case .all: return true
        case .maneuvers: return kind == .maneuver
        case .alerts: return kind == .alert
        case .off: return false
        }
    }

    public var next: VoiceLevel {
        let all = VoiceLevel.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /** Rebuilds the level from the three stored switches (older builds stored only the first two). */
    public init(voice: Bool, alertsOnly: Bool, maneuversOnly: Bool) {
        if !voice { self = .off }
        else if alertsOnly { self = .alerts }
        else if maneuversOnly { self = .maneuvers }
        else { self = .all }
    }

    public var storedSwitches: (voice: Bool, alertsOnly: Bool, maneuversOnly: Bool) {
        (self != .off, self == .alerts, self == .maneuvers)
    }
}
