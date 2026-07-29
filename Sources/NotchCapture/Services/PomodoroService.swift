import AppKit
import Foundation

@MainActor
struct PomodoroCompletionAlert {
    let play: () -> Void
    let stop: () -> Void

    static func glass() -> Self {
        let sound = NSSound(named: NSSound.Name("Glass"))
        sound?.loops = false
        return Self(
            play: {
                sound?.stop()
                sound?.currentTime = 0
                sound?.loops = false
                sound?.play()
            },
            stop: {
                sound?.stop()
                sound?.currentTime = 0
            }
        )
    }
}

private final class PomodoroObservationLifetime: @unchecked Sendable {
    var wakeObserver: NSObjectProtocol?

    @MainActor
    func stop() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }
}

@MainActor
final class PomodoroService {
    private(set) var state: PomodoroState
    var onChange: (@MainActor (PomodoroState) -> Void)?
    var onCompleted: (@MainActor () -> Void)?

    private let now: () -> Date
    private let persistDuration: (TimeInterval) -> Void
    private let completionAlert: PomodoroCompletionAlert
    private var completionTask: Task<Void, Never>?
    private var sessionGeneration: UInt64 = 0
    private let observationLifetime = PomodoroObservationLifetime()

    init(
        duration: TimeInterval = PomodoroState.defaultDuration,
        now: @escaping () -> Date = { .now },
        persistDuration: @escaping (TimeInterval) -> Void = { _ in },
        completionAlert: PomodoroCompletionAlert = .glass()
    ) {
        let clamped = min(max(duration, PomodoroState.durationRange.lowerBound), PomodoroState.durationRange.upperBound)
        self.state = PomodoroState(duration: clamped)
        self.now = now
        self.persistDuration = persistDuration
        self.completionAlert = completionAlert
        observationLifetime.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.revalidateDeadline() }
        }
    }

    deinit {
        completionTask?.cancel()
        let completionAlert = completionAlert
        let observationLifetime = observationLifetime
        Task { @MainActor in
            completionAlert.stop()
            observationLifetime.stop()
        }
    }

    func toggle() {
        switch state.phase {
        case .idle, .finished: start()
        case .running: pause()
        case .paused: resume()
        }
    }

    func start() {
        invalidateScheduledCompletion()
        completionAlert.stop()
        state.phase = .running(endsAt: now().addingTimeInterval(state.duration))
        publish()
        scheduleCompletion()
    }

    func pause() {
        guard case .running = state.phase else { return }
        let remaining = state.remaining(at: now())
        invalidateScheduledCompletion()
        state.phase = .paused(remaining: remaining)
        publish()
    }

    func resume() {
        guard case let .paused(remaining) = state.phase else { return }
        invalidateScheduledCompletion()
        completionAlert.stop()
        state.phase = .running(endsAt: now().addingTimeInterval(remaining))
        publish()
        scheduleCompletion()
    }

    func reset() {
        invalidateScheduledCompletion()
        completionAlert.stop()
        state.phase = .idle
        publish()
    }

    func setDuration(_ duration: TimeInterval) {
        let clamped = min(max(duration, PomodoroState.durationRange.lowerBound), PomodoroState.durationRange.upperBound)
        invalidateScheduledCompletion()
        completionAlert.stop()
        state = PomodoroState(duration: clamped)
        persistDuration(clamped)
        publish()
    }

    func revalidateDeadline() {
        guard case let .running(endsAt) = state.phase else { return }
        if endsAt <= now() {
            finish()
        } else {
            scheduleCompletion()
        }
    }

    private func publish() {
        onChange?(state)
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        guard case let .running(endsAt) = state.phase else { return }
        let generation = sessionGeneration
        let delay = max(0, endsAt.timeIntervalSince(now()))
        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  let self,
                  self.sessionGeneration == generation,
                  case let .running(currentEndsAt) = self.state.phase,
                  currentEndsAt == endsAt else { return }
            self.revalidateDeadline()
        }
    }

    private func finish() {
        guard case .running = state.phase else { return }
        invalidateScheduledCompletion()
        state.phase = .finished
        publish()
        completionAlert.play()
        onCompleted?()
    }

    private func invalidateScheduledCompletion() {
        sessionGeneration &+= 1
        completionTask?.cancel()
        completionTask = nil
    }
}
