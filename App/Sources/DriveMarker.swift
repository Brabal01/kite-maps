import Foundation

enum DriveMarker: String, CaseIterable, Identifiable {
    case arrow, alfa, van

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .alfa: return "Alfa Romeo 147"
        case .van: return "Van"
        }
    }

    func imageName(tilted: Bool) -> String? {
        switch self {
        case .arrow: return nil
        case .alfa: return tilted ? "DriveAlfaTilt" : "DriveAlfa"
        case .van: return tilted ? "DriveVanTilt" : "DriveVan"
        }
    }
}

enum RoutePointRole {
    case origin, destination, stop
}
