import SwiftUI

struct PragueTransitSettings: View {
    @State private var key = ""
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                SecureField("Golemio API token", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save token") { store(key) }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove token", role: .destructive) { store("") }
                if let status { Text(status).foregroundStyle(.secondary) }
            } footer: {
                Text("For Prague Integrated Transport trips, the token enables live vehicle positions and delays from Golemio.")
            }
        }
        .kiteList()
        .navigationTitle("Prague PID live data")
        .onAppear { key = PidKeyStore.read() }
    }

    private func store(_ value: String) {
        if PidKeyStore.write(value) {
            key = PidKeyStore.read()
            status = key.isEmpty ? "Token removed" : "Token saved"
        } else {
            status = "Could not save this token to Keychain."
        }
    }
}
