import MapLibre
import UIKit

/** Camera commands shared by all map renderers. Neither renderer owns the active trip. */
@MainActor
protocol KiteMapSurface: AnyObject {
    var mapView: UIView { get }
    var bounds: CGRect { get }
    var centerCoordinate: CLLocationCoordinate2D { get }
    var visibleCoordinateBounds: MLNCoordinateBounds { get }
    var zoomLevel: Double { get }
    var direction: CLLocationDirection { get }
    var camera: MLNMapCamera { get set }
    var showsUserLocation: Bool { get set }
    var locationCoordinate: CLLocationCoordinate2D? { get }
    func setCenter(_ coordinate: CLLocationCoordinate2D, zoomLevel: Double, animated: Bool)
    func setDirection(_ heading: CLLocationDirection, animated: Bool)
    func cameraThatFitsCoordinateBounds(_ bounds: MLNCoordinateBounds, edgePadding: UIEdgeInsets) -> MLNMapCamera
    func setCamera(_ camera: MLNMapCamera, withDuration duration: TimeInterval,
                   animationTimingFunction: CAMediaTimingFunction?, edgePadding: UIEdgeInsets,
                   completionHandler: (() -> Void)?)
    func drawPuck(at coordinate: CLLocationCoordinate2D?, bearing: Double)
}

extension KiteMapSurface {
    func setCamera(_ camera: MLNMapCamera, withDuration duration: TimeInterval,
                   animationTimingFunction: CAMediaTimingFunction?) {
        setCamera(camera, withDuration: duration, animationTimingFunction: animationTimingFunction,
                  edgePadding: .zero, completionHandler: nil)
    }
}

extension MLNMapView: KiteMapSurface {
    var mapView: UIView { self }
    var locationCoordinate: CLLocationCoordinate2D? { userLocation?.location?.coordinate }

    func drawPuck(at coordinate: CLLocationCoordinate2D?, bearing: Double) {
        guard let source = style?.source(withIdentifier: "vela-puck") as? MLNShapeSource else { return }
        guard let coordinate else { source.shape = nil; return }
        let point = MLNPointFeature()
        point.coordinate = coordinate
        point.attributes = ["bearing": bearing]
        source.shape = point
    }
}
