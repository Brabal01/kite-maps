import Foundation

/**
 Route planning needs a different kind of location from navigation.

 Planning may start from a last-known or approximate fix, as long as it is
 labelled as such. Navigation needs a fresh, precise fix. This file keeps those
 rules in one deterministic place so the phone code, the UI and the tests all
 agree, with no Core Location or network needed to exercise the state machine.
 */
public enum PlanningMode: Int, CaseIterable, Identifiable, Sendable {
    case drive = 0, bike = 1, walk = 2, transit = 3

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .drive: return "Drive"
        case .bike: return "Bike"
        case .walk: return "Walk"
        case .transit: return "Transit"
        }
    }

    public var travelMode: TravelMode? {
        switch self {
        case .drive: return .drive
        case .bike: return .bike
        case .walk: return .walk
        case .transit: return nil
        }
    }

    public init(_ mode: TravelMode) {
        switch mode {
        case .drive: self = .drive
        case .bike: self = .bike
        case .walk: self = .walk
        }
    }
}

public enum PlanningOriginKind: String, Equatable, Sendable {
    /// A fresh, precise-enough device fix.
    case device
    /// A device fix that is usable for a preview but not for active navigation.
    case approximate
    /// A reliable fix older than the fresh window, kept only for preliminary planning.
    case stale
    /// Typed in or picked on the map: planning must work with no GPS at all.
    case manual
    /// Kept from the previous fix while the GPS is briefly unavailable.
    case estimated
}

public enum PlanningLocationRequestReason: String, Equatable, Sendable {
    case opened, retry, returnedToForeground, stale, resumeFromPause, navigation
}

public enum PlanningFailure: Equatable, Sendable {
    case noRoute
    case offline
    case routerUnavailable
    case permissionDenied
    case locationServicesOff
    case noOrigin
    case impreciseFix
    case staleFix
}

public enum PlanningRouteState: Equatable, Sendable {
    case idle
    case loading
    case loaded(count: Int)
    case failed(PlanningFailure)

    public var isLoading: Bool { self == .loading }
    public var routeCount: Int {
        if case .loaded(let count) = self { return count }
        return 0
    }
    public var failure: PlanningFailure? {
        if case .failed(let failure) = self { return failure }
        return nil
    }
}

public enum PlanningPhase: Equatable, Sendable {
    case idle
    case waitingForPermission
    case searching
    /// A usable (possibly stale or approximate) origin is known.
    case ready
    case failed(PlanningFailure)

    public var isWaitingForLocation: Bool {
        switch self {
        case .waitingForPermission, .searching: return true
        case .idle, .ready, .failed: return false
        }
    }
}

/** How a fix may be used, from best to useless. */
public enum LocationUsability: Equatable, Sendable {
    /// Fresh and precise enough for both planning and navigation.
    case usable(age: TimeInterval, accuracy: Double)
    /// Usable for a preliminary route. Active navigation still asks for precision.
    case approximate(age: TimeInterval, accuracy: Double)
    /// Reliable but old. Preliminary planning only, and clearly labelled.
    case stale(age: TimeInterval, accuracy: Double)
    /// Older than any reasonable planning window.
    case expired(age: TimeInterval, accuracy: Double)
    /// Too inaccurate and not even good enough for a preview.
    case imprecise(age: TimeInterval, accuracy: Double)
    case missing

    public var canPlan: Bool {
        switch self {
        case .usable, .approximate, .stale: return true
        case .expired, .imprecise, .missing: return false
        }
    }

    /**
     A route kept from this fix may be started in navigation without asking for
     a new one. Planning "usable" is deliberately looser than this: 30 s and
     250 m can plan a preview, never guide a car.
     */
    public var isNavigationGrade: Bool {
        if case .usable(let age, let accuracy) = self {
            return age <= 8 && accuracy <= 60
        }
        return false
    }

