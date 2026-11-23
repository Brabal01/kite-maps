import Foundation

public enum MapLineGeometry {
    /// Split at invalid coordinates and unsupported gaps. Never connect points on either side of a gap.
    public static func segments(_ points: [LatLng], maximumEdgeMeters: Double? = nil) -> [[LatLng]] {
        var result: [[LatLng]] = []
        var current: [LatLng] = []
        func finish() {
            if current.count >= 2 { result.append(current) }
            current = []
        }
        for point in points {
            guard isValid(point) else {
                finish()
                continue
            }
            guard let previous = current.last else {
                current = [point]
                continue
            }
            guard point != previous else { continue }
            if let maximumEdgeMeters, previous.distance(to: point) > maximumEdgeMeters {
                finish()
            } else if abs(point.lng - previous.lng) > 180 {
                let seam = previous.lng > 0 ? 180.0 : -180.0
                let unwrapped = point.lng + 2 * seam
                let delta = unwrapped - previous.lng
                let fraction = delta == 0 ? 0 : (seam - previous.lng) / delta
                let latitude = previous.lat + fraction * (point.lat - previous.lat)
                let edge = LatLng(latitude, seam)
                if edge != previous { current.append(edge) }
                finish()
                let otherEdge = LatLng(latitude, -seam)
                if otherEdge != point { current.append(otherEdge) }
            }
            current.append(point)
        }
        finish()
        return result
    }

    public static func isValid(_ point: LatLng) -> Bool {
        (-90...90).contains(point.lat) && (-180...180).contains(point.lng)
    }
}

public enum MapLayerPolicy {
    public static func showsTransitNetwork(
        requested: Bool, activeTransit: Bool, planningTransit: Bool, roadGuidance: Bool
    ) -> Bool {
        !roadGuidance && (requested || activeTransit || planningTransit)
    }
}
