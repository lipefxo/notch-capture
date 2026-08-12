import AppKit
import CoreGraphics
import Darwin

/// Permission-free Window Server fields used by fullscreen classification.
struct WindowServerSnapshot: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let layer: Int
    let bounds: CGRect
    let alpha: Double
    let isOnscreen: Bool
}

struct DisplayBoundsSnapshot: Equatable {
    let displayID: CGDirectDisplayID
    let bounds: CGRect
    /// AppKit's visible frame converted into the Window Server coordinate
    /// system. A maximized window settles here rather than at `bounds`.
    let visibleBounds: CGRect
}

struct FullScreenApplicationIdentity: Equatable {
    let processID: pid_t
    let bundleIdentifier: String?
    let name: String
}

struct FullScreenForegroundWindow: Equatable {
    let windowID: CGWindowID
    let bounds: CGRect
}

struct FullScreenWindowObservation: Equatable {
    let application: FullScreenApplicationIdentity
    let coveredDisplayIDs: Set<CGDirectDisplayID>
    /// Displays whose working area (below the menu bar) is filled by an
    /// eligible window. A maximized/zoomed window settles here without ever
    /// covering the menu-bar region, so it is a persistent signal distinct
    /// from the covering-window full-screen detection above.
    let maximizedDisplayIDs: Set<CGDirectDisplayID>
    let foregroundWindowsByDisplay: [CGDirectDisplayID: FullScreenForegroundWindow]
    let displaysByID: [CGDirectDisplayID: DisplayBoundsSnapshot]

    init(
        application: FullScreenApplicationIdentity,
        coveredDisplayIDs: Set<CGDirectDisplayID>,
        maximizedDisplayIDs: Set<CGDirectDisplayID> = [],
        foregroundWindowsByDisplay: [CGDirectDisplayID: FullScreenForegroundWindow],
        displaysByID: [CGDirectDisplayID: DisplayBoundsSnapshot]
    ) {
        self.application = application
        self.coveredDisplayIDs = coveredDisplayIDs
        self.maximizedDisplayIDs = maximizedDisplayIDs
        self.foregroundWindowsByDisplay = foregroundWindowsByDisplay
        self.displaysByID = displaysByID
    }
}

enum FullScreenDisplayDetector {
    /// Window Server bounds occasionally differ from display bounds by a
    /// backing-pixel rounding error. Anything larger than this is meaningful
    /// chrome (for example, the menu bar above a maximized window).
    static let coverageTolerance: CGFloat = 2
    static let foregroundIntersectionThreshold = 0.15

    static func observe(
        windows: [WindowServerSnapshot],
        displays: [DisplayBoundsSnapshot],
        application: FullScreenApplicationIdentity,
        eligibleOwnerPIDs: Set<pid_t>,
        tolerance: CGFloat = coverageTolerance
    ) -> FullScreenWindowObservation {
        let eligibleWindows = windows.filter {
            eligibleOwnerPIDs.contains($0.ownerPID)
                && $0.layer >= 0
                && $0.isOnscreen
                && $0.alpha > 0.01
                && !$0.bounds.isEmpty
        }

        var coveredDisplayIDs: Set<CGDirectDisplayID> = []
        var maximizedDisplayIDs: Set<CGDirectDisplayID> = []
        var foregroundWindowsByDisplay: [CGDirectDisplayID: FullScreenForegroundWindow] = [:]

        for display in displays {
            if eligibleWindows.contains(where: {
                covers($0.bounds, displayBounds: display.bounds, tolerance: tolerance)
            }) {
                coveredDisplayIDs.insert(display.displayID)
            }

            // A window filling the working area below the menu bar is a
            // maximize/zoom. It persists in the public window list, so a
            // direct per-frame check (no session tracking) both catches it and
            // self-corrects when the window is restored.
            if eligibleWindows.contains(where: {
                $0.layer == 0
                    && covers($0.bounds, displayBounds: display.visibleBounds, tolerance: tolerance)
            }) {
                maximizedDisplayIDs.insert(display.displayID)
            }

            // CGWindowList is front-to-back. Ignore tiny layer-zero utility
            // strips so browser tab/menu helper windows do not replace the
            // actual foreground application window used by pulse tracking.
            if let foreground = eligibleWindows.first(where: {
                $0.layer == 0
                    && intersectionRatio($0.bounds, within: display.bounds)
                        >= foregroundIntersectionThreshold
            }) {
                foregroundWindowsByDisplay[display.displayID] = FullScreenForegroundWindow(
                    windowID: foreground.windowID,
                    bounds: foreground.bounds
                )
            }
        }

        return FullScreenWindowObservation(
            application: application,
            coveredDisplayIDs: coveredDisplayIDs,
            maximizedDisplayIDs: maximizedDisplayIDs,
            foregroundWindowsByDisplay: foregroundWindowsByDisplay,
            displaysByID: Dictionary(uniqueKeysWithValues: displays.map { ($0.displayID, $0) })
        )
    }

