import Foundation
import SwiftUI

// MARK: - capturestate

enum CaptureState: String, CaseIterable, Equatable {
    case idle // idlestate, can startcapture
    case countingDown // countdownstate
    case preparing // preparestage(countdown/AI)
    case capturing // in progresscapture(photo/video)
    case processing // stage(filter)
    case saving // savestage
    case completed // completestate
    case error // errorstate

    /// whethercan startcapture
    /// : error statestartcapture()
    var canStartCapture: Bool {
        self == .idle || self == .error
    }

    /// whetherin progresscapture
    var isCapturing: Bool {
        self == .capturing
    }

    /// whetherstate(not startcapture)
    var isBusy: Bool {
        self != .idle && self != .error && self != .completed
    }

    /// whethercan
    var canCancel: Bool {
        self == .preparing || self == .countingDown
    }

    /// whetherwaitstate(triggernot yet startcapture)
    var isWaiting: Bool {
        self == .preparing || self == .countingDown
    }

    /// whetherstate(in progresscapture)
    var isProcessing: Bool {
        self == .capturing || self == .processing
    }
}

// MARK: - capture

enum CaptureAction: String, Equatable {
    case startTimer // startcountdownprepare
    case startCapture // startcapture
    case completeCapture // capturecomplete
    case startSaving // startsave
    case completeSaving // savecomplete
    case cancel // operation
    case reset // resetidlestate
    case error // error
}

// MARK: - capturecontext

struct CaptureContext {
    let mode: CameraCaptureMode
    let isTimerEnabled: Bool
    let isAutomationEnabled: Bool

    var isVideoMode: Bool { mode == .movie }
    var isPhotoMode: Bool { mode == .photo || mode == .livePhoto }
}

// MARK: - stateresult

struct StateTransitionResult {
    let success: Bool
    let fromState: CaptureState
    let toState: CaptureState
    let action: CaptureAction
    let errorMessage: String?

    static func success(from: CaptureState, to: CaptureState, action: CaptureAction) -> StateTransitionResult {
        StateTransitionResult(success: true, fromState: from, toState: to, action: action, errorMessage: nil)
    }

    static func failure(from: CaptureState, action: CaptureAction, error: String) -> StateTransitionResult {
        StateTransitionResult(success: false, fromState: from, toState: from, action: action, errorMessage: error)
    }
}

// MARK: - capturestate

