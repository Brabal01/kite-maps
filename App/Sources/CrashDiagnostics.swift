import Foundation
import MetricKit

/**
 * MetricKit delivers crash diagnostics on a later launch. We keep only the technical fields needed
 * to identify the fault (exception type, signal, termination reason and the call-stack tree) and
 * never any location or query. Safe mode shows the summary.
 */
final class CrashDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashDiagnostics()
    private let key = "kiteLastCrash"
    private let lock = NSLock()

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads.flatMap { $0.crashDiagnostics ?? [] }
        guard let crash = crashes.last else { return }
        let stack = crash.callStackTree.jsonRepresentation()
        let summary: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: Date()),
            "exceptionType": crash.exceptionType?.intValue ?? 0,
            "signal": crash.signal?.intValue ?? 0,
            "terminationReason": crash.terminationReason ?? "",
            "virtualMemoryRegion": crash.virtualMemoryRegionInfo ?? "",
            "stack": String(data: stack, encoding: .utf8) ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        UserDefaults.standard.set(text, forKey: key)
        lock.unlock()
    }

    static var last: String? {
        UserDefaults.standard.string(forKey: "kiteLastCrash")
    }
}