    public var accuracy: Double? {
        switch self {
        case .usable(_, let accuracy), .approximate(_, let accuracy),
             .stale(_, let accuracy), .expired(_, let accuracy), .imprecise(_, let accuracy):
            return accuracy
        case .missing:
            return nil
        }
    }

    public var age: TimeInterval? {
        switch self {
        case .usable(let age, _), .approximate(let age, _),
             .stale(let age, _), .expired(let age, _), .imprecise(let age, _):
            return age
        case .missing:
            return nil
        }
    }

    public var kind: PlanningOriginKind? {
        switch self {
        case .usable: return .device
        case .approximate: return .approximate
        case .stale: return .stale
        case .expired, .imprecise, .missing: return nil
        }
    }
}

/** One Core Location answer, reduced to what planning needs. */
public struct PlanningFix: Equatable, Sendable {
    public var point: LatLng
    public var timestamp: Date
    public var horizontalAccuracy: Double
    /// False only for an injected/manual fix that never came from the GPS.
    public var fromDevice: Bool

    public init(point: LatLng, timestamp: Date, horizontalAccuracy: Double, fromDevice: Bool = true) {
        self.point = point
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.fromDevice = fromDevice
    }

    /** Reject a damaged sensor answer before it can become a route start. */
    public var hasValidCoordinate: Bool {
        point.lat.isFinite && point.lng.isFinite &&
            (-90...90).contains(point.lat) && (-180...180).contains(point.lng) &&
            !(point.lat == 0 && point.lng == 0)
    }

    /** A fix stamped far in the future is a broken clock, not a current position. */
    public func hasPlausibleTimestamp(at now: Date) -> Bool {
        let ahead = timestamp.timeIntervalSince(now)
        return ahead <= 2
    }
}

/** The planning start point after it has been snapshotted. */
public struct PlanningOrigin: Equatable, Sendable {
    public var point: LatLng
    public var capturedAt: Date
    public var accuracy: Double
    public var kind: PlanningOriginKind
    public var label: String

    public init(point: LatLng, capturedAt: Date, accuracy: Double = 0,
                kind: PlanningOriginKind, label: String = "My location") {
        self.point = point
        self.capturedAt = capturedAt
        self.accuracy = accuracy
        self.kind = kind
        self.label = label
    }

    public static func manual(_ point: LatLng, label: String = "Dropped pin") -> PlanningOrigin {
        PlanningOrigin(point: point, capturedAt: Date(), accuracy: 0, kind: .manual, label: label)
    }

    public func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(capturedAt))
    }

    public var isManual: Bool { kind == .manual }
}

/**
 The age and accuracy rules. These are deliberately split:
 preliminary planning tolerates an older or approximate fix; active
 navigation does not.
 */
public struct PlanningLocationPolicy: Equatable, Sendable {
    /// Up to this age a precise fix is still called fresh and can start navigation.
    public var freshAge: TimeInterval = 30
    /// A reliable fix older than this is not offered for planning at all.
    public var maximumAge: TimeInterval = 600
    /// Enough for planning. Above this a fix is approximate, not precise.
    public var usableAccuracy: Double = 250
    /// Fixed locations can be several kilometres out; still useful for a preview.
    public var approximateAccuracy: Double = 5_000
    /// A new fix must move the planning start at least this far before routes are recalculated.
    public var snapshotDrift: Double = 200
    /// After this long, say that the search is taking a while and offer a retry.
    public var slowAfter: TimeInterval = 15
    /// After this long, offer a manual start as well as waiting.
    public var manualAfter: TimeInterval = 45
    /// Navigation must use a fix no older than this.
    public var navigationMaximumAge: TimeInterval = 8
    /// Navigation must use a fix no less precise than this.
    public var navigationMaximumAccuracy: Double = 60
    /// A navigation start may be re-planned when the phone moved this far from the preview origin.
    public var navigationDrift: Double = 100

    public init() {}