@MainActor
final class CaptureStateMachine: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var currentState: CaptureState = .idle
    @Published private(set) var context: CaptureContext?

    // MARK: - State Observers

    private var stateChangeCallbacks: [(CaptureState, CaptureState) -> Void] = []

    // MARK: - Initialization

    init(initialState: CaptureState = .idle) {
        currentState = initialState
    }

    // MARK: - Context Management

    /// setcapturecontext
    func setContext(mode: CameraCaptureMode, isTimerEnabled: Bool, isAutomationEnabled: Bool) {
        context = CaptureContext(mode: mode, isTimerEnabled: isTimerEnabled, isAutomationEnabled: isAutomationEnabled)
    }

    /// context
    func clearContext() {
        context = nil
    }

    // MARK: - State Transition Methods

    /// state
    @discardableResult
    func transition(action: CaptureAction) -> StateTransitionResult {
        let fromState = currentState
        let toState = getNextState(from: fromState, action: action)

        print("🔄 [StateMachine] Attempting transition: \(fromState.rawValue) -> \(toState.rawValue) via \(action.rawValue)")

        // validatestatewhether
        guard isValidTransition(from: fromState, to: toState, action: action) else {
            let errorMessage = "Invalid transition: \(fromState.rawValue) -> \(toState.rawValue) via \(action.rawValue)"
            print("❌ [StateMachine] \(errorMessage)")
            return StateTransitionResult.failure(from: fromState, action: action, error: errorMessage)
        }

        // state
        currentState = toState
        let result = StateTransitionResult.success(from: fromState, to: toState, action: action)
        print("✅ [StateMachine] Transition successful: \(fromState.rawValue) -> \(toState.rawValue)")

        // notify
        notifyStateChange(from: fromState, to: toState)

        return result
    }

    /// resetidlestate
    func forceReset() {
        let fromState = currentState
        currentState = .idle
        context = nil
        notifyStateChange(from: fromState, to: .idle)
    }

    // MARK: - Convenience Methods

    /// startcapture(contextwhetherneed to preparestage)
    @discardableResult
    func startCapture() -> StateTransitionResult {
        guard let ctx = context else {
            return StateTransitionResult.failure(from: currentState, action: .startCapture, error: "No capture context set")
        }

        // contextwhetherneed to preparestage
        if ctx.isTimerEnabled {
            return transition(action: .startTimer)
        } else {
            // no whetherauto, startCapture preparing
            return transition(action: .startCapture)
        }
    }

    /// startcountdownprepare
    @discardableResult
    func startTimerPreparation() -> StateTransitionResult {
        transition(action: .startTimer)
    }

    /// startcapture
    @discardableResult
    func startActualCapture() -> StateTransitionResult {
        transition(action: .startCapture)
    }

    /// capturecomplete
    @discardableResult
    func completeCapture() -> StateTransitionResult {
        transition(action: .completeCapture)
    }

    /// startsave
    @discardableResult
    func startSaving() -> StateTransitionResult {
        transition(action: .startSaving)
    }

    /// savecomplete
    @discardableResult
    func completeSaving() -> StateTransitionResult {
        transition(action: .completeSaving)
    }

    @discardableResult
    func reset() -> StateTransitionResult {
        transition(action: .reset)
    }

    /// currentoperation
    @discardableResult
    func cancel() -> StateTransitionResult {
        transition(action: .cancel)
    }

    /// error
    @discardableResult
    func reportError() -> StateTransitionResult {
        transition(action: .error)
    }

    // MARK: - Observer Management

    /// addstate
    func addStateChangeObserver(_ callback: @escaping (CaptureState, CaptureState) -> Void) {
        stateChangeCallbacks.append(callback)
    }

    // MARK: - Private Methods

    /// getstate
    private func getNextState(from currentState: CaptureState, action: CaptureAction) -> CaptureState {
        switch (currentState, action) {
        // idlestatestart
        case (.idle, .startTimer):
            return .countingDown

        case (.idle, .startCapture):
            // no whetherauto, startCapture preparing
            return .preparing

        // errorstaterestore(startcapture)
        case (.error, .startTimer):
            return .countingDown

        case (.error, .startCapture):
            // no whetherauto, startCapture preparing
            return .preparing

        // preparestate
        case (.preparing, .startCapture):
            return .capturing

        case (.preparing, .cancel):
            return .idle

        // countdownstate
        case (.countingDown, .startCapture):
            // no whetherauto, startCapture preparing
            return .preparing

        case (.countingDown, .cancel):
            return .idle

        // capturestate
        case (.capturing, .completeCapture):
            return .processing

        // state
        case (.processing, .startSaving):
            return .saving

        // savestate
        case (.saving, .completeSaving):
            return .completed

        // completestate
        case (.completed, .reset):
            return .idle

        // error
        case (_, .error):
            return .error

        case (.error, .reset):
            return .idle

        // resetoperation
        case (_, .reset):
            return .idle

        // defaultcurrentstate
        default:
            return currentState
        }
    }

    /// validatestatewhether
    private func isValidTransition(from: CaptureState, to: CaptureState, action: CaptureAction) -> Bool {
        // reseterroroperation
        if action == .reset || action == .error {
            return true
        }

        // check
        switch (from, to, action) {
        // idlestate
        case (.idle, .countingDown, .startTimer),
             (.idle, .preparing, .startCapture):
            return true

        // errorstaterestore()
        case (.error, .countingDown, .startTimer),
             (.error, .preparing, .startCapture):
            return true

        // preparestate
        case (.preparing, .capturing, .startCapture),
             (.preparing, .idle, .cancel):
            return true

        // countdownstate
        case (.countingDown, .preparing, .startCapture),
             (.countingDown, .idle, .cancel):
            return true

        // capturestate
        case (.capturing, .processing, .completeCapture):
            return true

        // state
        case (.processing, .saving, .startSaving):
            return true

        // savestate
        case (.saving, .completed, .completeSaving):
            return true

        // completestate
        case (.completed, .idle, .reset):
            return true

        // errorstate
        case (.error, .idle, .reset):
            return true

        default:
            return false
        }
    }

    /// notifystate
    private func notifyStateChange(from: CaptureState, to: CaptureState) {
        for callback in stateChangeCallbacks {
            callback(from, to)
        }
    }
}
