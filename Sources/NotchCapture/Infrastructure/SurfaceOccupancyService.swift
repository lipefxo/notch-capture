import AppKit
import CoreGraphics

private final class SurfaceOccupancyObservationLifetime: @unchecked Sendable {
    let workspace: NSWorkspace
    var notificationTokens: [NSObjectProtocol] = []
    var refreshTimer: Timer?
    private var isStopped = false

    @MainActor
    init(workspace: NSWorkspace) {
        self.workspace = workspace
    }

    @MainActor
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        refreshTimer?.invalidate()
        refreshTimer = nil
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            workspace.notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()
    }
}

public struct SurfaceOccupancySnapshot: Equatable, Sendable {
    public let occupiedDisplayIDs: Set<CGDirectDisplayID>
    public let detectedBundleIdentifiers: Set<String>
    public let usesConservativeFallback: Bool

    public init(
        occupiedDisplayIDs: Set<CGDirectDisplayID> = [],
        detectedBundleIdentifiers: Set<String> = [],
        usesConservativeFallback: Bool = false
    ) {
        self.occupiedDisplayIDs = occupiedDisplayIDs
        self.detectedBundleIdentifiers = detectedBundleIdentifiers
        self.usesConservativeFallback = usesConservativeFallback
    }

    public var hasKnownUtilityRunning: Bool {
        !detectedBundleIdentifiers.isEmpty
    }

    public func isOccupied(displayID: CGDirectDisplayID) -> Bool {
        usesConservativeFallback || occupiedDisplayIDs.contains(displayID)
    }
}

@MainActor
public protocol SurfaceOccupancyProviding: AnyObject {
    var snapshot: SurfaceOccupancySnapshot { get }
    var onChange: (@MainActor (SurfaceOccupancySnapshot) -> Void)? { get set }
    func refresh()
}

/// Observes known notch utilities through documented process notifications and
/// public Core Graphics window metadata. It never sends events to, hides, moves,
/// terminates, or otherwise manipulates another application.
@MainActor
public final class SurfaceOccupancyService: SurfaceOccupancyProviding {
    public typealias WindowInfoProvider = @Sendable () -> [[String: Any]]

    public nonisolated static let notchFlowBundleIdentifier = "com.benshih.notchFlow"

    public private(set) var snapshot = SurfaceOccupancySnapshot()
    public var onChange: (@MainActor (SurfaceOccupancySnapshot) -> Void)?

    private let workspace: NSWorkspace
    private let knownBundleIdentifiers: Set<String>
    private let windowInfoProvider: WindowInfoProvider
    private let observationLifetime: SurfaceOccupancyObservationLifetime

    public init(
        workspace: NSWorkspace = .shared,
        knownBundleIdentifiers: Set<String> = [SurfaceOccupancyService.notchFlowBundleIdentifier],
        refreshInterval: TimeInterval = 1.5,
        windowInfoProvider: @escaping WindowInfoProvider = SurfaceOccupancyService.currentWindowInfo
    ) {
        self.workspace = workspace
        self.knownBundleIdentifiers = knownBundleIdentifiers
        self.windowInfoProvider = windowInfoProvider
        self.observationLifetime = SurfaceOccupancyObservationLifetime(workspace: workspace)
        installObservers()
        if refreshInterval > 0 {
            observationLifetime.refreshTimer = Timer.scheduledTimer(
                withTimeInterval: refreshInterval,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        refresh()
    }

    deinit {
        let observationLifetime = observationLifetime
        Task { @MainActor in
            observationLifetime.stop()
        }
    }

    /// Stops polling and unregisters notifications. App coordinators should call
    /// this during an orderly shutdown; deinitialization also schedules cleanup.
    public func stop() {
        observationLifetime.stop()
    }

    public func refresh() {
        let runningUtilities = workspace.runningApplications.filter {
            guard let bundleIdentifier = $0.bundleIdentifier else { return false }
            return knownBundleIdentifiers.contains(bundleIdentifier)
        }
        let detectedBundleIdentifiers = Set(runningUtilities.compactMap(\.bundleIdentifier))
        guard !runningUtilities.isEmpty else {
            publish(SurfaceOccupancySnapshot())
            return
        }

        let processIDs = Set(runningUtilities.map(\.processIdentifier))
        let displayBounds = onlineDisplayBounds()
        var occupiedDisplayIDs: Set<CGDirectDisplayID> = []
        var foundUsableWindow = false

        for info in windowInfoProvider() {
            guard
                let ownerPID = number(in: info, key: kCGWindowOwnerPID as String)?.int32Value,
                processIDs.contains(ownerPID),
                let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                let windowBounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                windowBounds.width > 1,
                windowBounds.height > 1
            else { continue }

            let alpha = number(in: info, key: kCGWindowAlpha as String)?.doubleValue ?? 1
            guard alpha > 0 else { continue }

            foundUsableWindow = true
            for (displayID, bounds) in displayBounds {
                let topInteractionBand = CGRect(
                    x: bounds.minX,
                    y: bounds.minY,
                    width: bounds.width,
                    height: min(180, bounds.height)
                )
                if windowBounds.intersects(topInteractionBand) {
                    occupiedDisplayIDs.insert(displayID)
                }
            }
        }

        let cannotMapOccupancy = !foundUsableWindow || occupiedDisplayIDs.isEmpty
        publish(SurfaceOccupancySnapshot(
            occupiedDisplayIDs: occupiedDisplayIDs,
            detectedBundleIdentifiers: detectedBundleIdentifiers,
            usesConservativeFallback: cannotMapOccupancy
        ))
    }

    nonisolated public static func currentWindowInfo() -> [[String: Any]] {
        guard let rawInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return rawInfo
    }

    private func publish(_ newSnapshot: SurfaceOccupancySnapshot) {
        guard newSnapshot != snapshot else { return }
        snapshot = newSnapshot
        onChange?(newSnapshot)
    }

    private func installObservers() {
        let workspaceEvents: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in workspaceEvents {
            observationLifetime.notificationTokens.append(
                workspace.notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                }
            )
        }

        observationLifetime.notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        )
    }

    private func onlineDisplayBounds() -> [CGDirectDisplayID: CGRect] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [:] }

        var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetOnlineDisplayList(count, &displayIDs, &count) == .success else { return [:] }

        return Dictionary(uniqueKeysWithValues: displayIDs.prefix(Int(count)).map {
            ($0, CGDisplayBounds($0))
        })
    }

    private func number(in info: [String: Any], key: String) -> NSNumber? {
        info[key] as? NSNumber
    }
}
