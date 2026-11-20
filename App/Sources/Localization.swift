import Foundation
import VelaCore

enum KiteLanguage: String, CaseIterable, Identifiable {
    case system, czech, english
    var id: String { rawValue }
    var locale: Locale {
        switch self {
        case .system: return Locale.preferredLanguages.first?.hasPrefix("cs") == true ? Locale(identifier: "cs_CZ") : .current
        case .czech: return Locale(identifier: "cs_CZ")
        case .english: return Locale(identifier: "en_US")
        }
    }
}

enum L10n {
    private static let czech = Bundle.main.path(forResource: "cs", ofType: "lproj").flatMap(Bundle.init(path:))
    static var isCzech: Bool {
        switch AppSettings.shared.language {
        case .czech: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("cs") == true
        }
    }

    static func text(_ key: String) -> String {
        guard isCzech, let czech else { return key }
        return czech.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ values: String...) -> String {
        String(format: text(key), arguments: values.map { $0 as CVarArg })
    }
}

enum CzechNavigation {
    static func prompt(_ maneuver: Maneuver, distance: Double? = nil) -> String {
        let command: String
        switch maneuver.type {
        case .depart: command = "Vyrazte"
        case .arrive: return distance.map { "Za \(spokenDistance($0)) dorazíte do cíle." } ?? "Jste v cíli."
        case .straight: command = "Pokračujte rovně"
        case .turnLeft: command = "Odbočte vlevo"
        case .turnRight: command = "Odbočte vpravo"
        case .slightLeft: command = "Odbočte mírně vlevo"
        case .slightRight: command = "Odbočte mírně vpravo"
        case .sharpLeft: command = "Odbočte ostře vlevo"
        case .sharpRight: command = "Odbočte ostře vpravo"
        case .uturn: command = "Otočte se do protisměru"
        case .merge: command = "Zařaďte se do provozu"
        case .rampLeft, .rampRight:
            let side = maneuver.type == .rampLeft ? "vlevo" : "vpravo"
            command = maneuver.exitSign?.number.map { "Použijte sjezd číslo \($0) \(side)" } ?? "Použijte sjezd \(side)"
        case .forkLeft, .keepLeft: command = "Držte se vlevo"
        case .forkRight, .keepRight: command = "Držte se vpravo"
        case .roundabout:
            command = maneuver.leavesRoundabout ? "Opusťte kruhový objezd" :
                maneuver.exit.map { "Na kruhovém objezdu použijte výjezd číslo \($0)" } ?? "Opusťte kruhový objezd"
        case .unknown: command = "Pokračujte po trase"
        }
        let lead = distance.map { "Za \(spokenDistance($0)) " } ?? ""
        let action = distance == nil ? command : command.prefix(1).lowercased() + command.dropFirst()
        let road = maneuver.road.flatMap { $0.isEmpty ? nil : $0 }
        if let sign = maneuver.exitSign, !sign.destinations.isEmpty {
            return lead + action + " – směr " + sign.destinations.prefix(2).joined(separator: ", ")
        }
        return lead + action + (road.map { " na \($0)" } ?? "")
    }

    static func spokenDistance(_ meters: Double) -> String {
        if meters < 950 {
            let rounded = max(10, Int((meters / 10).rounded()) * 10)
            return "\(rounded) metrů"
        }
        let rounded = max(1, Int((meters / 1000).rounded()))
        if rounded == 1 { return "jeden kilometr" }
        return rounded < 5 ? "\(rounded) kilometry" : "\(rounded) kilometrů"
    }
}
