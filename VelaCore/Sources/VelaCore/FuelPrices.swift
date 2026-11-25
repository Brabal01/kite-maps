import CZlib
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FuelPrices {
    public struct Quote: Equatable, Sendable {
        public let labels: [String]
        public let updated: Date
    }

    struct Station: Sendable {
        let position: LatLng
        let quote: Quote
    }

    static func googleLabel(_ value: String?) -> String? {
        guard let label = value?.replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines),
              (3...35).contains(label.count),
              label.range(of: #"(?:[$€£]\s*\d|\d[\d.,]*\s*(?:Kč|CZK|€|¢|p\s*/))"#,
                          options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return label
    }

    public static func isStation(_ place: Place) -> Bool {
        if place.fuelStation == true { return true }
        let category = place.category?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return ["gas station", "petrol station", "fuel station", "fuel", "cerpaci stanice"].contains(category ?? "")
    }

    static func nearBritain(_ point: LatLng) -> Bool {
        (49.7...61).contains(point.lat) && (-8.3...2).contains(point.lng)
    }

    public static func ukQuotes(for places: [Place]) async -> [String: Quote] {
        let eligible = places.filter { $0.fuelPrice == nil && isStation($0) && nearBritain($0.location) }
        guard !eligible.isEmpty else { return [:] }
        let data = await FuelStationFeed.shared.stations()
        let now = Date()
        return eligible.reduce(into: [:]) { prices, place in
            if let quote = match(place.location, stations: data, now: now) { prices[place.id] = quote }
        }
    }

    static func match(_ point: LatLng, stations: [Station], now: Date) -> Quote? {
        let nearby = stations.compactMap { station -> (Station, Double)? in
            guard abs(point.lat - station.position.lat) <= 0.001,
                  abs(point.lng - station.position.lng) <= 0.002 else { return nil }
            let distance = point.distance(to: station.position)
            return distance <= 75 ? (station, distance) : nil
        }.sorted { $0.1 < $1.1 }
        guard let (best, distance) = nearby.first,
              nearby.count < 2 || nearby[1].1 - distance >= 25,
              (-3_600...604_800).contains(now.timeIntervalSince(best.quote.updated)) else { return nil }
        return best.quote
    }

    static func parseCSV(_ csv: String) -> [Station] {
        let lines = csv.split(whereSeparator: \.isNewline)
        guard let line = lines.first else { return [] }
        let columns = line.split(separator: ",")
        let required = ["lat", "lng", "e10", "updated"]
        guard required.allSatisfy({ columns.contains(Substring($0)) }) else { return [] }
        let types = [("e10", "E10"), ("e5", "E5"), ("b7s", "Diesel"), ("b7p", "Premium diesel")]
        return lines.dropFirst().prefix(20_000).compactMap { line in
            var fields: [String] = [""]
            var quoted = false
            for char in line {
                if char == "\"" { quoted.toggle() }
                else if char == ",", !quoted { fields.append("") }
                else { fields[fields.count - 1].append(char) }
            }
            func field(_ name: String) -> String {
                guard let index = columns.firstIndex(of: Substring(name)), fields.indices.contains(index) else { return "" }
                return fields[index].trimmingCharacters(in: .whitespaces)
            }
            guard !quoted, let lat = Double(field("lat")), let lng = Double(field("lng")),
                  let time = Int64(field("updated")) else { return nil }
            let location = LatLng(lat, lng)
            guard nearBritain(location) else { return nil }
            let labels = types.compactMap { column, label -> String? in
                guard let price = Double(field(column)), (60...450).contains(price) else { return nil }
                let decimal = (price * 10).rounded()
                let value = decimal.truncatingRemainder(dividingBy: 10) == 0
                    ? String(Int(decimal / 10)) : String(decimal / 10)
                return "\(label) \(value) p/L"
            }
            guard !labels.isEmpty else { return nil }
            return Station(position: location, quote: Quote(labels: labels, updated: Date(timeIntervalSince1970: Double(time))))
        }
    }

    static func gunzip(_ bytes: Data) -> Data? {
        guard (18...2_000_000).contains(bytes.count), bytes.starts(with: [0x1f, 0x8b]) else { return nil }
        let size = bytes.suffix(4).enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
        guard (1...4_000_000).contains(size) else { return nil }
        var output = Data(count: size)
        var stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        let result = bytes.withUnsafeBytes { incoming in
            output.withUnsafeMutableBytes { outgoing in
                stream.next_in = UnsafeMutablePointer(mutating: incoming.bindMemory(to: UInt8.self).baseAddress)
                stream.avail_in = UInt32(bytes.count)
                stream.next_out = outgoing.bindMemory(to: UInt8.self).baseAddress
                stream.avail_out = UInt32(size)
                return inflate(&stream, Z_FINISH)
            }
        }
        return result == Z_STREAM_END && stream.total_out == size && stream.avail_in == 0 ? output : nil
    }
}

private actor FuelStationFeed {
    static let shared = FuelStationFeed()
    private var checkedAt = Date.distantPast
    private var cached: [FuelPrices.Station] = []
    private var loading: Task<[FuelPrices.Station], Never>?

    func stations() async -> [FuelPrices.Station] {
        if let loading { return await loading.value }
        if Date().timeIntervalSince(checkedAt) < (cached.isEmpty ? 900 : 10_800) { return cached }
        let task = Task.detached(priority: .utility) {
            let url = URL(string: "https://github.com/PimpinPumpkin/Vela/releases/download/fuel-gb/fuel-gb.csv.gz")!
            let request = URLRequest(url: url, timeoutInterval: 15)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let csv = FuelPrices.gunzip(data) else { return [FuelPrices.Station]() }
            return FuelPrices.parseCSV(String(decoding: csv, as: UTF8.self))
        }
        loading = task
        let response = await task.value
        if !response.isEmpty { cached = response }
        checkedAt = Date()
        loading = nil
        return cached
    }
}