    static func detect(
        windows: [WindowServerSnapshot],
        displays: [DisplayBoundsSnapshot],
        eligibleOwnerPIDs: Set<pid_t>,
        tolerance: CGFloat = coverageTolerance
    ) -> Set<CGDirectDisplayID> {
        observe(
            windows: windows,
            displays: displays,
            application: FullScreenApplicationIdentity(
                processID: eligibleOwnerPIDs.first ?? 0,
                bundleIdentifier: nil,
                name: "Test"
            ),
            eligibleOwnerPIDs: eligibleOwnerPIDs,
            tolerance: tolerance
        ).coveredDisplayIDs
    }

    /// Returns nil when the Window Server cannot provide a snapshot. Callers
    /// retain their current session in that case instead of fabricating an
    /// exit during a transient Window Server failure.
    static func observe(
        displays: [DisplayBoundsSnapshot],
        frontmostApplication: NSRunningApplication,
        excludingOwnerPIDs: Set<pid_t> = []
    ) -> FullScreenWindowObservation? {
        let application = FullScreenApplicationIdentity(
            processID: frontmostApplication.processIdentifier,
            bundleIdentifier: frontmostApplication.bundleIdentifier,
            name: frontmostApplication.localizedName ?? "-"
        )

        // Dock, WindowManager, and similar agents can become transiently
        // frontmost while presenting app-switching UI. They receive an empty
        // observation and therefore cannot initiate a fullscreen session.
        guard frontmostApplication.activationPolicy == .regular else {
            return FullScreenWindowObservation(
                application: application,
                coveredDisplayIDs: [],
                foregroundWindowsByDisplay: [:],
                displaysByID: Dictionary(uniqueKeysWithValues: displays.map { ($0.displayID, $0) })
            )
        }
        guard let dictionaries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let windows = dictionaries.compactMap(windowSnapshot(from:))
        let frontmostPID = frontmostApplication.processIdentifier
        let eligibleOwnerPIDs = Set(windows.lazy.map(\.ownerPID).filter {
            !excludingOwnerPIDs.contains($0)
                && isProcess($0, relatedTo: frontmostApplication, frontmostPID: frontmostPID)
        })
        return observe(
            windows: windows,
            displays: displays,
            application: application,
            eligibleOwnerPIDs: eligibleOwnerPIDs
        )
    }

    static func covers(
        _ windowBounds: CGRect,
        displayBounds: CGRect,
        tolerance: CGFloat = coverageTolerance
    ) -> Bool {
        windowBounds.minX <= displayBounds.minX + tolerance
            && windowBounds.minY <= displayBounds.minY + tolerance
            && windowBounds.maxX >= displayBounds.maxX - tolerance
            && windowBounds.maxY >= displayBounds.maxY - tolerance
    }

    private static func intersectionRatio(_ windowBounds: CGRect, within displayBounds: CGRect) -> CGFloat {
        let displayArea = displayBounds.width * displayBounds.height
        guard displayArea > 0 else { return 0 }
        let intersection = windowBounds.intersection(displayBounds)
        guard !intersection.isNull else { return 0 }
        return (intersection.width * intersection.height) / displayArea
    }

