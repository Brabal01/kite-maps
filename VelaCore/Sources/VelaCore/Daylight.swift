import Foundation

public enum Daylight {
    /// Solar elevation at the map coordinates, evaluated in UTC.
    public static func isDark(at point: LatLng, time: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let utc = calendar.dateComponents([.hour, .minute, .second], from: time)
        let hour = Double(utc.hour ?? 0) + Double(utc.minute ?? 0) / 60 + Double(utc.second ?? 0) / 3600
        let day = calendar.ordinality(of: .day, in: .year, for: time) ?? 1
        let days = calendar.range(of: .day, in: .year, for: time)?.count ?? 365
        let gamma = 2 * Double.pi / Double(days) * (Double(day - 1) + (hour - 12) / 24)
        let equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                                 - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let radians = Double.pi / 180
        let hourAngle = ((hour * 60 + equation + 4 * point.lng) / 4 - 180) * radians
        let latitude = point.lat * radians
        let altitude = sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle)
        return altitude < sin(-0.833 * radians)
    }
}
