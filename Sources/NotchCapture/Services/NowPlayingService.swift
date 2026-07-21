import AppKit
import Foundation

private final class NowPlayingObservationLifetime: @unchecked Sendable {
    var distributedTokens: [NSObjectProtocol] = []
    var workspaceTokens: [NSObjectProtocol] = []
    var pollTimer: Timer?

    @MainActor
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        distributedTokens.forEach(DistributedNotificationCenter.default().removeObserver)
        workspaceTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        distributedTokens.removeAll()
        workspaceTokens.removeAll()
    }
}

@MainActor
final class NowPlayingService {
    enum ActivityLevel: Sendable, Equatable {
        case hidden
        case compact
        case full

        var pollInterval: TimeInterval? {
            switch self {
            case .hidden: nil
            case .compact: 15
            case .full: 5
            }
        }
    }

    var onSnapshotChange: (@MainActor (NowPlayingSnapshot?) -> Void)?
    var onPresentationChange: (@MainActor (NowPlayingPresentation?) -> Void)?
    var onSourceStatusChange: (@MainActor (NowPlayingSource, NowPlayingConnectionState) -> Void)?
    var onArtworkChange: (@MainActor (String, NSImage?) -> Void)?

    private(set) var snapshot: NowPlayingSnapshot?
    private(set) var presentation: NowPlayingPresentation?
    private let runner: any AppleScriptRunning
    private let artworkLoader: ArtworkLoader
    private let workspace: NSWorkspace
    private let sourceIsRunning: @MainActor (NowPlayingSource) -> Bool
    private let lifetime = NowPlayingObservationLifetime()
    private var activityLevel: ActivityLevel = .hidden
    private var connectionStates: [NowPlayingSource: NowPlayingConnectionState] = [:]
    private var lastSuccessfulSnapshots: [NowPlayingSource: NowPlayingSnapshot] = [:]
    private var lastActivity: [NowPlayingSource: Date] = [:]
    private var refreshTask: Task<Void, Never>?
    private var refreshPending = false
    private var refreshGeneration = 0
    private var isStopped = false
    /// Track key for which artwork was last successfully delivered.
    /// Kept separately from `snapshot` so a cancelled refresh that already
    /// published metadata still retries artwork on the next pass.
    private var artworkLoadedForTrackKey: String?

    init(
        runner: any AppleScriptRunning = AppleScriptRunner(),
        workspace: NSWorkspace = .shared,
        sourceIsRunning: @escaping @MainActor (NowPlayingSource) -> Bool = { source in
            !NSRunningApplication.runningApplications(withBundleIdentifier: source.rawValue).isEmpty
        }
    ) {
        self.runner = runner
        self.artworkLoader = ArtworkLoader(runner: runner)
        self.workspace = workspace
        self.sourceIsRunning = sourceIsRunning
        installObservers()
    }

    deinit {
        refreshTask?.cancel()
        let lifetime = lifetime
        Task { @MainActor in lifetime.stop() }
    }

    func stop() {
        isStopped = true
        refreshGeneration += 1
        refreshPending = false
        refreshTask?.cancel()
        lifetime.stop()
    }

    func setActivityLevel(_ level: ActivityLevel) {
        guard !isStopped, level != activityLevel else { return }
        activityLevel = level
        lifetime.pollTimer?.invalidate()
        lifetime.pollTimer = nil
        if let interval = level.pollInterval {
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            timer.tolerance = min(1, interval * 0.1)
            lifetime.pollTimer = timer
            refresh()
        } else {
            refreshGeneration += 1
            refreshPending = false
            refreshTask?.cancel()
        }
    }

    func connectionState(for source: NowPlayingSource) -> NowPlayingConnectionState {
        connectionStates[source] ?? .notRunning
    }

    func refresh(triggeredBy source: NowPlayingSource? = nil) {
        if let source { lastActivity[source] = .now }
        guard !isStopped, activityLevel != .hidden else { return }
        guard refreshTask == nil else {
            refreshPending = true
            return
        }
        startRefresh()
    }

    /// Clears an explicit Automation denial and joins the existing single-flight
    /// refresh. This is intentionally the only path that retries a denied app.
    func reconnect(_ source: NowPlayingSource) {
        guard runner.hostExecutableIsCurrent else {
            transitionToRecovery(
                .restartRequired,
                source: source,
                snapshot: lastSuccessfulSnapshots[source] ?? snapshotForSource(source)
            )
            return
        }
        setConnectionState(.connecting, for: source)
        refresh(triggeredBy: source)
    }

