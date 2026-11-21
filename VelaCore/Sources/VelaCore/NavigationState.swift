import Foundation

/**
 One explicit lifecycle for guidance.

 `Navigator` still owns the prose, cameras and speech. This machine owns the
 one answer to "what is happening now?", so two booleans can never disagree
 with the banner, and a late reroute answer cannot revive an ended trip.
 */
public enum NavigationState: String, Equatable, Sendable, CaseIterable {
    case idle
    case preparing
    case waitingForGPS
    case navigating
    case gpsUncertain
    case gpsLost
    case offRoute
    case rerouting
    case rerouteUnavailable
    case routeRecovered
    case arriving
    case arrived
    case ended

    public var isActive: Bool {
        switch self {
        case .preparing, .waitingForGPS, .navigating, .gpsUncertain, .gpsLost,
             .offRoute, .rerouting, .rerouteUnavailable, .routeRecovered, .arriving:
            return true
        case .idle, .arrived, .ended:
            return false
        }
    }

    public var showsGuidance: Bool { isActive && self != .preparing }
}

public enum NavigationEvent: Equatable, Sendable {
    case started
    case awaitingFirstFix
    case firstFix
    case gpsUncertain
    case gpsLost
    case gpsRecovered
    case leftRoute
    case rerouteRequested
    case rerouteSucceeded
    case rerouteFailed
    case returnedToRoute
    case approachingArrival
    case arrived
    case ended
}

/**
 A small, deterministic transition table. Unknown transitions are ignored
 rather than producing an illogical combination such as "arrived while
 rerouting".
 */
public struct NavigationSessionState: Equatable, Sendable {
    public let id: UUID
    public private(set) var state: NavigationState
    public private(set) var lastEventAt: Date?
    public private(set) var transitionCount: Int
    /** The state to return to when a temporary uncertainty clears. */
    private var recoveryState: NavigationState

    public init(id: UUID = UUID(), state: NavigationState = .idle,
                now: Date? = nil) {
        self.id = id
        self.state = state
        self.recoveryState = state == .idle ? .navigating : state
        self.lastEventAt = now
        self.transitionCount = 0
    }

    public var isTerminal: Bool { state == .ended }

    @discardableResult
    public mutating func send(_ event: NavigationEvent, at now: Date = Date()) -> NavigationState {
        guard !isTerminal else { return state }
        let next: NavigationState?
        switch event {
        case .started:
            next = state == .idle ? .preparing : nil
        case .awaitingFirstFix:
            next = state == .preparing ? .waitingForGPS : nil
        case .firstFix:
            switch state {
            case .preparing, .waitingForGPS, .routeRecovered:
                next = .navigating
            case .gpsLost, .gpsUncertain:
                next = recoveryState
            default:
                next = nil
            }
        case .gpsUncertain:
            if [.navigating, .offRoute, .rerouting, .routeRecovered, .arriving].contains(state) {
                recoveryState = state
                next = .gpsUncertain
            } else {
                next = nil
            }
        case .gpsLost:
            if [.navigating, .gpsUncertain, .offRoute, .rerouting,
                .rerouteUnavailable, .routeRecovered, .arriving].contains(state) {
                if state != .gpsUncertain { recoveryState = state }
                next = .gpsLost
            } else {
                next = nil
            }
        case .gpsRecovered:
            next = [.gpsLost, .gpsUncertain].contains(state) ? recoveryState : nil
        case .leftRoute:
            if [.navigating, .gpsUncertain, .routeRecovered, .arriving].contains(state) {
                next = .offRoute
            } else {
                next = nil
            }
        case .rerouteRequested:
            if [.offRoute, .navigating, .gpsUncertain, .gpsLost, .rerouteUnavailable].contains(state) {
                next = .rerouting
            } else {
                next = nil
            }
        case .rerouteSucceeded:
            next = state == .rerouting ? .navigating : nil
        case .rerouteFailed:
            next = state == .rerouting ? .rerouteUnavailable : nil
        case .returnedToRoute:
            if [.offRoute, .rerouting, .rerouteUnavailable, .gpsUncertain, .gpsLost].contains(state) {
                next = .routeRecovered
            } else {
                next = nil
            }
        case .approachingArrival:
            if [.navigating, .gpsUncertain, .routeRecovered].contains(state) {
                next = .arriving
            } else {
                next = nil
            }
        case .arrived:
            next = [.navigating, .arriving, .gpsUncertain, .routeRecovered].contains(state) ? .arrived : nil
        case .ended:
            next = state == .ended ? nil : .ended
        }

        guard let next, next != state else { return state }
        state = next
        transitionCount += 1
        lastEventAt = now
        return state
    }

    /** Feed the coarse facts that already exist in Navigator, without duplicating its logic. */
    @discardableResult
    public mutating func update(hasProgress: Bool, arrived: Bool, rerouting: Bool,
                                gpsLost: Bool, estimating: Bool, offRoute: Bool,
                                remainingMeters: Double?, at now: Date = Date()) -> NavigationState {
        if arrived { return send(.arrived, at: now) }
        if !hasProgress {
            if state == .idle { _ = send(.started, at: now) }
            return send(.awaitingFirstFix, at: now)
        }
        if gpsLost { return send(.gpsLost, at: now) }
        if estimating { return send(.gpsUncertain, at: now) }
        if rerouting { return send(.rerouteRequested, at: now) }
        if offRoute { return send(.leftRoute, at: now) }
        if let remainingMeters, remainingMeters <= 120,
           ![.arriving, .arrived].contains(state) {
            return send(.approachingArrival, at: now)
        }
        if [.offRoute, .rerouting, .rerouteUnavailable].contains(state) {
            return send(.returnedToRoute, at: now)
        }
        return send(.firstFix, at: now)
    }
}