    public func usability(of fix: PlanningFix, at now: Date) -> LocationUsability {
        guard fix.hasValidCoordinate, fix.hasPlausibleTimestamp(at: now) else {
            return .imprecise(age: max(0, now.timeIntervalSince(fix.timestamp)),
                              accuracy: fix.horizontalAccuracy)
        }
        return usability(point: fix.point, timestamp: fix.timestamp,
                         accuracy: fix.horizontalAccuracy, now: now)
    }

    public func usability(of origin: PlanningOrigin, at now: Date) -> LocationUsability {
        if origin.isManual {
            return .usable(age: origin.age(at: now), accuracy: 0)
        }
        return usability(point: origin.point, timestamp: origin.capturedAt,
                         accuracy: origin.accuracy, now: now)
    }

    public func usability(point: LatLng?, timestamp: Date?, accuracy: Double, now: Date) -> LocationUsability {
        guard let point, let timestamp else { return .missing }
        guard point.lat.isFinite, point.lng.isFinite,
              (-90...90).contains(point.lat), (-180...180).contains(point.lng),
              !(point.lat == 0 && point.lng == 0) else { return .missing }
        guard timestamp.timeIntervalSince(now) <= 2 else {
            return .imprecise(age: 0, accuracy: accuracy)
        }
        guard accuracy >= 0, accuracy.isFinite else {
            return .imprecise(age: 0, accuracy: accuracy)
        }
        let age = max(0, now.timeIntervalSince(timestamp))
        guard age <= maximumAge else {
            return .expired(age: age, accuracy: accuracy)
        }
        if accuracy <= usableAccuracy, age <= freshAge {
            return .usable(age: age, accuracy: accuracy)
        }
        if accuracy <= usableAccuracy, age <= maximumAge {
            return .stale(age: age, accuracy: accuracy)
        }
        if accuracy <= approximateAccuracy, age <= maximumAge {
            return .approximate(age: age, accuracy: accuracy)
        }
        return .imprecise(age: age, accuracy: accuracy)
    }

    public func acceptsForNavigation(timestamp: Date?, accuracy: Double, now: Date) -> Bool {
        guard let timestamp else { return false }
        let age = now.timeIntervalSince(timestamp)
        return (-2...navigationMaximumAge).contains(age) &&
            (0...navigationMaximumAccuracy).contains(accuracy) &&
            accuracy.isFinite
    }

    /** Whether a newer fix should move the snapshotted start, or only refresh its age. */
    public func shouldMoveOrigin(current: PlanningOrigin, to fix: PlanningFix, at now: Date) -> Bool {
        guard !current.isManual else { return false }
        // A precise fix may upgrade an approximate start in place, but a real
        // move over the drift threshold always wins.
        return current.point.distance(to: fix.point) > snapshotDrift
    }
}

public struct PlanningEffect: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case requestFreshLocation
        case loadRoute
        case loadBackgroundModes
        case cancelRouteLoads
        case frameRoute
        case showSlowNotice
        case offerManualOrigin
    }

    public var kind: Kind
    /// Every effect names the request generation it belongs to, so a late
    /// answer can never be applied to a newer plan.
    public var requestID: Int
    public var mode: PlanningMode?
    public var reason: PlanningLocationRequestReason?

    init(_ kind: Kind, requestID: Int, mode: PlanningMode? = nil,
         reason: PlanningLocationRequestReason? = nil) {
        self.kind = kind
        self.requestID = requestID
        self.mode = mode
        self.reason = reason
    }
}

/** The version of the trip that the routes are for. */
public struct PlanningSnapshot: Equatable, Sendable {
    public var requestID: Int
    public var destinationID: String
    public var destination: LatLng
    public var origin: PlanningOrigin?
    public var mode: PlanningMode
    public var reversed: Bool
    public var stops: [LatLng]
}

