import Foundation
import Network

/** Whether the phone has an internet connection, so a failed search or route can say why. */
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()
    @Published private(set) var online = true
    private var simulatedOffline = false
    private var actualOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let ok = path.status == .satisfied
            Task { @MainActor in
                Connectivity.shared.actualOnline = ok
                Connectivity.shared.online = ok && !Connectivity.shared.simulatedOffline
            }
        }
        monitor.start(queue: DispatchQueue(label: "kite.connectivity"))
    }

    /** Developer replay only: make the app see an outage without touching the network. */
    func setSimulatedOffline(_ on: Bool) {
        simulatedOffline = on
        online = actualOnline && !on
    }

    /** "No internet connection." when offline, else [fallback]. */
    static func explain(_ fallback: String) -> String {
        L10n.text(shared.online ? fallback : "No internet connection. Check your signal and try again.")
    }
}
