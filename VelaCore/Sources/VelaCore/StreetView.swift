import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 * Google Street View, keyless: the same panorama lookup Google's own map pages use, a thumbnail
 * for the place page, and the image tiles the app's own viewer stitches into a 360° view.
 */
public enum StreetView {
    public struct Link: Equatable, Sendable {
        public let id: String
        public let location: LatLng
        public let bearing: Double
    }

    fileprivate struct Level: Equatable, Sendable {
        let width: Int
        let height: Int
    }

    public struct Panorama: Equatable, Sendable {
        public var id: String
        public var location: LatLng
        /** Full size in pixels (width is twice height); older panoramas are smaller. */
        public var width = 16384
        public var height = 8192
        /** The compass direction at the middle of the image. */
        public var heading = 0.0
        public fileprivate(set) var tileSize = 512
        fileprivate var levels: [Level] = []
        public fileprivate(set) var links: [Link] = []
        public fileprivate(set) var credit: String?

        public init(id: String, location: LatLng, width: Int = 16384, height: Int = 8192, heading: Double = 0) {
            self.id = id
            self.location = location
            self.width = width
            self.height = height
            self.heading = heading
        }

        /** Image size at [zoom] (0 to 5): each step down halves it. */
        public func size(zoom: Int) -> (width: Int, height: Int) {
            if levels.indices.contains(zoom) {
                let level = levels[zoom]
                return (level.width, level.height)
            }
            let f = 1 << max(0, 5 - max(0, zoom))
            return (width / f, height / f)
        }

        public func step(facing bearing: Double) -> Link? {
            links.map { ($0, abs(NavigationCamera.shortestTurn(from: bearing, to: $0.bearing))) }
                .filter { $0.1 <= 60 }.min { $0.1 < $1.1 }?.0
        }
    }

    /** Google retired the old GeoPhotoService.SingleImageSearch; its pages now ask this RPC. */
    static let searchEndpoint = URL(string: "https://maps.googleapis.com/$rpc/google.internal.maps.mapsjs.v1.MapsJsInternalService/SingleImageSearch")!