public struct NavigationPreparation: Equatable, Sendable {
    public var canStart: Bool
    public var rerouted: Bool
    public var requestID: Int
    public var origin: PlanningOrigin?
    public var failure: PlanningFailure?
    public var effects: [PlanningEffect]
}

/**
 The event-driven planning state machine.

 It never polls. A fix, a mode tap, a permission change, a foreground return,
 a tick that notices an expired deadline and a route answer are the only
 events. Every route answer carries the request ID it was asked for.
 */
public struct PlanningSession: Equatable, Sendable {
    public var policy: PlanningLocationPolicy
    public private(set) var requestID: Int
    public private(set) var destinationID: String
    public private(set) var destinationName: String
    public private(set) var destination: LatLng
    public private(set) var selectedMode: PlanningMode
    public private(set) var reversed: Bool
    public private(set) var stops: [LatLng]
    public private(set) var manualOrigin: PlanningOrigin?
    public private(set) var deviceOrigin: PlanningOrigin?
    public private(set) var originUsability: LocationUsability = .missing
    public private(set) var phase: PlanningPhase = .idle
    public private(set) var modeStates: [PlanningMode: PlanningRouteState]
    public private(set) var isOpen = false
    public private(set) var isRefreshingLocation = false
    public private(set) var lastLocationRequestAt: Date?
    public private(set) var waitingSince: Date?
    public private(set) var slowLocationNotice = false
    public private(set) var manualOriginOffered = false
    public private(set) var lastEventAt: Date?

    public init(destinationID: String = UUID().uuidString, destinationName: String = "Destination",
                destination: LatLng, mode: PlanningMode = .drive, reversed: Bool = false,
                stops: [LatLng] = [], manualOrigin: PlanningOrigin? = nil,
                deviceOrigin: PlanningOrigin? = nil,
                policy: PlanningLocationPolicy = PlanningLocationPolicy()) {
        self.requestID = 1
        self.destinationID = destinationID
        self.destinationName = destinationName
        self.destination = destination
        self.selectedMode = mode
        self.reversed = reversed
        self.stops = stops
        self.manualOrigin = manualOrigin
        self.deviceOrigin = deviceOrigin
        self.policy = policy
        self.modeStates = Dictionary(uniqueKeysWithValues: PlanningMode.allCases.map { ($0, .idle) })
    }

    public var origin: PlanningOrigin? { manualOrigin ?? deviceOrigin }

    public var snapshot: PlanningSnapshot {
        PlanningSnapshot(requestID: requestID, destinationID: destinationID,
                         destination: destination, origin: origin,
                         mode: selectedMode, reversed: reversed, stops: stops)
    }

    public var needsDeviceLocation: Bool { manualOrigin == nil }

    public var isWaitingForLocation: Bool {
        guard isOpen, needsDeviceLocation else { return false }
        if case .failed = phase { return false }
        return origin == nil || !originUsability.canPlan
    }

    public var selectedRouteState: PlanningRouteState {
        modeStates[selectedMode] ?? .idle
    }

    public var selectedFailure: PlanningFailure? { selectedRouteState.failure }

    public var canStartNavigation: Bool {
        guard let origin, needsDeviceLocation else { return manualOrigin != nil }
        return originUsability.isNavigationGrade && origin.kind != .manual
    }

    /** Open the planner and decide whether a route can be shown immediately. */
    public mutating func start(now: Date = Date()) -> [PlanningEffect] {
        isOpen = true
        lastEventAt = now
        phase = .idle
        if let manual = manualOrigin {
            applyOrigin(manual, at: now)
            phase = .ready
            var effects = routeEffects(for: selectedMode)
            effects.append(effect(.loadBackgroundModes, mode: selectedMode))
            return effects
        }
        if let device = deviceOrigin {
            applyOrigin(device, at: now)
            if originUsability.canPlan {
                phase = .ready
                // Show the usable preview at once, and refresh in the background.
                var effects = [requestLocation(.opened, at: now)]
                effects += routeEffects(for: selectedMode)
                effects.append(effect(.loadBackgroundModes, mode: selectedMode))
                return effects
            }
        }
        phase = .searching
        waitingSince = now
        return [requestLocation(.opened, at: now)]
    }

