import Foundation

/**
 Whether warning about a fixed speed camera is legal where the car actually is.

 This is a conservative gate, not legal advice. The list below is the one Kite already used, keyed by
 ISO 3166-1 alpha-2 code; it is deliberately not presented as a complete survey of world law. An
 unknown country is treated as **unknown**, never as "allowed", so a failed lookup cannot silently
 enable warnings in a restricted country. The user's language or device region is never used to
 infer where the vehicle is: that can differ by thousands of kilometres.
 */
public enum CameraWarningPolicy: String, Equatable, Sendable {
    case allowed
    case restricted
    case unknown
}

public enum CameraJurisdiction {
    /** Codes for which Kite suppresses camera warnings. Not exhaustive; updated with the app. */
    public static let restrictedISO: Set<String> = ["FR", "DE", "CH", "CY", "SK", "TR"]

    public static func policy(isoCountryCode: String?) -> CameraWarningPolicy {
        guard let raw = isoCountryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              raw.count == 2, raw.allSatisfy({ $0.isLetter }) else { return .unknown }
        return restrictedISO.contains(raw) ? .restricted : .allowed
    }

    /**
     * The device region is used only as a *hint* for an offline first launch, and only when the user
     * has explicitly said they understand it is their own responsibility. Never as proof.
     */
    public static func policy(isoCountryCode: String?, deviceRegion: String?, userAcceptsResponsibility: Bool) -> CameraWarningPolicy {
        let verified = policy(isoCountryCode: isoCountryCode)
        if verified != .unknown || !userAcceptsResponsibility { return verified }
        return policy(isoCountryCode: deviceRegion)
    }

    /** The gate used by the navigator: a preference is honoured only where warnings are allowed. */
    public static func warningsEnabled(userPreference: Bool, policy: CameraWarningPolicy,
                                       userAcceptsResponsibility: Bool) -> Bool {
        guard userPreference else { return false }
        if policy == .allowed { return true }
        // An explicit, persistent acknowledgement can override a conservative unknown or a device hint.
        // It never manufactures a verified country code.
        if userAcceptsResponsibility, policy == .unknown { return true }
        return false
    }
}