    private static func windowSnapshot(from dictionary: [String: Any]) -> WindowServerSnapshot? {
        guard let windowID = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let ownerPID = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue,
              let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
            return nil
        }

        return WindowServerSnapshot(
            windowID: windowID,
            ownerPID: ownerPID,
            layer: layer,
            bounds: bounds,
            alpha: (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            isOnscreen: (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
        )
    }

    private static func isProcess(
        _ candidatePID: pid_t,
        relatedTo frontmostApplication: NSRunningApplication,
        frontmostPID: pid_t
    ) -> Bool {
        guard candidatePID > 0 else { return false }
        if candidatePID == frontmostPID || isDescendant(candidatePID, of: frontmostPID) {
            return true
        }

        // Some browser helpers are launched through an intermediate service,
        // so ancestry is not always preserved. Their bundle identifiers still
        // remain in the owning application's namespace.
        guard let frontmostBundleID = frontmostApplication.bundleIdentifier,
              let candidateBundleID = NSRunningApplication(
                  processIdentifier: candidatePID
              )?.bundleIdentifier else {
            return false
        }
        return candidateBundleID == frontmostBundleID
            || candidateBundleID.hasPrefix(frontmostBundleID + ".")
    }

    private static func isDescendant(_ candidatePID: pid_t, of ancestorPID: pid_t) -> Bool {
        var currentPID = candidatePID
        var visited: Set<pid_t> = []

        for _ in 0..<16 {
            guard currentPID > 1,
                  currentPID != ancestorPID,
                  visited.insert(currentPID).inserted,
                  let parentPID = parentPID(of: currentPID) else {
                return currentPID == ancestorPID
            }
            currentPID = parentPID
        }
        return currentPID == ancestorPID
    }

    private static func parentPID(of processID: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let result = proc_pidinfo(
            processID,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.stride)
        )
        guard result == MemoryLayout<proc_bsdinfo>.stride else { return nil }
        return pid_t(info.pbi_ppid)
    }
}

struct FullScreenSessionObservation: Equatable {
    let window: FullScreenWindowObservation
    let timestamp: TimeInterval
    let activeSpaceGeneration: Int
    let displayEnvironmentGeneration: Int
}

struct FullScreenSessionTransition: Equatable {
    enum Kind: String {
        case entered
        case compositorLatched
        case nativeConfirmed
        case exitPulse
        case exited
        case maximizeRejected
        case contextReset
    }

    let kind: Kind
    let displayID: CGDirectDisplayID
    let application: FullScreenApplicationIdentity
    let sourceWindow: FullScreenForegroundWindow?
    let settledWindow: FullScreenForegroundWindow?

    var diagnosticDescription: String {
        func describe(_ window: FullScreenForegroundWindow?) -> String {
            guard let window else { return "-" }
            return "#\(window.windowID) \(NSStringFromRect(window.bounds))"
        }
        return "fullscreen session: \(kind.rawValue) display=\(displayID) "
            + "owner=\(application.name)[\(application.processID)] "
            + "source=\(describe(sourceWindow)) settled=\(describe(settledWindow))"
    }
}

struct FullScreenSessionUpdate: Equatable {
    let fullScreenDisplayIDs: Set<CGDirectDisplayID>
    let stableStateChanged: Bool
    let transitions: [FullScreenSessionTransition]
}

/// Tracks compositor-hosted browser fullscreen as a session. Chromium exposes
/// a covering Window Server window only during its enter/exit animations; the
/// actual fullscreen surface is rendered outside the public window list.
struct FullScreenSessionTracker {
    static let compositorPulseMaximumDuration: TimeInterval = 1
    static let geometryTolerance: CGFloat = 6

    private enum Phase: Equatable {
        case entering(coverageStartedAt: TimeInterval)
        case compositor(latchedAt: TimeInterval)
        case exiting
        case continuous
    }

    private struct Session: Equatable {
        let application: FullScreenApplicationIdentity
        var phase: Phase
        let sourceWindow: FullScreenForegroundWindow?
    }