    /** A route answer arrived. Late answers from an older request are ignored. */
    public mutating func routeLoaded(mode: PlanningMode, requestID: Int, count: Int,
                                     now: Date = Date()) -> [PlanningEffect] {
        guard isOpen, requestID == self.requestID else { return [] }
        lastEventAt = now
        guard count > 0 else {
            modeStates[mode] = .failed(.noRoute)
            return []
        }
        modeStates[mode] = .loaded(count: count)
        if mode == selectedMode {
            if origin != nil { phase = .ready }
            return [effect(.frameRoute, mode: mode)]
        }
        return []
    }

    public mutating func routeFailed(mode: PlanningMode, requestID: Int,
                                     failure: PlanningFailure, now: Date = Date()) -> [PlanningEffect] {
        guard isOpen, requestID == self.requestID else { return [] }
        lastEventAt = now
        modeStates[mode] = .failed(failure)
        if mode == selectedMode, failure == .permissionDenied || failure == .locationServicesOff {
            phase = .failed(failure)
        }
        return []
    }

    /** A route request was started; duplicate loads for one mode are avoided. */
    public mutating func routeStarted(mode: PlanningMode, requestID: Int,
                                      now: Date = Date()) -> Bool {
        guard isOpen, requestID == self.requestID else { return false }
        if modeStates[mode]?.isLoading == true { return false }
        modeStates[mode] = .loading
        lastEventAt = now
        return true
    }

    /** A GPS fix arrived while the planner is open. */
    public mutating func location(_ fix: PlanningFix, now: Date = Date()) -> [PlanningEffect] {
        guard isOpen else { return [] }
        lastEventAt = now
        let usability = policy.usability(of: fix, at: now)

        guard usability.canPlan else {
            guard manualOrigin == nil else { return [] }
            let previous = deviceOrigin.map { policy.usability(of: $0, at: now) } ?? .missing
            if previous.canPlan {
                // A poor new sample must not replace a start that is still usable.
                originUsability = previous
                return []
            }
            originUsability = usability
            phase = .searching
            if waitingSince == nil { waitingSince = now }
            if !isRefreshingLocation {
                return [requestLocation(.retry, at: now)]
            }
            return []
        }

        // A start chosen by hand stays put while the phone moves; only the
        // navigation check may replace it.
        if manualOrigin != nil {
            applyOrigin(manualOrigin, at: now)
            isRefreshingLocation = false
            waitingSince = nil
            phase = .ready
            return []
        }

        let newOrigin = origin(for: fix, usability: usability)
        var moved = false
        var hadOrigin = false

        if let existing = deviceOrigin, manualOrigin == nil {
            hadOrigin = true
            if policy.shouldMoveOrigin(current: existing, to: fix, at: now) {
                deviceOrigin = newOrigin
                moved = true
            } else {
                // Keep the stable point, but refresh its age and accuracy so a
                // standing phone does not look stale while fixes keep coming.
                deviceOrigin?.capturedAt = fix.timestamp
                deviceOrigin?.accuracy = min(fix.horizontalAccuracy, existing.accuracy == 0 ? fix.horizontalAccuracy : existing.accuracy)
                if usability.isNavigationGrade { deviceOrigin?.kind = .device }
            }
        } else if manualOrigin == nil {
            deviceOrigin = newOrigin
            hadOrigin = false
        }

        applyOrigin(origin, at: now)
        isRefreshingLocation = false
        lastLocationRequestAt = nil
        waitingSince = nil
        slowLocationNotice = false
        manualOriginOffered = false

        if manualOrigin == nil, hadOrigin, !moved, phase == .ready {
            // Same start point: no route change, only fresher provenance.
            return []
        }

        phase = .ready
        if !hadOrigin || moved {
            modeStates = Dictionary(uniqueKeysWithValues: PlanningMode.allCases.map { ($0, .idle) })
            var effects = [effect(.cancelRouteLoads)]
            effects += routeEffects(for: selectedMode)
            effects.append(effect(.loadBackgroundModes, mode: selectedMode))
            effects.append(effect(.frameRoute, mode: selectedMode))
            return effects
        }
        return []
    }

