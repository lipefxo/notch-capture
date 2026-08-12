import AppKit
import Foundation

extension AppCoordinator {
    /// Re-anchors the panel after display topology changes or sleep/wake, and
    /// re-presents it when the app-level state and the panel state have drifted
    /// (e.g. a present() that failed while displays were unavailable).
    func installDisplayEnvironmentObservers() {
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDisplayEnvironmentChange()
            }
        }
        displayEnvironmentObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main,
                using: handler
            )
        )
        displayEnvironmentObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main,
                using: handler
            )
        )
        displayEnvironmentObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main,
                using: handler
            )
        )

        let applicationHandler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleFullScreenDetection()
            }
        }
        displayEnvironmentObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main,
                using: applicationHandler
            )
        )
        let activeSpaceHandler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activeSpaceGeneration += 1
                self.scheduleFullScreenDetection()
            }
        }
        displayEnvironmentObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main,
                using: activeSpaceHandler
            )
        )
    }

    private func handleDisplayEnvironmentChange() {
        displayEnvironmentGeneration += 1
        panelController.reposition()
        applyFullScreenCompactOverride()
        scheduleFullScreenDetection()
        updateIdlePillVisibility()
        synchronizePanel(with: viewModel.surfaceState)
    }

    /// Full-screen windows and their Space settle asynchronously. The short
    /// debounce avoids measuring the outgoing frame, and the second sample
    /// catches apps that publish their final Window Server bounds one beat
    /// after the workspace notification.
    func scheduleFullScreenDetection(delay: TimeInterval = 0.12) {
        guard !previewMode else { return }
        fullScreenDetectionTask?.cancel()
        fullScreenDetectionTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, let self else { return }
            self.refreshFullScreenDisplays()

            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            self.refreshFullScreenDisplays()
        }
    }

    /// Chromium's compositor-hosted fullscreen surface exposes its Window
    /// Server transition window for roughly 270 ms. A 200 ms sample interval
    /// observes that pulse without requiring browser Automation or
    /// Accessibility permission. Native fullscreen changes still take the
    /// faster notification path above.
    func startFullScreenMonitoring() {
        guard !previewMode else { return }
        fullScreenMonitoringTask?.cancel()
        fullScreenMonitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshFullScreenDisplays()
                try? await Task.sleep(for: .seconds(0.2))
            }
        }
    }

    private func refreshFullScreenDisplays() {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return }
        let displays = displayLocator.screens.compactMap { screen -> DisplayBoundsSnapshot? in
            guard let displayID = displayLocator.displayID(for: screen) else { return nil }
            let bounds = CGDisplayBounds(displayID)
            let leftInset = max(0, screen.visibleFrame.minX - screen.frame.minX)
            let rightInset = max(0, screen.frame.maxX - screen.visibleFrame.maxX)
            let topInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let bottomInset = max(0, screen.visibleFrame.minY - screen.frame.minY)
            let visibleBounds = CGRect(
                x: bounds.minX + leftInset,
                y: bounds.minY + topInset,
                width: max(0, bounds.width - leftInset - rightInset),
                height: max(0, bounds.height - topInset - bottomInset)
            )
            return DisplayBoundsSnapshot(
                displayID: displayID,
                bounds: bounds,
                visibleBounds: visibleBounds
            )
        }
        guard let windowObservation = FullScreenDisplayDetector.observe(
            displays: displays,
            frontmostApplication: frontmostApplication,
            excludingOwnerPIDs: [ProcessInfo.processInfo.processIdentifier]
        ) else {
            return
        }
        if rawFullScreenDisplayIDs != windowObservation.coveredDisplayIDs {
            rawFullScreenDisplayIDs = windowObservation.coveredDisplayIDs
            let foreground = windowObservation.foregroundWindowsByDisplay
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key):#\($0.value.windowID) \(NSStringFromRect($0.value.bounds))" }
                .joined(separator: ", ")
            PanelDiagnostics.log(
                "fullscreen raw: front=\(frontmostApplication.localizedName ?? "-") "
                    + "covered=\(windowObservation.coveredDisplayIDs.sorted()) "
                    + "foreground=[\(foreground)]"
            )
        }
        let update = fullScreenSessionTracker.update(FullScreenSessionObservation(
            window: windowObservation,
            timestamp: ProcessInfo.processInfo.systemUptime,
            activeSpaceGeneration: activeSpaceGeneration,
            displayEnvironmentGeneration: displayEnvironmentGeneration
        ))
        update.transitions.forEach { PanelDiagnostics.log($0.diagnosticDescription) }
        // A display counts as occupied when either the session tracker reports
        // full screen (native or browser-compositor) or an eligible window has
        // maximized to fill the working area. Both collapse the pill.
        let occupiedDisplayIDs = update.fullScreenDisplayIDs
            .union(windowObservation.maximizedDisplayIDs)
        guard occupiedDisplayIDs != fullScreenDisplayIDs else { return }
        fullScreenDisplayIDs = occupiedDisplayIDs
        PanelDiagnostics.log(
            "fullscreen: front=\(frontmostApplication.localizedName ?? "-") "
                + "fullscreen=\(update.fullScreenDisplayIDs.sorted()) "
                + "maximized=\(windowObservation.maximizedDisplayIDs.sorted()) "
                + "displays=\(occupiedDisplayIDs.sorted())"
        )
        applyFullScreenCompactOverride()
    }

    func applyFullScreenCompactOverride() {
        let displayID = panelController.targetDisplayID
            ?? displayLocator.pointerScreen.flatMap(displayLocator.displayID(for:))
        let shouldForceMinimal = FullScreenCompactPresentationPolicy.shouldForceMinimal(
            targetDisplayID: displayID,
            fullScreenDisplayIDs: fullScreenDisplayIDs
        )
        viewModel.setFullScreenCompactOverride(shouldForceMinimal)
    }

    func beginShortcutRecording(for action: AppViewModel.Shortcut.Action) {
        guard globalAction(for: action) != nil, let manager = hotKeyManager else { return }
        let currentDisplay = viewModel.shortcuts.first(where: { $0.action == action })?.displayValue ?? ""
        let oldDefinitions = manager.definitions
        manager.unregisterAll()
        pendingShortcutDefinitions = oldDefinitions
        viewModel.shortcutRecordingRequest = AppViewModel.ShortcutRecordingRequest(
            action: action,
            title: viewModel.shortcuts.first(where: { $0.action == action })?.title ?? "Shortcut",
            currentValue: currentDisplay
        )
    }

    func commitShortcutRecording(
        _ recording: ShortcutRecording,
        for action: AppViewModel.Shortcut.Action
    ) -> String? {
        guard let hotKeyAction = globalAction(for: action), let manager = hotKeyManager,
              let oldDefinitions = pendingShortcutDefinitions else {
            return "Shortcut recording is no longer active."
        }

        var definitions = oldDefinitions
        if definitions.contains(where: { $0.key != hotKeyAction && $0.value == recording.definition }) {
            return "That shortcut is already assigned to another Notch Capture action."
        }
        definitions[hotKeyAction] = recording.definition

        do {
            try manager.register(definitions)
            persistShortcut(recording, for: hotKeyAction)
            viewModel.updateShortcut(action, displayValue: recording.displayValue)
            viewModel.errorMessage = nil
            pendingShortcutDefinitions = nil
            viewModel.shortcutRecordingRequest = nil
            return nil
        } catch {
            try? manager.register(oldDefinitions)
            return error.localizedDescription
        }
    }

    func cancelShortcutRecording() {
        defer {
            pendingShortcutDefinitions = nil
            viewModel.shortcutRecordingRequest = nil
        }
        guard let oldDefinitions = pendingShortcutDefinitions, let manager = hotKeyManager else { return }
        do { try manager.register(oldDefinitions) } catch { show(error) }
    }

    func loadShortcutDefinitions() -> [GlobalHotKeyAction: GlobalHotKeyDefinition] {
        var definitions = GlobalHotKeyManager.defaultDefinitions
        for action in GlobalHotKeyAction.allCases {
            let keyCodeKey = DefaultsKey.shortcut(action, field: "keyCode")
            let modifiersKey = DefaultsKey.shortcut(action, field: "modifiers")
            guard defaults.object(forKey: keyCodeKey) != nil,
                  defaults.object(forKey: modifiersKey) != nil else { continue }
            definitions[action] = GlobalHotKeyDefinition(
                keyCode: UInt32(defaults.integer(forKey: keyCodeKey)),
                modifiers: UInt32(defaults.integer(forKey: modifiersKey))
            )
        }
        return definitions
    }

    private func persistShortcut(_ recording: ShortcutRecording, for action: GlobalHotKeyAction) {
        defaults.set(Int(recording.definition.keyCode), forKey: DefaultsKey.shortcut(action, field: "keyCode"))
        defaults.set(Int(recording.definition.modifiers), forKey: DefaultsKey.shortcut(action, field: "modifiers"))
        defaults.set(recording.displayValue, forKey: DefaultsKey.shortcut(action, field: "display"))
    }

    func updateShortcutDisplayValues() {
        for shortcut in viewModel.shortcuts {
            guard let action = globalAction(for: shortcut.action) else { continue }
            let display = defaults.string(forKey: DefaultsKey.shortcut(action, field: "display"))
            if let display { viewModel.updateShortcut(shortcut.action, displayValue: display) }
        }
    }

    private func globalAction(for action: AppViewModel.Shortcut.Action) -> GlobalHotKeyAction? {
        switch action {
        case .openComposer: .openComposer
        }
    }

    func presentExportPanel() {
        let panel = NSSavePanel()
        panel.title = "Export Notch Capture Library"
        panel.nameFieldStringValue = "Notch Capture Backup.notchcapture"
        panel.canCreateDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                let fileManager = FileManager.default
                do {
                    if fileManager.fileExists(atPath: destination.path) {
                        // Never delete the existing backup until the new export
                        // has fully succeeded; stage next to it and swap.
                        let staging = destination.deletingLastPathComponent()
                            .appendingPathComponent(".export-\(UUID().uuidString).notchcapture", isDirectory: true)
                        do {
                            _ = try self.packageService.export(to: staging)
                            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
                        } catch {
                            try? fileManager.removeItem(at: staging)
                            throw error
                        }
                    } else {
                        _ = try self.packageService.export(to: destination)
                    }
                    self.viewModel.errorMessage = nil
                } catch { self.show(error) }
            }
        }
    }

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Notch Capture Library"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let packageURL = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do {
                    _ = try self.packageService.importPackage(at: packageURL)
                    self.reloadFromStore()
                    self.viewModel.openExpanded()
                } catch { self.show(error) }
            }
        }
    }
}