    private var sessionsByDisplay: [CGDirectDisplayID: Session] = [:]
    private var lastForegroundWindows: [CGDirectDisplayID: FullScreenForegroundWindow] = [:]
    private var lastApplication: FullScreenApplicationIdentity?
    private var activeSpaceGeneration: Int?
    private var displayEnvironmentGeneration: Int?

    private(set) var fullScreenDisplayIDs: Set<CGDirectDisplayID> = []

    mutating func update(_ observation: FullScreenSessionObservation) -> FullScreenSessionUpdate {
        let previousDisplayIDs = fullScreenDisplayIDs
        let window = observation.window
        var transitions: [FullScreenSessionTransition] = []

        let activeSpaceChanged = activeSpaceGeneration.map {
            $0 != observation.activeSpaceGeneration
        } ?? false
        let displayEnvironmentChanged = displayEnvironmentGeneration.map {
            $0 != observation.displayEnvironmentGeneration
        } ?? false
        if displayEnvironmentChanged {
            for (displayID, session) in sessionsByDisplay {
                transitions.append(transition(
                    .contextReset,
                    displayID: displayID,
                    session: session,
                    settledWindow: window.foregroundWindowsByDisplay[displayID]
                ))
            }
            sessionsByDisplay.removeAll()
            lastForegroundWindows.removeAll()
        } else if activeSpaceChanged {
            // A native fullscreen Space change can arrive during either its
            // entering or exiting cover animation. Preserve same-owner
            // coverage as continuous; clear compositor sessions that have no
            // public window on the newly active Space.
            for (displayID, var session) in sessionsByDisplay {
                if session.application == window.application,
                   window.coveredDisplayIDs.contains(displayID) {
                    session.phase = .continuous
                    sessionsByDisplay[displayID] = session
                    transitions.append(transition(
                        .nativeConfirmed,
                        displayID: displayID,
                        session: session,
                        settledWindow: window.foregroundWindowsByDisplay[displayID]
                    ))
                } else {
                    sessionsByDisplay.removeValue(forKey: displayID)
                    transitions.append(transition(
                        .contextReset,
                        displayID: displayID,
                        session: session,
                        settledWindow: window.foregroundWindowsByDisplay[displayID]
                    ))
                }
            }
            lastForegroundWindows.removeAll()
        }
        activeSpaceGeneration = observation.activeSpaceGeneration
        displayEnvironmentGeneration = observation.displayEnvironmentGeneration

        if let lastApplication, lastApplication != window.application {
            for (displayID, session) in sessionsByDisplay {
                transitions.append(transition(
                    .contextReset,
                    displayID: displayID,
                    session: session,
                    settledWindow: window.foregroundWindowsByDisplay[displayID]
                ))
            }
            sessionsByDisplay.removeAll()
            lastForegroundWindows.removeAll()
        }
        lastApplication = window.application

        let displayIDs = Set(window.displaysByID.keys)
            .union(sessionsByDisplay.keys)
            .union(window.coveredDisplayIDs)
        for displayID in displayIDs {
            let isCovered = window.coveredDisplayIDs.contains(displayID)
            let settledWindow = window.foregroundWindowsByDisplay[displayID]

            guard var session = sessionsByDisplay[displayID] else {
                if isCovered {
                    let newSession = Session(
                        application: window.application,
                        phase: .entering(coverageStartedAt: observation.timestamp),
                        sourceWindow: lastForegroundWindows[displayID]
                    )
                    sessionsByDisplay[displayID] = newSession
                    transitions.append(transition(
                        .entered,
                        displayID: displayID,
                        session: newSession,
                        settledWindow: settledWindow
                    ))
                }
                continue
            }

            guard session.application == window.application else {
                sessionsByDisplay.removeValue(forKey: displayID)
                transitions.append(transition(
                    .contextReset,
                    displayID: displayID,
                    session: session,
                    settledWindow: settledWindow
                ))
                continue
            }

            switch session.phase {
            case let .entering(coverageStartedAt):
                if isCovered {
                    if observation.timestamp - coverageStartedAt
                        >= Self.compositorPulseMaximumDuration {
                        session.phase = .continuous
                        sessionsByDisplay[displayID] = session
                        transitions.append(transition(
                            .nativeConfirmed,
                            displayID: displayID,
                            session: session,
                            settledWindow: settledWindow
                        ))
                    }
                } else if observation.timestamp - coverageStartedAt
                            <= Self.compositorPulseMaximumDuration,
                          !settledAsMaximized(
                              source: session.sourceWindow,
                              settled: settledWindow,
                              display: window.displaysByID[displayID]
                          ) {
                    session.phase = .compositor(latchedAt: observation.timestamp)
                    sessionsByDisplay[displayID] = session
                    transitions.append(transition(
                        .compositorLatched,
                        displayID: displayID,
                        session: session,
                        settledWindow: settledWindow
                    ))
                } else {
                    sessionsByDisplay.removeValue(forKey: displayID)
                    transitions.append(transition(
                        settledAsMaximized(
                            source: session.sourceWindow,
                            settled: settledWindow,
                            display: window.displaysByID[displayID]
                        ) ? .maximizeRejected : .exited,
                        displayID: displayID,
                        session: session,
                        settledWindow: settledWindow
                    ))
                }

            case .compositor:
                if isCovered {
                    session.phase = .exiting
                    sessionsByDisplay[displayID] = session
                    transitions.append(transition(
                        .exitPulse,
                        displayID: displayID,
                        session: session,
                        settledWindow: settledWindow
                    ))
                }

            case .exiting:
                if !isCovered {
                    sessionsByDisplay.removeValue(forKey: displayID)
                    transitions.append(transition(
                        .exited,
                        displayID: displayID,
                        session: session,
                        settledWindow: settledWindow
                    ))
                }

            case .continuous:
                if !isCovered {
                    sessionsByDisplay.removeValue(forKey: displayID)
                    transitions.append(transition(
                        .exited,
                        displayID: displayID,
                        session: session,
                        settledWindow: settledWindow
                    ))
                }
            }
        }

        // Preserve the last non-covering application window so a transition
        // pulse can be distinguished from an ordinary maximize operation.
        for (displayID, foregroundWindow) in window.foregroundWindowsByDisplay
            where !window.coveredDisplayIDs.contains(displayID) {
            lastForegroundWindows[displayID] = foregroundWindow
        }
        lastForegroundWindows = lastForegroundWindows.filter {
            window.displaysByID[$0.key] != nil
        }

        fullScreenDisplayIDs = Set(sessionsByDisplay.keys)
        return FullScreenSessionUpdate(
            fullScreenDisplayIDs: fullScreenDisplayIDs,
            stableStateChanged: fullScreenDisplayIDs != previousDisplayIDs,
            transitions: transitions
        )
    }