    /** A new fix may be less useful than the last one; keep the old start if it still can plan. */
    public mutating func rejectedLocation(_ fix: PlanningFix, now: Date = Date()) {
        guard isOpen else { return }
        let usability = policy.usability(of: fix, at: now)
        if !usability.canPlan, origin == nil {
            originUsability = usability
            phase = .searching
            if waitingSince == nil { waitingSince = now }
        }
    }

    /** Switching tabs must never cancel the location request or move the origin. */
    public mutating func selectMode(_ mode: PlanningMode, now: Date = Date()) -> [PlanningEffect] {
        guard isOpen else { return [] }
        lastEventAt = now
        selectedMode = mode
        guard origin != nil, originUsability.canPlan else {
            // The request for a fix is already running and is shared by every mode.
            return []
        }
        switch modeStates[mode] ?? .idle {
        case .loaded:
            return [effect(.frameRoute, mode: mode)]
        case .loading:
            return []
        case .idle, .failed:
            modeStates[mode] = .loading
            return [effect(.loadRoute, mode: mode)]
        }
    }

    /** Change origin by hand: planning must then work with the GPS off. */
    public mutating func setManualOrigin(_ origin: PlanningOrigin?, now: Date = Date()) -> [PlanningEffect] {
        guard isOpen else { return [] }
        requestID += 1
        lastEventAt = now
        manualOrigin = origin
        modeStates = Dictionary(uniqueKeysWithValues: PlanningMode.allCases.map { ($0, .idle) })
        guard let origin else {
            applyOrigin(deviceOrigin, at: now)
            if deviceOrigin == nil {
                phase = .searching
                waitingSince = now
                return [effect(.cancelRouteLoads), requestLocation(.retry, at: now)]
            }
            phase = .ready
            return [effect(.cancelRouteLoads), requestLocation(.retry, at: now)]
        }
        applyOrigin(origin, at: now)
        phase = .ready
        isRefreshingLocation = false
        waitingSince = nil
        slowLocationNotice = false
        manualOriginOffered = false
        var effects = [effect(.cancelRouteLoads)]
        effects += routeEffects(for: selectedMode)
        effects.append(effect(.frameRoute, mode: selectedMode))
        return effects
    }

    /** A different destination or a reversed trip invalidates every route. */
    public mutating func changeDestination(id: String, name: String, point: LatLng,
                                           reversed: Bool? = nil, stops: [LatLng]? = nil,
                                           now: Date = Date()) -> [PlanningEffect] {
        guard isOpen else { return [] }
        requestID += 1
        lastEventAt = now
        destinationID = id
        destinationName = name
        destination = point
        if let reversed { self.reversed = reversed }
        if let stops { self.stops = stops }
        modeStates = Dictionary(uniqueKeysWithValues: PlanningMode.allCases.map { ($0, .idle) })
        if origin == nil || !originUsability.canPlan {
            phase = .searching
            return [effect(.cancelRouteLoads), requestLocation(.retry, at: now)]
        }
        phase = .ready
        var effects = [effect(.cancelRouteLoads)]
        effects += routeEffects(for: selectedMode)
        return effects
    }

    public mutating func retryLocation(now: Date = Date()) -> [PlanningEffect] {
        guard isOpen else { return [] }
        lastEventAt = now
        slowLocationNotice = false
        manualOriginOffered = false
        if origin == nil || !originUsability.canPlan {
            phase = .searching
            waitingSince = now
        }
        return [requestLocation(.retry, at: now)]
    }

