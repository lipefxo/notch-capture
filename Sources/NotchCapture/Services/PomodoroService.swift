import AppKit
import Foundation

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
    private var completionTask: Task<Void, Never>?
    private let observationLifetime = PomodoroObservationLifetime()

    init(
        duration: TimeInterval = PomodoroState.defaultDuration,
        now: @escaping () -> Date = { .now },
        persistDuration: @escaping (TimeInterval) -> Void = { _ in }
    ) {
        let clamped = min(max(duration, PomodoroState.durationRange.lowerBound), PomodoroState.durationRange.upperBound)
        self.state = PomodoroState(duration: clamped)
        self.now = now
        self.persistDuration = persistDuration
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
        let observationLifetime = observationLifetime
        Task { @MainActor in observationLifetime.stop() }
    }

    func toggle() {
        switch state.phase {
        case .idle, .finished: start()
        case .running: pause()
        case .paused: resume()
        }
    }

    func start() {
        state.phase = .running(endsAt: now().addingTimeInterval(state.duration))
        publish()
        scheduleCompletion()
    }

    func pause() {
        guard case .running = state.phase else { return }
        let remaining = state.remaining(at: now())
        completionTask?.cancel()
        state.phase = .paused(remaining: remaining)
        publish()
    }

    func resume() {
        guard case let .paused(remaining) = state.phase else { return }
        state.phase = .running(endsAt: now().addingTimeInterval(remaining))
        publish()
        scheduleCompletion()
    }

    func reset() {
        completionTask?.cancel()
        state.phase = .idle
        publish()
    }

    func setDuration(_ duration: TimeInterval) {
        let clamped = min(max(duration, PomodoroState.durationRange.lowerBound), PomodoroState.durationRange.upperBound)
        completionTask?.cancel()
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
        let delay = max(0, endsAt.timeIntervalSince(now()))
        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.revalidateDeadline()
        }
    }

    private func finish() {
        completionTask?.cancel()
        state.phase = .finished
        publish()
        NSSound(named: NSSound.Name("Glass"))?.play()
        onCompleted?()
    }
}
