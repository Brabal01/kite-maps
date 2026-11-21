import Foundation

/** Road numbers named in a routing instruction, for signs and junction diagrams. */
public enum RoadReferenceParser {
    public static func find(_ text: String) -> [String] {
        let pattern = #"\b(I|US|CA|SR|State Route|Route|Hwy|Highway|A|B|M|E|N|D|SS)[- ]?(\d{1,4}[A-Z]?)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var out: [String] = []
        for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let network = ns.substring(with: match.range(at: 1))
            let number = ns.substring(with: match.range(at: 2))
            let ref: String
            switch network {
            case "I": ref = "I-\(number)"
            case "US": ref = "US \(number)"
            case "CA", "SR", "State Route", "Route", "Hwy", "Highway": ref = "SR \(number)"
            default: ref = network + number
            }
            if !out.contains(ref) { out.append(ref) }
        }
        return Array(out.prefix(3))
    }
}
