import CoreLocation
import MapLibre
import QuartzCore
import UIKit
import VelaCore

/**
 Moves the navigation arrow and the camera every screen frame instead of once per GPS fix.
 Between fixes it keeps the arrow rolling along the route at the current speed, then eases
 onto each new fix, so driving looks smooth like Google Maps or Waze rather than jumping every second.
 */
@MainActor
final class NavGlide: NSObject {
    weak var map: MLNMapView? {
        didSet {
            if map != nil, nav != nil { start() }
        }
    }
    nonisolated static func carY(_ height: CGFloat, north: Bool = false) -> CGFloat {
        let padding = NavigationCamera.padding(height: Double(height))
        return ((north ? 0 : CGFloat(padding.top)) + height - CGFloat(padding.bottom)) / 2
    }

    /** The side panel's width on a big screen, so the car drives in the middle of the map beside it. */
    var leftInset: CGFloat = 0
    private weak var nav: Navigator?
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0

    // The latest fix, as a target.
    private var fixAt: CFTimeInterval = 0
    private var fixAlong: Double = 0
    private var fixCoord = CLLocationCoordinate2D()
    private var fixBearing: Double = 0
    private var fixSpeed: Double = 0
    private var fixCourse: Double = -1
    private var waitingForAccurateFix = false
    private var onRoute = false
    private var line: [LatLng] = []
    private var cum: [Double] = []
    private var targetAcross: Double = 600
    private var targetPitch: Double = 50
    /** 3D, 2D or north up, from the map button. */
    var look: MapLook = .tilted
    /** 0 facing the way you go, 1 north up; eased so a tap turns the map rather than jumping. */
    private var northBlend: Double = 0

    // What is on screen now.
    private var shownAlong: Double?
    private var shownCoord: CLLocationCoordinate2D?
    private var shownBearing: Double = 0
    private var shownAcross: Double = 600
    private var shownPitch: Double = 50
    private var lastPuckDraw: (coordinate: CLLocationCoordinate2D, bearing: Double)?

    /** Called on every GPS fix while navigating. */
    func fix(_ n: Navigator, _ loc: CLLocation, across: Double, pitch: Double = 50, jump: Bool) {
        let starting = nav !== n
        let accurate = NavigationCamera.reliableFix(age: -loc.timestamp.timeIntervalSinceNow, accuracy: loc.horizontalAccuracy)
        let recovered = !starting && shownCoord.map {
            NavigationCamera.reanchor(firstReliableFix: waitingForAccurateFix && accurate,
                                      displacement: distance($0, loc.coordinate), accuracy: loc.horizontalAccuracy)
        } == true
        if starting { waitingForAccurateFix = !accurate }
        else if accurate { waitingForAccurateFix = false }
        let recenter = jump || starting || recovered
        nav = n
        let p = n.progress
        let poly = n.route.polyline
        if poly.count != line.count || poly.first != line.first || poly.last != line.last {
            line = poly
            cum = Geo.cumulative(poly)
            shownAlong = nil
        }
        onRoute = p.map {
            NavigationCamera.snappedToRoute(mode: n.route.mode, offset: $0.offsetMeters, offRoute: $0.offRoute)
        } ?? false
        fixAt = CACurrentMediaTime()
        fixAlong = p?.alongMeters ?? 0
        fixCoord = loc.coordinate
        fixSpeed = loc.speed > 0.5 ? loc.speed : 0
        fixCourse = loc.course >= 0 && loc.speed >= 1.3 && (0...50).contains(loc.horizontalAccuracy) ? loc.course : -1
        fixBearing = fixCourse >= 0 ? fixCourse : (p?.routeBearing ?? shownBearing)
        targetAcross = across
        targetPitch = pitch
        if recenter || shownCoord == nil {
            shownAlong = onRoute ? fixAlong : nil
            shownCoord = onRoute ? coord(at: fixAlong) : fixCoord
            shownBearing = fixBearing
            shownAcross = across
            shownPitch = pitch
            northBlend = look == .north ? 1 : 0
        }
        if map != nil { start() }
        if recenter { step(dt: 0) }
    }

    func restoreOnMap() {
        guard nav != nil else { return }
        lastPuckDraw = nil
        step(dt: 0.0001)
        start()
    }

    func stop() {
        link?.invalidate()
        link = nil
        nav = nil
        shownAlong = nil
        shownCoord = nil
        lastFrame = 0
        lastPuckDraw = nil
        (map?.style?.source(withIdentifier: "vela-puck") as? MLNShapeSource)?.shape = nil
    }

