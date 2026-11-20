import SwiftUI

struct MapboxSettings: View {
    @ObservedObject var settings: AppSettings
    @State private var token = ""
    @State private var checking = false
    @State private var failed = false

    var body: some View {
        Toggle(L10n.text("Use Mapbox maps"), isOn: $settings.useMapbox)
            .disabled(settings.mapboxToken.isEmpty)
        SecureField("pk.…", text: $token)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityLabel("Mapbox public token")
        Button(L10n.text("Verify and use token")) {
            let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
            checking = true
            Task {
                var url = URLComponents(string: "https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/0/0/0")!
                url.queryItems = [URLQueryItem(name: "access_token", value: value)]
                let answer = try? await URLSession.shared.data(from: url.url!)
                let valid = (answer?.1 as? HTTPURLResponse)?.statusCode == 200
                if valid { settings.mapboxToken = value; settings.useMapbox = true; token = "" }
                failed = !valid
                checking = false
            }
        }.disabled(checking || !token.hasPrefix("pk.") || token.contains(where: { $0.isWhitespace }))
        if failed { Text(L10n.text("Could not verify the Mapbox token.")).foregroundStyle(.secondary) }
    }
}
