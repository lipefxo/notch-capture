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
    enum ActivityLevel: Sendable {
        case hidden
        case compact
        case full

        var pollInterval: TimeInterval? {
            switch self {
            case .hidden: nil
            case .compact: 5
            case .full: 1
            }
        }
    }

    var onSnapshotChange: (@MainActor (NowPlayingSnapshot?) -> Void)?
    var onArtworkChange: (@MainActor (String, NSImage?) -> Void)?
    var onAutomationDenied: (@MainActor (NowPlayingSource) -> Void)?

    private(set) var snapshot: NowPlayingSnapshot?
    private let runner: AppleScriptRunner
    private let artworkLoader: ArtworkLoader
    private let workspace: NSWorkspace
    private let lifetime = NowPlayingObservationLifetime()
    private var activityLevel: ActivityLevel = .hidden
    private var deniedSources: Set<NowPlayingSource> = []
    private var lastActivity: [NowPlayingSource: Date] = [:]
    private var refreshTask: Task<Void, Never>?

    init(
        runner: AppleScriptRunner = AppleScriptRunner(),
        workspace: NSWorkspace = .shared
    ) {
        self.runner = runner
        self.artworkLoader = ArtworkLoader(runner: runner)
        self.workspace = workspace
        installObservers()
    }

    deinit {
        refreshTask?.cancel()
        let lifetime = lifetime
        Task { @MainActor in lifetime.stop() }
    }

    func stop() {
        refreshTask?.cancel()
        lifetime.stop()
    }

    func setActivityLevel(_ level: ActivityLevel) {
        activityLevel = level
        lifetime.pollTimer?.invalidate()
        lifetime.pollTimer = nil
        if let interval = level.pollInterval {
            lifetime.pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            refresh()
        }
    }

    func refresh(triggeredBy source: NowPlayingSource? = nil) {
        if let source { lastActivity[source] = .now }
        guard activityLevel != .hidden else { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            await self?.performRefresh()
        }
    }

    func playPause() { runCommand("playpause", optimisticallyTogglingPlayback: true) }
    func nextTrack() { runCommand("next track") }
    func previousTrack() { runCommand("previous track") }

    func seek(to position: TimeInterval) {
        guard let current = snapshot else { return }
        let optimistic = current.seeking(to: position, at: .now)
        snapshot = optimistic
        onSnapshotChange?(optimistic)

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

    private func performRefresh() async {
        var candidates: [NowPlayingSnapshot] = []
        for source in NowPlayingSource.allCases where isRunning(source) && !deniedSources.contains(source) {
            do {
                let result = try await runner.run(Self.statusScript(for: source))
                guard case let .string(value) = result,
                      let parsed = Self.parseStatus(value, source: source) else { continue }
                candidates.append(parsed)
            } catch AppleScriptRunnerError.automationDenied {
                deniedSources.insert(source)
                onAutomationDenied?(source)
            } catch {
                continue
            }
            guard !Task.isCancelled else { return }
        }

        let selected = Self.chooseActive(
            candidates,
            currentSource: snapshot?.source,
            lastActivity: lastActivity
        )
        guard !Task.isCancelled else { return }
        let oldTrackKey = snapshot?.trackKey
        snapshot = selected
        onSnapshotChange?(selected)
        guard let selected, selected.trackKey != oldTrackKey else {
            if selected == nil { onArtworkChange?(oldTrackKey ?? "", nil) }
            return
        }
        let artwork = await artworkLoader.artwork(for: selected)
        guard snapshot?.trackKey == selected.trackKey else { return }
        onArtworkChange?(selected.trackKey, artwork)
    }

    private func runCommand(_ command: String, optimisticallyTogglingPlayback: Bool = false) {
        guard let source = snapshot?.source, isRunning(source), !deniedSources.contains(source) else { return }
        if optimisticallyTogglingPlayback, var optimistic = snapshot {
            optimistic.position = optimistic.position(at: .now)
            optimistic.positionAnchor = .now
            optimistic.isPlaying.toggle()
            snapshot = optimistic
            onSnapshotChange?(optimistic)
        }
        lastActivity[source] = .now
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await runner.run("tell application \"\(source.applicationName)\" to \(command)")
            } catch AppleScriptRunnerError.automationDenied {
                deniedSources.insert(source)
                onAutomationDenied?(source)
            } catch { }
            refresh(triggeredBy: source)
        }
    }

    private func isRunning(_ source: NowPlayingSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.rawValue).isEmpty
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
