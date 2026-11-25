import Foundation

public struct PlaceReview: Hashable, Sendable {
    public let author: String
    public let rating: Int?
    public let time: String?
    public let text: String?
    public let photos: [String]
}

/// Response schemas shared with the Android fork's Google place media client.
enum GooglePlaceMedia {
    static func featureIDIsValid(_ id: String) -> Bool {
        id.range(of: #"\A0x[0-9a-fA-F]{1,16}:0x[0-9a-fA-F]{1,16}\z"#, options: .regularExpression) != nil
    }

    static func legacyParameter(_ id: String) -> String? {
        guard featureIDIsValid(id), let (high, low) = GoogleReviews.ids(id) else { return nil }
        return "!1m2!1y\(high)!2y\(low)!2m2!2i0!3i20!3e1!5m2!1skite!7e81"
    }

    static func reviewsRequest(_ id: String) -> String? {
        guard featureIDIsValid(id) else { return nil }
        let payload = """
        [[["\(id)"],null,null,null,null,[null,null,null,[[1],[3]]]],[10,""],null,null,[null,null,null,null,null,null,81],null,null,[null,1,1,null,1,null,1,null,null,null,null,[1,1,null,[[1]]]],null,null,[3,1,null,null,null,[2]],null,[1]]
        """
        return batchRequest("qv9Egd", payload: payload)
    }

    static func galleryRequest(_ id: String) -> String? {
        guard featureIDIsValid(id) else { return nil }
        let payload = """
        [2,null,["\(id)",null,null,null,null,null,null,null,0],null,[null,[1200,1000],[null,30,null,null,1],null,null,null,[[[1,0,3],[2,1,2],[2,0,3],[8,0,3],[10,0,3],[10,1,2],[10,0,4],[9,1,2]],1],null,0],null,null,null,null,null,null,null,null,null,null,[null,1,null,1]]
        """
        return batchRequest("hspqX", payload: payload)
    }

    private static func batchRequest(_ rpc: String, payload: String) -> String {
        GoogleJSON.text([[[rpc, payload, NSNull(), "generic"]]])
    }

    private static func batchPayload(_ body: String, rpc: String) -> Any? {
        for line in body.split(whereSeparator: \.isNewline) where line.trimmingCharacters(in: .whitespaces).hasPrefix("[[") {
            for row in arr(GoogleJSON.parse(String(line))) ?? [] where str(at(row, 0)) == "wrb.fr" && str(at(row, 1)) == rpc {
                if let value = at(row, 2) as? String, let payload = GoogleJSON.parse(value) { return payload }
            }
        }
        return nil
    }

    static func reviewFeed(_ body: String) -> [PlaceReview] {
        (arr(at(batchPayload(body, rpc: "qv9Egd"), 2)) ?? []).compactMap { entry in
            let row = at(entry, 0)
            return review(author: at(row, 1, 4, 5, 0), rating: at(row, 2, 0, 0),
                          time: at(row, 1, 6), text: at(row, 2, 15, 0, 0), photos: at(row, 2, 2))
        }
    }

    static func legacyReviews(_ body: String) -> [PlaceReview] {
        (arr(at(GoogleJSON.parse(body), 2)) ?? []).compactMap { row in
            review(author: at(row, 0, 1), rating: at(row, 4), time: at(row, 1), text: at(row, 3), photos: row)
        }
    }

    static func gallery(_ body: String) -> [String] {
        imageURLs(at(batchPayload(body, rpc: "hspqX"), 0), limit: 40)
    }

    static func mergedReviews(_ groups: [PlaceReview]...) -> [PlaceReview] {
        struct Key: Hashable { let author: String; let rating: Int?; let text: String? }
        var rows: [PlaceReview] = []
        var indices: [Key: Int] = [:]
        for row in groups.joined() {
            let key = Key(author: row.author, rating: row.rating, text: row.text)
            if let index = indices[key] {
                let old = rows[index]
                var seen = Set<String>()
                let photos = (old.photos + row.photos).filter { seen.insert($0).inserted }
                rows[index] = PlaceReview(author: old.author, rating: old.rating, time: old.time ?? row.time,
                                         text: old.text, photos: Array(photos.prefix(8)))
            } else {
                indices[key] = rows.count
                rows.append(row)
            }
        }
        return rows
    }

    private static func review(author: Any?, rating: Any?, time: Any?, text: Any?, photos: Any?) -> PlaceReview? {
        guard let author = nonempty(author) else { return nil }
        let stars = dbl(rating).flatMap { (1...5).contains($0) && $0.rounded() == $0 ? Int($0) : nil }
        return PlaceReview(author: author, rating: stars, time: nonempty(time), text: nonempty(text),
                           photos: imageURLs(photos, limit: 8))
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func imageURLs(_ root: Any?, limit: Int) -> [String] {
        guard let root, limit > 0 else { return [] }
        var work: [Any] = [root]
        var seen = Set<String>()
        var result: [String] = []
        while let node = work.popLast(), result.count < limit {
            if let children = arr(node) { work.append(contentsOf: children.reversed()); continue }
            guard let value = node as? String, let url = imageURL(value), seen.insert(url).inserted else { continue }
            result.append(url)
        }
        return result
    }

    private static func imageURL(_ value: String) -> String? {
        let absolute = value.hasPrefix("//") ? "https:" + value : value
        guard var url = URLComponents(string: absolute), url.scheme == "https",
              url.user == nil, url.password == nil, url.port == nil, let host = url.host?.lowercased(),
              host.hasSuffix(".googleusercontent.com") || host.hasSuffix(".ggpht.com"),
              ["/p/", "/gps-cs", "/grass-cs/", "/geougc", "/places/"].contains(where: url.path.hasPrefix) else { return nil }
        url.query = nil
        url.fragment = nil
        url.percentEncodedPath = url.percentEncodedPath.replacingOccurrences(of: #"=(?:[swh]\d[\w-]*|k-no)$"#,
                                                                             with: "", options: .regularExpression) + "=w800-h600"
        return url.string
    }
}