    /** Coming back from the background (or an unlocked phone) always asks for a fresh fix. */
    public mutating func returnedToForeground(now: Date = Date()) -> [PlanningEffect] {
        guard isOpen, needsDeviceLocation else { return [] }
        lastEventAt = now
        if origin == nil || !originUsability.canPlan {
            phase = .searching
            waitingSince = now
        }
        return [requestLocation(.returnedToForeground, at: now)]
    }

    /** Core Location paused our updates on its own. Ask again once it resumes. */
    public mutating func updatesPaused(now: Date = Date()) -> [PlanningEffect] {
        guard isOpen, needsDeviceLocation else { return [] }
        lastEventAt = now
        return [requestLocation(.resumeFromPause, at: now)]
    }

    public mutating func permissionChanged(granted: Bool, denied: Bool, servicesOff: Bool,
                                           now: Date = Date()) -> [PlanningEffect] {
        guard isOpen else { return [] }
        lastEventAt = now
        if servicesOff {
            phase = .failed(.locationServicesOff)
            isRefreshingLocation = false
            return []
        }
        if denied {
            // A manual start and a manual destination do not need the GPS at all.
            guard needsDeviceLocation, origin == nil || !originUsability.canPlan else { return [] }
            phase = .failed(.permissionDenied)
            isRefreshingLocation = false
            return []
        }
        guard granted else {
            if needsDeviceLocation, origin == nil { phase = .waitingForPermission }
            return []
        }
        if phase == .waitingForPermission || (needsDeviceLocation && (origin == nil || !originUsability.canPlan)) {
            phase = origin == nil ? .searching : .ready
            return [requestLocation(.opened, at: now)]
        }
        return []
    }

    /**
     Deadlines are checked when the app has a reason to look at the clock
     (opening, a mode tap, a fix, a foreground return), never by polling.
     */
    public mutating func tick(now: Date = Date()) -> [PlanningEffect] {
        guard isOpen else { return [] }
        lastEventAt = now
        if case .failed(.permissionDenied) = phase { return [] }
        if case .failed(.locationServicesOff) = phase { return [] }
        if let origin {
            originUsability = policy.usability(of: origin, at: now)
        }

        guard needsDeviceLocation else { return [] }

        // A location request that has not produced a fix within the slow
        // window is treated as finished, so the next deadline can retry it.
        if isRefreshingLocation, let requestedAt = lastLocationRequestAt,
           now.timeIntervalSince(requestedAt) >= policy.slowAfter {
            isRefreshingLocation = false
        }

        if origin == nil || !originUsability.canPlan {
            phase = .searching
            if waitingSince == nil { waitingSince = now }
            let waited = now.timeIntervalSince(waitingSince ?? now)
            var effects: [PlanningEffect] = []
            if waited >= policy.slowAfter, !slowLocationNotice {
                slowLocationNotice = true
                effects.append(effect(.showSlowNotice))
            }
            if waited >= policy.manualAfter, !manualOriginOffered {
                manualOriginOffered = true
                effects.append(effect(.offerManualOrigin))
            }
            if !isRefreshingLocation {
                effects.append(requestLocation(.stale, at: now))
            }
            return effects
        }

        // A route from an old fix is still shown, but the start needs refreshing.
        if case .stale = originUsability, !isRefreshingLocation {
            return [requestLocation(.stale, at: now)]
        }
        return []
    }

    /** Closing the planner cancels its route loads and stops waiting for a fix. */
    public mutating func close(now: Date = Date()) -> [PlanningEffect] {
        guard isOpen else { return [] }
        requestID += 1
        isOpen = false
        phase = .idle
        isRefreshingLocation = false
        waitingSince = nil
        slowLocationNotice = false
        manualOriginOffered = false
        lastEventAt = now
        modeStates = Dictionary(uniqueKeysWithValues: PlanningMode.allCases.map { ($0, .idle) })
        return [effect(.cancelRouteLoads)]
    }

