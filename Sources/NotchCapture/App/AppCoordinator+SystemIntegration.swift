import AppKit
import ApplicationServices
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
    }

    private func handleDisplayEnvironmentChange() {
        panelController.reposition()
        updateIdlePillVisibility()
        synchronizePanel(with: viewModel.surfaceState)
    }

    func requestAccessibility() {
        suspendForSystemPermissionPrompt()
        selectionService.requestAccessibilityAccess()
        pollAccessibilityStatus()
    }

    private func pollAccessibilityStatus() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<20 {
                viewModel.accessibilityGranted = selectionService.isAccessibilityTrusted
                if viewModel.accessibilityGranted {
                    schedulePermissionSurfaceRestore()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// The notch panel intentionally sits above other notch utilities during an
    /// explicit session. System-owned permission prompts use a lower window level,
    /// so the panel must be removed for the duration of that modal interaction.
    private func suspendForSystemPermissionPrompt() {
        clearPermissionSuspension()
        switch viewModel.surfaceState {
        case .settings:
            permissionReturnState = .settings
        case .onboarding:
            permissionReturnState = .onboarding
        default:
            permissionReturnState = .expanded
        }
        panelController.dismiss(restoringFocus: false, animated: false)

        permissionLocalEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            self?.schedulePermissionSurfaceRestore()
            return event
        }
        permissionGlobalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.schedulePermissionSurfaceRestore()
        }
        permissionActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedulePermissionSurfaceRestore() }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func schedulePermissionSurfaceRestore() {
        permissionRestoreTask?.cancel()
        permissionRestoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self, let returnState = self.permissionReturnState else { return }

            let ownPID = ProcessInfo.processInfo.processIdentifier
            let appIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID
            guard appIsFrontmost, NSApp.modalWindow == nil else { return }

            self.clearPermissionSuspension()
            self.viewModel.surfaceState = returnState
            self.synchronizePanel(with: returnState)
        }
    }

    func clearPermissionSuspension() {
        permissionRestoreTask?.cancel()
        permissionRestoreTask = nil
        permissionReturnState = nil
        if let permissionLocalEventMonitor {
            NSEvent.removeMonitor(permissionLocalEventMonitor)
            self.permissionLocalEventMonitor = nil
        }
        if let permissionGlobalEventMonitor {
            NSEvent.removeMonitor(permissionGlobalEventMonitor)
            self.permissionGlobalEventMonitor = nil
        }
        if let permissionActivationObserver {
            NotificationCenter.default.removeObserver(permissionActivationObserver)
            self.permissionActivationObserver = nil
        }
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
        case .captureSelection: .captureSelection
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