    public static func searchRequest(_ p: LatLng, radius: Int) -> URLRequest {
        var r = URLRequest(url: searchEndpoint)
        r.httpMethod = "POST"
        r.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
        let body = "[[\"apiv3\",null,null,null,\"US\",null,null,null,null,null,[[0]]],"
            + "[[null,null,\(p.lat),\(p.lng)],\(radius)],"
            + "[null,[\"en\",\"US\"],null,null,null,null,null,null,[2],null,[[[2,1,2]]]],"
            + "[[1,2,3,4,8,6]]]"
        r.httpBody = body.data(using: .utf8)
        r.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")
        return r
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Referer": "https://www.google.com/",
        ]
        return URLSession(configuration: c)
    }()

    /** The nearest Google panorama within [radius] meters, or nil. Official Street View only: not
     *  the photo spheres people upload (type 10), which are often indoors or years old. */
    public static func find(near p: LatLng, radius: Int = 60) async -> Panorama? {
        await load(searchRequest(p, radius: radius))
    }

    public static func panorama(id: String) async -> Panorama? {
        guard validID(id) else { return nil }
        let meta = "!1m4!1smaps_sv.tactile!11m2!2m1!1b1!2m2!1sen!2sus!3m3!1m2!1e2!2s\(id)"
            + "!4m57!1e1!1e2!1e3!1e4!1e5!1e6!1e8!1e12!2m1!1e1!4m1!1i48!5m1!1e1!5m1!1e2!6m1!1e1!6m1!1e2"
            + "!9m36!1m3!1e2!2b1!3e2!1m3!1e2!2b0!3e3!1m3!1e3!2b1!3e2!1m3!1e3!2b0!3e3!1m3!1e8!2b0!3e3"
            + "!1m3!1e1!2b0!3e3!1m3!1e4!2b0!3e3!1m3!1e10!2b1!3e2!1m3!1e10!2b0!3e3"
        guard let url = URL(string: "https://www.google.com/maps/photometa/v1?authuser=0&hl=en&gl=us&pb=" + meta),
              let result = await load(URLRequest(url: url)), result.id == id else { return nil }
        return result
    }

    private static func load(_ request: URLRequest) async -> Panorama? {
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func validID(_ id: String) -> Bool {
        id.range(of: #"\A[A-Za-z0-9_-]{20,25}\z"#, options: .regularExpression) != nil
    }

    static func parse(_ text: String) -> Panorama? {
        let root = GoogleJSON.parse(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let nodes = [at(root, 1), at(root, 1, 0)]
        guard let node = nodes.first(where: { (at($0, 1, 1) as? String).map(validID) == true }),
              let id = at(node, 1, 1) as? String else { return parseLegacy(text) }
        let position = at(node, 5, 0, 1) ?? at(node, 3)
        guard let here = coordinate(position) else { return nil }
        let rawLevels = arr(at(node, 2, 3, 0)) ?? []
        let levels = rawLevels.compactMap { entry -> Level? in
            guard let width = int(at(entry, 0, 1)), (1...65536).contains(width),
                  let height = int(at(entry, 0, 0)), (1...32768).contains(height) else { return nil }
            return Level(width: width, height: height)
        }
        var pano = Panorama(id: id, location: here)
        if levels.count == rawLevels.count { pano.levels = levels }
        pano.width = pano.levels.last?.width ?? boundedDimension(at(node, 2, 2, 1), 1024...65536) ?? pano.width
        pano.height = pano.levels.last?.height ?? boundedDimension(at(node, 2, 2, 0), 512...32768) ?? pano.height
        pano.heading = dbl(at(position, 2, 0)).flatMap { $0.isFinite ? $0 : nil } ?? 0
        pano.tileSize = boundedDimension(at(node, 2, 3, 1, 0), 128...1024) ?? pano.tileSize
        pano.credit = at(node, 4, 0, 0, 0, 0) as? String
        let graph = arr(at(node, 5, 0, 3, 0)) ?? []
        let historical = Set((arr(at(node, 5, 0, 8)) ?? []).compactMap { entry -> String? in
            guard let index = int(at(entry, 0)), graph.indices.contains(index) else { return nil }
            return at(graph[index], 0, 1) as? String
        })
        let nearby = graph.compactMap { entry -> (Link, Double)? in
            guard let neighbor = at(entry, 0, 1) as? String, validID(neighbor), neighbor != id,
                  !historical.contains(neighbor), let point = coordinate(at(entry, 2)) else { return nil }
            let distance = here.distance(to: point)
            guard (3...38).contains(distance) else { return nil }
            return (Link(id: neighbor, location: point, bearing: Geo.bearing(here, point)), distance)
        }.sorted { $0.1 < $1.1 }
        for (link, _) in nearby where !pano.links.contains(where: { abs(NavigationCamera.shortestTurn(from: $0.bearing, to: link.bearing)) < 33 }) {
            pano.links.append(link)
        }
        return pano
    }

    private static func coordinate(_ position: Any?) -> LatLng? {
        guard let lat = dbl(at(position, 0, 2)), (-90...90).contains(lat),
              let lng = dbl(at(position, 0, 3)), (-180...180).contains(lng) else { return nil }
        return LatLng(lat, lng)
    }

    private static func boundedDimension(_ value: Any?, _ bounds: ClosedRange<Int>) -> Int? {
        guard let value = int(value), bounds.contains(value) else { return nil }
        return value
    }

    private static func parseLegacy(_ text: String) -> Panorama? {
        guard let idMatch = text.range(of: #"\[2,\s*"[A-Za-z0-9_-]{22}"\]"#, options: .regularExpression) else { return nil }
        let id = String(text[idMatch].filter { $0 != " " }.dropFirst(4).dropLast(2))
        guard let r = text.range(of: #"\[\[null,null,-?\d+\.\d+,\s*-?\d+\.\d+\]"#, options: .regularExpression) else { return nil }
        let nums = text[r].dropFirst(12).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.count == 2, (-90...90).contains(nums[0]), (-180...180).contains(nums[1]) else { return nil }
        var pano = Panorama(id: id, location: LatLng(nums[0], nums[1]))
        // Its size follows the id: [2,2,[height,width],...
        let after = text[idMatch.upperBound...]
        if let m = after.range(of: #"^,\[\d+,\d+,\[\d+,\d+\]"#, options: .regularExpression) {
            let n = after[m].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if n.count == 4, (512...32768).contains(n[2]), (1024...65536).contains(n[3]) {
                pano.height = n[2]
                pano.width = n[3]
            }
        }
        // Its heading follows the position: [[null,null,lat,lng],[altitude],[heading,tilt,roll]]
        let rest = text[r.upperBound...]
        if let m = rest.range(of: #"^,\[[^\]]*\],\[-?\d+(\.\d+)?"#, options: .regularExpression),
           let h = Double(rest[m].split(separator: "[").last ?? "") {
            pano.heading = h
        }
        return pano
    }

    /** One 512-pixel square of the panorama at [zoom]. */
    public static func tileURL(_ pano: Panorama, x: Int, y: Int, zoom: Int) -> URL {
        URL(string: "https://streetviewpixels-pa.googleapis.com/v1/tile?cb_client=maps_sv.tactile&panoid=\(pano.id)"
            + "&x=\(x)&y=\(y)&zoom=\(zoom)&nbt=1&fover=2")!
    }

    /** A still from the panorama, looking toward [heading]. */
    public static func thumbnailURL(_ pano: Panorama, heading: Double, width: Int = 640, height: Int = 360) -> URL {
        URL(string: "https://streetviewpixels-pa.googleapis.com/v1/thumbnail?panoid=\(pano.id)&cb_client=maps_sv.tactile.gps"
            + "&w=\(width)&h=\(height)&yaw=\(Int(heading.rounded()))&pitch=0&thumbfov=100")!
    }

}