    /**
     Before guidance starts, demand a navigation-grade fix. A significant move
     since the preview must recalculate the route from where the phone is now.
     */
    public mutating func prepareNavigation(fix: PlanningFix?, now: Date = Date()) -> NavigationPreparation {
        guard isOpen else {
            return NavigationPreparation(canStart: false, rerouted: false, requestID: requestID,
                                         origin: origin, failure: .noOrigin, effects: [])
        }
        lastEventAt = now
        guard let fix else {
            return NavigationPreparation(canStart: false, rerouted: false, requestID: requestID,
                                         origin: origin, failure: .impreciseFix,
                                         effects: [requestLocation(.navigation, at: now)])
        }
        guard fix.hasValidCoordinate, fix.hasPlausibleTimestamp(at: now),
              policy.acceptsForNavigation(timestamp: fix.timestamp,
                                          accuracy: fix.horizontalAccuracy, now: now) else {
            return NavigationPreparation(canStart: false, rerouted: false, requestID: requestID,
                                         origin: origin, failure: .impreciseFix,
                                         effects: [requestLocation(.navigation, at: now)])
        }

        let fresh = planningOrigin(for: fix, usability: policy.usability(of: fix, at: now))
        let moved = origin.map { $0.point.distance(to: fix.point) > policy.navigationDrift } ?? true
        if moved {
            requestID += 1
            manualOrigin = nil
            deviceOrigin = fresh
            applyOrigin(fresh, at: now)
            phase = .ready
            modeStates = Dictionary(uniqueKeysWithValues: PlanningMode.allCases.map { ($0, .idle) })
            modeStates[selectedMode] = .loading
            var effects = [effect(.cancelRouteLoads)]
            effects += routeEffects(for: selectedMode)
            return NavigationPreparation(canStart: false, rerouted: true, requestID: requestID,
                                         origin: fresh, failure: nil, effects: effects)
        }
        if deviceOrigin != nil { deviceOrigin = fresh }
        applyOrigin(fresh, at: now)
        return NavigationPreparation(canStart: true, rerouted: false, requestID: requestID,
                                     origin: origin ?? fresh, failure: nil, effects: [])
    }

    // MARK: internals

    private func effect(_ kind: PlanningEffect.Kind, mode: PlanningMode? = nil,
                        reason: PlanningLocationRequestReason? = nil) -> PlanningEffect {
        PlanningEffect(kind, requestID: requestID, mode: mode, reason: reason)
    }

    private mutating func requestLocation(_ reason: PlanningLocationRequestReason,
                                          at now: Date) -> PlanningEffect {
        isRefreshingLocation = true
        lastLocationRequestAt = now
        return effect(.requestFreshLocation, reason: reason)
    }

    private mutating func routeEffects(for mode: PlanningMode) -> [PlanningEffect] {
        modeStates[mode] = .loading
        return [effect(.loadRoute, mode: mode)]
    }

    private func origin(for fix: PlanningFix, usability: LocationUsability) -> PlanningOrigin {
        let kind: PlanningOriginKind
        switch usability {
        case .usable: kind = .device
        case .approximate: kind = .approximate
        case .stale: kind = .stale
        case .expired, .imprecise, .missing: kind = .estimated
        }
        return PlanningOrigin(point: fix.point, capturedAt: fix.timestamp,
                              accuracy: fix.horizontalAccuracy, kind: kind)
    }

    private func planningOrigin(for fix: PlanningFix, usability: LocationUsability) -> PlanningOrigin {
        origin(for: fix, usability: usability)
    }

    private mutating func applyOrigin(_ value: PlanningOrigin?, at now: Date) {
        guard let value else {
            originUsability = .missing
            return
        }
        originUsability = policy.usability(of: value, at: now)
    }
}