    private func startRefresh() {
        let generation = refreshGeneration
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await performRefresh(generation: generation)
            finishRefresh()
        }
    }

    private func finishRefresh() {
        refreshTask = nil
        guard !isStopped, activityLevel != .hidden, refreshPending else { return }
        refreshPending = false
        startRefresh()
    }

    func playPause() { runCommand("playpause", optimisticallyTogglingPlayback: true) }
    func nextTrack() { runCommand("next track") }
    func previousTrack() { runCommand("previous track") }

    func seek(to position: TimeInterval) {
        guard let current = snapshot, presentation?.isRecovery != true else { return }
        let optimistic = current.seeking(to: position, at: .now)
        publish(NowPlayingPresentation(source: current.source, state: .connected, snapshot: optimistic))

        let value = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            optimistic.position
        )
        runCommand("set player position to \(value)")
    }

    nonisolated static func parseStatus(
        _ value: String,
        source: NowPlayingSource,
        at date: Date = .now
    ) -> NowPlayingSnapshot? {
        let fields = value.components(separatedBy: "\u{1F}")
        guard fields.count >= 8 else { return nil }
        let rawDuration = parseNumber(fields[4]) ?? 0
        let duration = source == .spotify ? rawDuration / 1000 : rawDuration
        let position = parseNumber(fields[5]) ?? 0
        let state = fields[6].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard state != "stopped", !fields[1].isEmpty else { return nil }
        return NowPlayingSnapshot(
            source: source,
            trackKey: fields[0].isEmpty ? "\(fields[1])|\(fields[2])|\(fields[3])" : fields[0],
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            duration: max(0, duration),
            isPlaying: state == "playing",
            position: max(0, position),
            positionAnchor: date,
            artworkURL: fields[7].isEmpty ? nil : URL(string: fields[7])
        )
    }

    nonisolated static func parseNumber(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = TimeInterval(trimmed) { return number }
        guard trimmed.contains(","), !trimmed.contains(".") else { return nil }
        return TimeInterval(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    nonisolated static func chooseActive(
        _ candidates: [NowPlayingSnapshot],
        currentSource: NowPlayingSource?,
        lastActivity: [NowPlayingSource: Date]
    ) -> NowPlayingSnapshot? {
        guard candidates.count > 1 else { return candidates.first }
        let playing = candidates.filter(\.isPlaying)
        if playing.count == 1 { return playing[0] }
        let pool = playing.isEmpty ? candidates : playing
        if let currentSource, let sticky = pool.first(where: { $0.source == currentSource }) {
            let newest = pool.max { (lastActivity[$0.source] ?? .distantPast) < (lastActivity[$1.source] ?? .distantPast) }
            if let newest, (lastActivity[newest.source] ?? .distantPast) > (lastActivity[currentSource] ?? .distantPast) {
                return newest
            }
            return sticky
        }
        return pool.max { (lastActivity[$0.source] ?? .distantPast) < (lastActivity[$1.source] ?? .distantPast) }
            ?? pool.first
    }

    /// Artwork must load whenever we have not yet successfully delivered art for
    /// this track — including after a cancelled first-launch refresh that already
    /// published the same metadata.
    nonisolated static func needsArtworkLoad(
        trackKey: String,
        artworkLoadedForTrackKey: String?
    ) -> Bool {
        trackKey != artworkLoadedForTrackKey
    }

    nonisolated static func shouldPublish(
        previous: NowPlayingSnapshot?,
        candidate: NowPlayingSnapshot?,
        driftThreshold: TimeInterval = 1.5
    ) -> Bool {
        guard let previous, let candidate else {
            return previous != nil || candidate != nil
        }
        guard previous.source == candidate.source,
              previous.trackKey == candidate.trackKey,
              previous.title == candidate.title,
              previous.artist == candidate.artist,
              previous.album == candidate.album,
              previous.duration == candidate.duration,
              previous.isPlaying == candidate.isPlaying,
              previous.artworkURL == candidate.artworkURL else {
            return true
        }
        let expectedPosition = previous.position(at: candidate.positionAnchor)
        return abs(candidate.position - expectedPosition) > driftThreshold
    }

    private func performRefresh(generation: Int) async {
        var candidates: [NowPlayingSnapshot] = []
        for source in NowPlayingSource.allCases {
            guard isRunning(source) else {
                lastSuccessfulSnapshots.removeValue(forKey: source)
                setConnectionState(.notRunning, for: source)
                continue
            }
            guard connectionState(for: source) != .permissionDenied else { continue }
            setConnectionState(.connecting, for: source)
            do {
                let result = try await runner.run(Self.statusScript(for: source))
                guard refreshIsCurrent(generation) else { return }
                guard case let .string(value) = result,
                      let parsed = Self.parseStatus(value, source: source) else {
                    lastSuccessfulSnapshots.removeValue(forKey: source)
                    setConnectionState(.idle, for: source)
                    continue
                }
                lastSuccessfulSnapshots[source] = parsed
                setConnectionState(.connected, for: source)
                candidates.append(parsed)
            } catch AppleScriptRunnerError.automationDenied {
                guard refreshIsCurrent(generation) else { return }
                setConnectionState(.permissionDenied, for: source)
            } catch AppleScriptRunnerError.hostApplicationInvalidated {
                guard refreshIsCurrent(generation) else { return }
                transitionToRecovery(
                    .restartRequired,
                    source: source,
                    snapshot: lastSuccessfulSnapshots[source] ?? snapshotForSource(source)
                )
            } catch AppleScriptRunnerError.applicationNotRunning {
                guard refreshIsCurrent(generation) else { return }
                lastSuccessfulSnapshots.removeValue(forKey: source)
                setConnectionState(.notRunning, for: source)
            } catch {
                guard refreshIsCurrent(generation) else { return }
                setConnectionState(.disconnected, for: source)
            }
        }

        let selected = Self.chooseActive(
            candidates,
            currentSource: presentation?.source,
            lastActivity: lastActivity
        )
        guard refreshIsCurrent(generation) else { return }
        let previous = snapshot
        let oldTrackKey = previous?.trackKey
        let nextPresentation: NowPlayingPresentation?
        if let selected {
            nextPresentation = NowPlayingPresentation(source: selected.source, state: .connected, snapshot: selected)
        } else {
            nextPresentation = recoveryPresentation()
        }
        publish(nextPresentation)

        guard let selected, nextPresentation?.isRecovery != true else {
            if oldTrackKey != nil {
                artworkLoadedForTrackKey = nil
                onArtworkChange?(oldTrackKey ?? "", nil)
            }
            return
        }

        // A refresh can publish metadata and then be invalidated while artwork
        // is loading. The next pass must retry instead of treating the matching
        // track key as proof that artwork was already delivered.
        guard Self.needsArtworkLoad(
            trackKey: selected.trackKey,
            artworkLoadedForTrackKey: artworkLoadedForTrackKey
        ) else { return }

        let artwork = await artworkLoader.artwork(for: selected)
        guard refreshIsCurrent(generation) else { return }
        guard snapshot?.trackKey == selected.trackKey, presentation?.isRecovery != true else { return }
        artworkLoadedForTrackKey = selected.trackKey
        onArtworkChange?(selected.trackKey, artwork)
    }

    private func refreshIsCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled
            && !isStopped
            && activityLevel != .hidden
            && refreshGeneration == generation
    }

    private func runCommand(_ command: String, optimisticallyTogglingPlayback: Bool = false) {
        guard let source = snapshot?.source,
              presentation?.isRecovery != true,
              isRunning(source),
              connectionState(for: source) != .permissionDenied else { return }
        let confirmedSnapshot = lastSuccessfulSnapshots[source] ?? snapshot
        if optimisticallyTogglingPlayback, var optimistic = snapshot {
            optimistic.position = optimistic.position(at: .now)
            optimistic.positionAnchor = .now
            optimistic.isPlaying.toggle()
            publish(NowPlayingPresentation(source: source, state: .connected, snapshot: optimistic))
        }
        lastActivity[source] = .now
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await runner.run("tell application \"\(source.applicationName)\" to \(command)")
            } catch AppleScriptRunnerError.automationDenied {
                transitionToRecovery(.permissionDenied, source: source, snapshot: confirmedSnapshot)
            } catch AppleScriptRunnerError.hostApplicationInvalidated {
                transitionToRecovery(.restartRequired, source: source, snapshot: confirmedSnapshot)
            } catch AppleScriptRunnerError.applicationNotRunning {
                lastSuccessfulSnapshots.removeValue(forKey: source)
                setConnectionState(.notRunning, for: source)
                publish(recoveryPresentation())
            } catch {
                transitionToRecovery(.disconnected, source: source, snapshot: confirmedSnapshot)
            }
            refresh(triggeredBy: source)
        }
    }

    private func setConnectionState(_ state: NowPlayingConnectionState, for source: NowPlayingSource) {
        guard connectionStates[source] != state else { return }
        connectionStates[source] = state
        onSourceStatusChange?(source, state)
    }

    private func transitionToRecovery(
        _ state: NowPlayingConnectionState,
        source: NowPlayingSource,
        snapshot: NowPlayingSnapshot?
    ) {
        if let snapshot { lastSuccessfulSnapshots[source] = snapshot.frozen() }
        setConnectionState(state, for: source)
        publish(recoveryPresentation(preferredSource: source))
    }

    private func snapshotForSource(_ source: NowPlayingSource) -> NowPlayingSnapshot? {
        guard snapshot?.source == source else { return nil }
        return snapshot
    }

    private func recoveryPresentation(preferredSource: NowPlayingSource? = nil) -> NowPlayingPresentation? {
        let recoverable = NowPlayingSource.allCases.compactMap { source -> NowPlayingPresentation? in
            let state = connectionState(for: source)
            guard state.isRecoverable, let snapshot = lastSuccessfulSnapshots[source] else { return nil }
            return NowPlayingPresentation(source: source, state: state, snapshot: snapshot.frozen())
        }
        if let preferredSource, let preferred = recoverable.first(where: { $0.source == preferredSource }) {
            return preferred
        }
        if let current = presentation,
           let sticky = recoverable.first(where: { $0.source == current.source }) {
            return sticky
        }
        return recoverable.max {
            (lastActivity[$0.source] ?? .distantPast) < (lastActivity[$1.source] ?? .distantPast)
        }
    }

    private func publish(_ next: NowPlayingPresentation?) {
        let previous = presentation
        presentation = next
        snapshot = next?.snapshot
        guard previous != next else { return }
        onPresentationChange?(next)
        onSnapshotChange?(next?.snapshot)
    }

    private func isRunning(_ source: NowPlayingSource) -> Bool {
        sourceIsRunning(source)
    }

    private func installObservers() {
        let center = DistributedNotificationCenter.default()
        let names: [(Notification.Name, NowPlayingSource)] = [
            (Notification.Name("com.spotify.client.PlaybackStateChanged"), .spotify),
            (Notification.Name("com.apple.Music.playerInfo"), .appleMusic),
            (Notification.Name("com.apple.iTunes.playerInfo"), .appleMusic),
        ]
        for (name, source) in names {
            lifetime.distributedTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let playbackState = notification.userInfo?["Player State"] as? String
                Task { @MainActor in
                    if source == .spotify, playbackState?.lowercased() == "stopped" {
                        self?.refresh()
                    } else {
                        self?.refresh(triggeredBy: source)
                    }
                }
            })
        }
        lifetime.workspaceTokens.append(workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundleIdentifier = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard let bundleIdentifier, let source = NowPlayingSource(rawValue: bundleIdentifier) else { return }
            Task { @MainActor in self?.refresh(triggeredBy: source) }
        })
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            lifetime.workspaceTokens.append(workspace.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let bundleIdentifier = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                guard let bundleIdentifier, let source = NowPlayingSource(rawValue: bundleIdentifier) else { return }
                Task { @MainActor in self?.refresh(triggeredBy: source) }
            })
        }
        lifetime.workspaceTokens.append(workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
    }

    private nonisolated static func statusScript(for source: NowPlayingSource) -> String {
        let app = source.applicationName
        if source == .spotify {
            return """
            tell application \"\(app)\"
                set s to ASCII character 31
                if player state is stopped then return \"\"
                set t to current track
                set trackDuration to duration of t as integer
                set trackPosition to player position as integer
                return (id of t as text) & s & (name of t as text) & s & (artist of t as text) & s & (album of t as text) & s & (trackDuration as text) & s & (trackPosition as text) & s & (player state as text) & s & (artwork url of t as text)
            end tell
            """
        }
        return """
        tell application \"\(app)\"
            set s to ASCII character 31
            if player state is stopped then return \"\"
            set t to current track
            try
                set trackID to persistent ID of t as text
            on error
                set trackID to database ID of t as text
            end try
            set trackDuration to duration of t as integer
            set trackPosition to player position as integer
            return trackID & s & (name of t as text) & s & (artist of t as text) & s & (album of t as text) & s & (trackDuration as text) & s & (trackPosition as text) & s & (player state as text) & s & \"\"
        end tell
        """
    }
}
