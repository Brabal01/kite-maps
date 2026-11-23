import Foundation

/**
 * The one source of truth for "is live traffic on this map right now, and why".
 *
 * Traffic is three different things that V36 keeps apart:
 *   .map      a live overlay across the visible roads, independent of any route;
 *   .route    congestion on the planned / active route only;
 *   .incident  accidents, closures, hazards — not a measured speed in itself.
 *
 * The state bundles everything the app (and the layer inspector, and the settings
 * toggle) needs to answer a single question honestly: what traffic is visible on
 * this renderer, and if none, exactly why. A tile's download time is *not* the
 * age of its data, so freshness is reported from the provider's own statement
 * when it has one, and left unknown otherwise.
 */
public struct TrafficOverlayState: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// Live congestion across the visible map, no route needed.
        case map
        /// Congestion on a planned or active route.
        case route
        /// Accidents, closures and hazards (not a measured speed).
        case incident
    }

    public enum Provider: String, Hashable, Sendable {
        case apple = "Apple Maps traffic"
        case google = "Google traffic tiles"
        case transitous = "Transitous network"
        case none = "none"
    }

    public enum Status: String, Hashable, Sendable {
        /// The layer is on and currently showing data.
        case on
        /// The layer is off by the user or the preset.
        case off
        /// Waiting for the renderer / tiles to load or refresh.
        case loading
        /// The provider has no usable traffic for the current renderer or area.
        case unavailable
        /// The provider serves no data in this region at all.
        case noCoverage
    }

    public var kind: Kind
    public var provider: Provider
    public var renderer: String
    /// The user's traffic switch.
    public var requested: Bool
    /// Whether the renderer actually supports this provider's overlay.
    public var rendererReady: Bool
    /// Whether the underlying data is actually loaded.
    public var dataLoaded: Bool
    /// A tile / span was received at this time (not necessarily when its data was true).
    public var receivedAt: Date?
    /// The provider's own stated freshness, when it has one.
    public var dataAge: TimeInterval?
    /// When the provider is a measured-speed source, the severity levels it uses.
    public var legend: [TrafficLevel]?
    /// A human reason for the current status, for the inspector / diagnostics.
    public var reason: String?
    public var lastError: String?

    public init(kind: Kind, provider: Provider, renderer: String, requested: Bool,
                rendererReady: Bool, dataLoaded: Bool, receivedAt: Date? = nil,
                dataAge: TimeInterval? = nil, legend: [TrafficLevel]? = nil,
                reason: String? = nil, lastError: String? = nil) {
        self.kind = kind
        self.provider = provider
        self.renderer = renderer
        self.requested = requested
        self.rendererReady = rendererReady
        self.dataLoaded = dataLoaded
        self.receivedAt = receivedAt
        self.dataAge = dataAge
        self.legend = legend
        self.reason = reason
        self.lastError = lastError
    }

    public var status: Status {
        if !requested { return .off }
        if let lastError, lastError != "" { return .unavailable }
        if !rendererReady { return .unavailable }
        if !dataLoaded {
            // The layer is on but nothing has arrived yet: say so rather than pretend "on".
            return provider == .none ? .noCoverage : .loading
        }
        return provider == .none ? .noCoverage : .on
    }

    public var isVisible: Bool { requested && rendererReady && dataLoaded && provider != .none }

    public static func map(_ requested: Bool, provider: Provider, renderer: String,
                           rendererReady: Bool, dataLoaded: Bool, receivedAt: Date? = nil,
                           dataAge: TimeInterval? = nil, legend: [TrafficLevel]? = nil,
                           reason: String? = nil, lastError: String? = nil) -> TrafficOverlayState {
        TrafficOverlayState(kind: .map, provider: provider, renderer: renderer, requested: requested,
                            rendererReady: rendererReady, dataLoaded: dataLoaded,
                            receivedAt: receivedAt, dataAge: dataAge, legend: legend,
                            reason: reason, lastError: lastError)
    }
}

/** One congestion level a provider recognises, with the colour and meaning it publishes. */
public struct TrafficLevel: Hashable, Sendable {
    public var name: String
    public var color: UInt32
    public init(name: String, color: UInt32) {
        self.name = name
        self.color = color
    }
}