    private func settledAsMaximized(
        source: FullScreenForegroundWindow?,
        settled: FullScreenForegroundWindow?,
        display: DisplayBoundsSnapshot?
    ) -> Bool {
        guard let source, let settled, let display,
              source.windowID == settled.windowID else { return false }
        return !approximatelyEqual(source.bounds, display.visibleBounds)
            && approximatelyEqual(settled.bounds, display.visibleBounds)
            && !approximatelyEqual(source.bounds, settled.bounds)
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= Self.geometryTolerance
            && abs(lhs.minY - rhs.minY) <= Self.geometryTolerance
            && abs(lhs.maxX - rhs.maxX) <= Self.geometryTolerance
            && abs(lhs.maxY - rhs.maxY) <= Self.geometryTolerance
    }

    private func transition(
        _ kind: FullScreenSessionTransition.Kind,
        displayID: CGDirectDisplayID,
        session: Session,
        settledWindow: FullScreenForegroundWindow?
    ) -> FullScreenSessionTransition {
        FullScreenSessionTransition(
            kind: kind,
            displayID: displayID,
            application: session.application,
            sourceWindow: session.sourceWindow,
            settledWindow: settledWindow
        )
    }
}

enum FullScreenCompactPresentationPolicy {
    static func shouldForceMinimal(
        targetDisplayID: CGDirectDisplayID?,
        fullScreenDisplayIDs: Set<CGDirectDisplayID>
    ) -> Bool {
        targetDisplayID.map(fullScreenDisplayIDs.contains) ?? false
    }
}