    private func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
        let preferred: Float = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: preferred, preferred: preferred)
        l.add(to: .main, forMode: .common)
        link = l
        lastFrame = 0
    }

    @objc private func frame(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = lastFrame == 0 ? 0 : min(0.1, now - lastFrame)
        lastFrame = now
        guard UIApplication.shared.applicationState == .active else { return }
        step(dt: dt)
    }

    private func step(dt: Double) {
        guard let n = nav else { stop(); return }
        guard let map, map.bounds.width > 0, map.bounds.height > 0 else { return }
        // Keep rolling forward for up to 2 s after a fix, so a late fix doesn't stall the arrow.
        let ahead = fixSpeed * min(2, max(0, CACurrentMediaTime() - fixAt))
        // How quickly the screen catches up with where the car should be: about a third of a second.
        let k = dt == 0 ? 1 : 1 - exp(-dt / 0.35)

        let coordNow: CLLocationCoordinate2D
        var bearingTarget = fixBearing
        if onRoute, !line.isEmpty {
            let want = min(fixAlong + ahead, cum.last ?? fixAlong)
            var along = shownAlong ?? want
            if abs(want - along) > 150 { along = want }
            // Never slide backwards along the road unless the car really went back a long way.
            let next = along + (want - along) * k
            along = next < along && along - want < 15 ? along : next
            shownAlong = along
            coordNow = coord(at: along)
            bearingTarget = roadBearing(at: along)
        } else {
            shownAlong = nil
            var want = fixCoord
            if fixCourse >= 0 { want = moved(fixCoord, by: ahead, bearing: fixCourse) }
            let from = shownCoord ?? want
            if distance(from, want) > 200 {
                coordNow = want
            } else {
                coordNow = CLLocationCoordinate2D(latitude: from.latitude + (want.latitude - from.latitude) * k,
                                                  longitude: from.longitude + (want.longitude - from.longitude) * k)
            }
        }
        shownCoord = coordNow
        let turn = NavigationCamera.shortestTurn(from: shownBearing, to: bearingTarget)
        shownBearing = (shownBearing + turn * (dt == 0 ? 1 : 1 - exp(-dt / 0.4)) + 360).truncatingRemainder(dividingBy: 360)
        // Zooming in for a turn takes about a second; easing back out afterwards is gentler.
        let zoomTime = targetAcross < shownAcross ? 1.0 : 2.0
        shownAcross += (targetAcross - shownAcross) * (dt == 0 ? 1 : 1 - exp(-dt / zoomTime))
        shownPitch += (targetPitch - shownPitch) * (dt == 0 ? 1 : 1 - exp(-dt / zoomTime))

        let puckChanged = lastPuckDraw.map { draw in
            let turn = abs((draw.bearing - shownBearing + 540).truncatingRemainder(dividingBy: 360) - 180)
            return abs(draw.coordinate.latitude - coordNow.latitude) > 0.000002 ||
                abs(draw.coordinate.longitude - coordNow.longitude) > 0.000003 || turn > 0.3
        } ?? true
        if let src = map.style?.source(withIdentifier: "vela-puck") as? MLNShapeSource, puckChanged || src.shape == nil {
            let f = MLNPointFeature()
            f.coordinate = coordNow
            f.attributes = ["bearing": shownBearing]
            src.shape = f
            lastPuckDraw = (coordNow, shownBearing)
        }
        let northTarget: Double = look == .north ? 1 : 0
        northBlend += (northTarget - northBlend) * (dt == 0 ? 1 : 1 - exp(-dt / 0.3))
        if abs(northTarget - northBlend) < 0.001 { northBlend = northTarget }
        if n.following {
            // North up: the map turns to face north and the car moves up to the middle, as the road
            // ahead can be any way round. Otherwise it faces the way you go with the car low down.
            let toNorth = NavigationCamera.shortestTurn(from: shownBearing, to: 0)
            let heading = (shownBearing + toNorth * northBlend + 360).truncatingRemainder(dividingBy: 360)
            let cam = MLNMapCamera(lookingAtCenter: coordNow, acrossDistance: shownAcross, pitch: shownPitch, heading: heading)
            let padding = NavigationCamera.padding(height: Double(map.bounds.height))
            let pad = UIEdgeInsets(top: CGFloat(padding.top) * (1 - northBlend), left: leftInset,
                                   bottom: CGFloat(padding.bottom), right: 0)
            map.setCamera(cam, withDuration: 0, animationTimingFunction: nil, edgePadding: pad, completionHandler: nil)
        }
    }

    // MARK: Helpers

    private func coord(at along: Double) -> CLLocationCoordinate2D {
        let p = Geo.point(along: line, meters: along, cumulative: cum)
        return CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
    }

    /** Direction of the road a little ahead, so the arrow turns into bends instead of snapping at corners. */
    private func roadBearing(at along: Double) -> Double {
        let a = Geo.point(along: line, meters: max(0, along - 5), cumulative: cum)
        let b = Geo.point(along: line, meters: along + 15, cumulative: cum)
        return a == b ? shownBearing : Geo.bearing(a, b)
    }

    private func moved(_ c: CLLocationCoordinate2D, by meters: Double, bearing: Double) -> CLLocationCoordinate2D {
        let r = bearing * .pi / 180
        let dLat = meters * cos(r) / 111_320
        let dLng = meters * sin(r) / (111_320 * max(0.2, cos(c.latitude * .pi / 180)))
        return CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLng)
    }

    private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
