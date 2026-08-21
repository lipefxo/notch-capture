import AppKit
import Combine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator {
    enum DefaultsKey {
        static let onboardingComplete = "onboardingComplete"
        static let autoHideExternalPill = "autoHideExternalPill"
        static let timeFormat = "timeFormat"
        static let compactPresentationSize = "compactPresentationSize"

        static func shortcut(_ action: GlobalHotKeyAction, field: String) -> String {
            "shortcut.\(action.rawValue).\(field)"
        }
    }

    let modelContainer: ModelContainer
    let repository: ItemRepository
    let attachmentStore: AttachmentStore
    let packageService: CapturePackageService
    let linkMetadataFetcher: any LinkMetadataFetching
    private let loginItemService: LoginItemService
    private let updaterService: UpdaterService
    let displayLocator: DisplayLocator
    let nowPlayingService: NowPlayingService
    let audioOutputService: any AudioOutputControlling
    let studioLightService: any StudioLightControlling
    let cameraService: CameraService
    let cameraControlService: CameraControlService
    let cameraAimStore: CameraAimStore
    let cameraPresetStore: CameraPresetStore
    let defaults: UserDefaults
    let previewMode: Bool

    let viewModel: AppViewModel
    let panelController: PanelController
    var hotKeyManager: GlobalHotKeyManager?
    private var cancellables: Set<AnyCancellable> = []
    var composerPasteTask: Task<Void, Never>?
    var cameraPresentationTask: Task<Void, Never>?
    var pendingShortcutDefinitions: [GlobalHotKeyAction: GlobalHotKeyDefinition]?
    var displayEnvironmentObservers: [NSObjectProtocol] = []
    var fullScreenDetectionTask: Task<Void, Never>?
    var fullScreenMonitoringTask: Task<Void, Never>?
    var fullScreenDisplayIDs: Set<CGDirectDisplayID> = []
    var rawFullScreenDisplayIDs: Set<CGDirectDisplayID> = []
    var fullScreenSessionTracker = FullScreenSessionTracker()
    var activeSpaceGeneration = 0
    var displayEnvironmentGeneration = 0

    init(
        defaults: UserDefaults = .standard,
        audioOutputService injectedAudioOutputService: (any AudioOutputControlling)? = nil,
        studioLightService injectedStudioLightService: (any StudioLightControlling)? = nil
    ) throws {
        self.defaults = defaults
        self.previewMode = CommandLine.arguments.contains("--design-preview")

        let schema = Schema(NotchCaptureSchemaV2.models)
        var storeRecoveryBackupURL: URL?
        if previewMode {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            self.modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: NotchCaptureMigrationPlan.self,
                configurations: [configuration]
            )
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appendingPathComponent("NotchCapture", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let storeURL = directory.appendingPathComponent("NotchCapture.store")
            let configuration = ModelConfiguration("NotchCapture", schema: schema, url: storeURL)
            do {
                self.modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: NotchCaptureMigrationPlan.self,
                    configurations: [configuration]
                )
            } catch {
                // An unreadable store (corruption, incompatible schema) must not
                // brick the app: keep the bad store as a backup and start fresh.
                storeRecoveryBackupURL = try Self.moveStoreAside(storeURL: storeURL)
                self.modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: NotchCaptureMigrationPlan.self,
                    configurations: [configuration]
                )
            }
        }
        self.attachmentStore = try AttachmentStore()
        self.repository = ItemRepository(
            modelContext: modelContainer.mainContext,
            attachmentStore: attachmentStore
        )
        self.packageService = CapturePackageService(
            modelContext: modelContainer.mainContext,
            attachmentStore: attachmentStore
        )
        self.linkMetadataFetcher = LinkMetadataFetcher()
        self.loginItemService = LoginItemService()
        self.updaterService = UpdaterService(previewMode: previewMode)
        self.displayLocator = DisplayLocator()
        self.nowPlayingService = NowPlayingService()
        self.audioOutputService = injectedAudioOutputService ?? AudioOutputService()
        self.studioLightService = injectedStudioLightService
            ?? StudioLightService(
                defaults: defaults,
                onAccessPrompt: {
                    // The notch panel is non-key, so bring the Bluetooth privacy
                    // prompt in front when Pair is explicitly requested.
                    NSApp.activate(ignoringOtherApps: true)
                }
            )
        self.cameraService = CameraService(onAccessPrompt: {
            // An agent app with a non-key panel can otherwise leave the camera
            // TCC prompt stranded behind the user's frontmost window.
            NSApp.activate(ignoringOtherApps: true)
        })
        self.cameraControlService = CameraControlService()
        self.cameraAimStore = CameraAimStore(defaults: defaults)
        self.cameraPresetStore = CameraPresetStore(defaults: defaults)

        let timeFormat = AppViewModel.TimeFormat.fromStoredValue(
            defaults.string(forKey: DefaultsKey.timeFormat)
        )
        let compactPresentationSize = CompactPresentationSize.fromStoredValue(
            defaults.string(forKey: DefaultsKey.compactPresentationSize)
        )
        let initialState: AppViewModel.SurfaceState
        if previewMode {
            initialState = Self.requestedPreviewState()
        } else if defaults.bool(forKey: DefaultsKey.onboardingComplete)
                    || CommandLine.arguments.contains("--skip-onboarding") {
            initialState = .collapsed
        } else {
            initialState = .onboarding
        }

        if previewMode {
            let preview = AppViewModel.preview
            preview.surfaceState = initialState
            preview.onboardingStep = Self.requestedPreviewOnboardingStep()
            if initialState == .confirmation {
                preview.confirmation = AppViewModel.Confirmation(
                    title: "Send the revised capture flow",
                    destination: "Inbox"
                )
            }
            if initialState == .mirror {
                // No camera runs under --design-preview, so the control chrome
                // needs a stand-in to be reviewable in snapshots.
                preview.cameraControls = .init(
                    zoomRange: 100...400,
                    canRecenter: true,
                    panRange: -522000...522000,
                    tiltRange: -324000...360000
                )
                preview.cameraZoom = 130
                var presetState = CameraPresetState.empty
                presetState.setPreset(
                    CameraPreset(pan: 0, tilt: -64800, zoom: 130),
                    in: .one
                )
                preview.configureCameraPresets(presetState)
            }
            if CommandLine.arguments.contains("--preview-studio-light")
                || CommandLine.arguments.contains("--preview-studio-light-popover") {
                preview.studioLightState = StudioLightViewState(
                    connection: .connected,
                    configuredDevice: StudioLightDevice(
                        id: UUID(),
                        name: "MOLUS G60_STUDIO"
                    ),
                    discoveredDevices: [],
                    snapshot: StudioLightSnapshot(
                        isOn: true,
                        brightness: 54,
                        colorTemperature: 4_300
                    )
                )
            }
            self.viewModel = preview
        } else {
            self.viewModel = AppViewModel(
                surfaceState: initialState,
                autoHideExternalPill: defaults.bool(forKey: DefaultsKey.autoHideExternalPill),
                launchAtLogin: loginItemService.isEnabled,
                timeFormat: timeFormat,
                compactPresentationSize: compactPresentationSize,
                audioOutputState: audioOutputService.state,
                studioLightState: studioLightService.state
            )
        }
        if let storeRecoveryBackupURL {
            self.viewModel.errorMessage = "Your capture library couldn't be read, so a new one was started. The previous library was saved to \(storeRecoveryBackupURL.path)."
        }
        self.viewModel.updatesEnabled = updaterService.isEnabled

        let viewModel = self.viewModel
        self.panelController = PanelController(
            displayLocator: displayLocator,
            automaticDismissalEnabled: !previewMode
        ) { _ in
            AnyView(NotchSurfaceView(viewModel: viewModel))
        }
        self.panelController.compactPresentationSizeProvider = { [weak viewModel] in
            viewModel?.effectiveCompactPresentationSize ?? .minimal
        }
        self.panelController.panel.onLedgerRowKeyboardCommand = { [weak viewModel] command in
            viewModel?.performSelectedRowKeyboardCommand(command) ?? false
        }
        self.panelController.panel.onComposerImagePaste = { [weak self] pasteboard in
            self?.handleComposerImagePaste(from: pasteboard) ?? false
        }

        configureHooks()
        configureMedia()
        configureAudioOutput()
        configureStudioLight()
        configureCamera()
        configureStateSynchronization()
    }

    private static func moveStoreAside(storeURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let backupDirectory = storeURL.deletingLastPathComponent()
            .appendingPathComponent("Unreadable Store \(stamp)", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(
                at: source,
                to: backupDirectory.appendingPathComponent(source.lastPathComponent)
            )
        }
        return backupDirectory
    }

#if DEBUG
    /// Replays the "modal, then click away" flows in-process and reports the
    /// focus/interaction state after each step. Run with `--modal-probe`.
    private func runModalProbe() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let presentation = self.panelController.presentationCoordinator
            let panel = self.panelController.panel

            func log(_ message: String) {
                FileHandle.standardError.write(Data("modal-probe: \(message)\n".utf8))
            }
            @MainActor func report(_ label: String) {
                let responder = panel.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "nil"
                log("\(label): surface=\(self.viewModel.surfaceState) hasModal=\(presentation.hasModal) hasMenu=\(presentation.menu != nil) key=\(panel.isKeyWindow) visible=\(panel.isVisible) ignoresMouse=\(panel.ignoresMouseEvents) alpha=\(panel.alphaValue) active=\(NSApp.isActive) frame=\(panel.frame.size) responder=\(responder)")
            }
            @MainActor func type(_ character: String, keyCode: UInt16) {
                for eventType in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let event = NSEvent.keyEvent(
                        with: eventType,
                        location: .zero,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: panel.windowNumber,
                        context: nil,
                        characters: character,
                        charactersIgnoringModifiers: character,
                        isARepeat: false,
                        keyCode: keyCode
                    ) else { continue }
                    panel.sendEvent(event)
                }
            }
            @MainActor func probeModal() -> NotchModal {
                NotchModal(
                    kind: .standard,
                    title: "Probe",
                    message: nil,
                    textFieldLabel: "Name",
                    draft: "probe",
                    primaryTitle: "OK",
                    cancelTitle: "Cancel",
                    onSubmit: { _ in nil },
                    onCancel: {}
                )
            }

            try? await Task.sleep(for: .seconds(1.5))
            self.viewModel.openExpanded()
            try? await Task.sleep(for: .seconds(1.5))
            report("baseline expanded")
            type("a", keyCode: 0)
            try? await Task.sleep(for: .seconds(0.4))
            log("baseline typed composerText='\(self.viewModel.composerText)' (expect 'a')")
            self.viewModel.composerText = ""

            presentation.present(probeModal())
            try? await Task.sleep(for: .seconds(0.8))
            report("modal open")
            presentation.cancelActivePresentation() // scrim-click path
            try? await Task.sleep(for: .seconds(0.8))
            report("after in-place cancel")
            type("b", keyCode: 11)
            try? await Task.sleep(for: .seconds(0.4))
            log("in-place cancel composerText='\(self.viewModel.composerText)' (expect 'b')")
            self.viewModel.composerText = ""

            presentation.present(probeModal())
            try? await Task.sleep(for: .seconds(0.8))
            self.viewModel.handleDismissalRequest(.externalClick) // outside-app click path
            try? await Task.sleep(for: .seconds(1.2))
            report("after external dismiss")
            self.viewModel.openExpanded()
            try? await Task.sleep(for: .seconds(1.5))
            report("after reopen")
            type("c", keyCode: 8)
            try? await Task.sleep(for: .seconds(0.4))
            log("reopen composerText='\(self.viewModel.composerText)' (expect 'c')")

            // The user-reported flow: an item-actions MENU open, then a click
            // outside the panel. Poll afterwards so transient contract states
            // can be told apart from a stuck one.
            self.viewModel.composerText = ""
            presentation.present(NotchMenu(
                title: "Probe menu",
                anchor: CGRect(x: 330, y: 290, width: 28, height: 28),
                items: [NotchMenuItem(title: "Item", icon: nil, action: {})]
            ))
            try? await Task.sleep(for: .seconds(0.6))
            report("menu open")
            self.viewModel.handleDismissalRequest(.externalClick)
            for step in 1...8 {
                try? await Task.sleep(for: .seconds(0.4))
                report("menu dismiss poll \(step)")
            }
            self.viewModel.openExpanded()
            try? await Task.sleep(for: .seconds(1.5))
            report("after menu reopen")
            type("d", keyCode: 2)
            try? await Task.sleep(for: .seconds(0.4))
            log("menu reopen composerText='\(self.viewModel.composerText)' (expect 'd')")

            // Destructive confirm (Delete Tag shape: no text field), both
            // teardown paths.
            self.viewModel.composerText = ""
            func destructiveModal() -> NotchModal {
                NotchModal(
                    kind: .destructive,
                    title: "Delete @probe?",
                    message: "The tag will be removed.",
                    textFieldLabel: nil,
                    draft: "",
                    primaryTitle: "Delete Tag",
                    cancelTitle: "Cancel",
                    onSubmit: { _ in nil },
                    onCancel: {}
                )
            }
            presentation.present(destructiveModal())
            try? await Task.sleep(for: .seconds(0.8))
            report("destructive modal open")
            presentation.cancelActivePresentation() // scrim click
            try? await Task.sleep(for: .seconds(0.8))
            type("e", keyCode: 14)
            try? await Task.sleep(for: .seconds(0.4))
            log("destructive scrim-cancel composerText='\(self.viewModel.composerText)' (expect 'e')")
            self.viewModel.composerText = ""

            presentation.present(destructiveModal())
            try? await Task.sleep(for: .seconds(0.8))
            self.viewModel.handleDismissalRequest(.externalClick)
            for step in 1...5 {
                try? await Task.sleep(for: .seconds(0.4))
                report("destructive dismiss poll \(step)")
            }
            self.viewModel.openExpanded()
            try? await Task.sleep(for: .seconds(1.5))
            report("after destructive reopen")
            type("f", keyCode: 3)
            try? await Task.sleep(for: .seconds(0.4))
            log("destructive reopen composerText='\(self.viewModel.composerText)' (expect 'f')")

            // Menu → modal handoff (the real Delete Tag path: the focused
            // menu is replaced by a destructive modal), then outside click.
            self.viewModel.composerText = ""
            presentation.present(NotchMenu(
                title: "@probe",
                anchor: CGRect(x: 120, y: 150, width: 24, height: 24),
                items: [NotchMenuItem(title: "Delete", icon: "xmark", role: .destructive, action: {})]
            ))
            try? await Task.sleep(for: .seconds(0.6))
            presentation.dismissMenu()
            presentation.present(destructiveModal())
            try? await Task.sleep(for: .seconds(0.8))
            report("handoff modal open")
            self.viewModel.handleDismissalRequest(.externalClick)
            try? await Task.sleep(for: .seconds(1.4))
            report("handoff after dismiss")
            self.viewModel.openExpanded()
            try? await Task.sleep(for: .seconds(1.5))
            report("handoff after reopen")
            type("g", keyCode: 5)
            try? await Task.sleep(for: .seconds(0.4))
            log("handoff reopen composerText='\(self.viewModel.composerText)' (expect 'g')")

            // Occupancy flip-flop: hide to dormant, then re-present while the
            // hide fade is still in flight. A stale alpha animator can leave
            // an invisible, hit-testable panel behind (the "click eater").
            for delay in [0.10, 0.25, 0.40, 0.55] {
                self.viewModel.surfaceState = .expanded
                try? await Task.sleep(for: .seconds(1.0))
                self.viewModel.surfaceState = .dormant
                try? await Task.sleep(for: .seconds(delay))
                self.viewModel.surfaceState = .collapsed
                try? await Task.sleep(for: .seconds(1.4))
                report("flip-flop delay=\(delay)")
            }
            log("done")
        }
    }
#endif

    private nonisolated static func requestedPreviewState() -> AppViewModel.SurfaceState {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-state=") }) else {
            return .expanded
        }
        switch argument.dropFirst("--preview-state=".count) {
        case "collapsed": return .collapsed
        case "activity": return .collapsedActivity
        case "confirmation": return .confirmation
        case "settings": return .settings
        case "onboarding": return .onboarding
        case "drop": return .drop
        case "mirror": return .mirror
        default: return .expanded
        }
    }

    private nonisolated static func requestedPreviewOnboardingStep() -> AppViewModel.OnboardingStep {
        guard let argument = CommandLine.arguments.first(where: {
            $0.hasPrefix("--preview-onboarding-step=")
        }) else {
            return .capture
        }
        switch argument.dropFirst("--preview-onboarding-step=".count) {
        case "capture": return .capture
        case "organize": return .organize
        case "music": return .music
        default: return .capture
        }
    }

    func start() {
        if !previewMode {
            nowPlayingService.setActivityLevel(.compact)
            audioOutputService.start()
            studioLightService.start()
            do {
                let manager = try GlobalHotKeyManager { [weak self] action in
                    self?.handleHotKey(action)
                }
                try manager.register(loadShortcutDefinitions())
                hotKeyManager = manager
                updateShortcutDisplayValues()
            } catch {
                viewModel.errorMessage = error.localizedDescription
                viewModel.surfaceState = .expanded
            }
        }

        if !previewMode {
            installDisplayEnvironmentObservers()
            startFullScreenMonitoring()
            scheduleFullScreenDetection(delay: 0)
            updateIdlePillVisibility()
            do {
                // One-time launch maintenance; not needed on every reload.
                try repository.backfillMissingSortOrders()
                try repository.backfillMissingTagColorSeeds()
                try repository.removeOrphanedAttachmentFiles()
            } catch {
                // Maintenance failures are non-fatal; they retry next launch.
            }
        }
        reloadFromStore()
        synchronizePanel(with: viewModel.surfaceState)
#if DEBUG
        if CommandLine.arguments.contains("--modal-probe") {
            runModalProbe()
        }
        if previewMode, let output = snapshotOutputURL() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                do {
                    try self?.panelController.writeSnapshot(to: output)
                    NSApp.terminate(nil)
                } catch {
                    FileHandle.standardError.write(Data("Snapshot failed: \(error.localizedDescription)\n".utf8))
                    NSApp.terminate(nil)
                }
            }
        }
#endif
    }

    func stop() {
        hotKeyManager?.unregisterAll()
        hotKeyManager = nil
        nowPlayingService.stop()
        audioOutputService.stop()
        studioLightService.stop()
        cameraService.stop()
        cameraControlService.detach()
        cameraPresentationTask?.cancel()
        cameraPresentationTask = nil
        composerPasteTask?.cancel()
        fullScreenDetectionTask?.cancel()
        fullScreenDetectionTask = nil
        fullScreenMonitoringTask?.cancel()
        fullScreenMonitoringTask = nil
        displayEnvironmentObservers.forEach(NotificationCenter.default.removeObserver)
        displayEnvironmentObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        displayEnvironmentObservers.removeAll()
        panelController.dismiss(restoringFocus: false, animated: false)
    }

    private func configureHooks() {
        var hooks = AppViewModel.Hooks()
        hooks.onDismiss = { [weak self] in
            self?.panelController.restoreFocus()
        }
        hooks.onCaptureText = { [weak self] text, folderID in
            self?.captureManualText(text, folderID: folderID)
        }
        hooks.onCaptureComposerImages = { [weak self] text, images, folderID in
            self?.captureComposerImages(text: text, images: images, folderID: folderID)
        }
        hooks.onPastedImageProviders = { [weak self] providers, draftID in
            self?.loadPastedImages(from: providers, forComposerDraft: draftID)
        }
        hooks.onUndoCapture = { [weak self] id in
            self?.undoCapture(id: id)
        }
        hooks.onConfirmationPauseChanged = { [weak self] paused, remaining in
            self?.panelController.setConfirmationDismissalPaused(paused, remaining: remaining)
        }
        hooks.onToggleComplete = { [weak self] id in
            self?.toggleComplete(id: id)
        }
        hooks.onUpdateText = { [weak self] id, text in
            self?.updateText(text, for: id)
        }
        hooks.onTogglePin = { [weak self] id in
            self?.togglePin(id: id)
        }
        hooks.onReorder = { [weak self] assignments in
            self?.applyOrderAssignments(assignments)
        }
        hooks.onReorderFolders = { [weak self] assignments in
            self?.applyFolderOrderAssignments(assignments)
        }
        hooks.onArchive = { [weak self] id in
            self?.archive(id: id)
        }
        hooks.onSetDueDate = { [weak self] id, date in
            self?.setDueDate(date, for: id)
        }
        hooks.onMove = { [weak self] id, folderID in
            self?.move(id: id, to: folderID)
        }
        hooks.onCreateFolder = { [weak self] name in
            self?.createFolder(named: name)
        }
        hooks.onRenameFolder = { [weak self] id, name in
            self?.renameFolder(id: id, to: name)
        }
        hooks.onDeleteFolder = { [weak self] id in
            self?.deleteFolder(id: id)
        }
        hooks.onCreateTag = { [weak self] name in
            self?.createTag(named: name)
        }
        hooks.onRenameTag = { [weak self] id, name in
            self?.renameTag(id: id, to: name)
        }
        hooks.onDeleteTag = { [weak self] id in
            self?.deleteTag(id: id)
        }
        hooks.onTrash = { [weak self] id in
            self?.trash(id: id)
        }
        hooks.onRestore = { [weak self] id in
            self?.restore(id: id)
        }
        hooks.onDeletePermanently = { [weak self] id in
            self?.deletePermanently(id: id)
        }
        hooks.onEmptyTrash = { [weak self] in
            guard let self else { return }
            do {
                try self.repository.emptyTrash()
                self.reloadFromStore()
            } catch {
                self.show(error)
            }
        }
        hooks.onClearCompletedTasks = { [weak self] in
            guard let self else { return }
            do {
                try self.repository.trashCompletedTasks()
                self.reloadFromStore()
            } catch {
                self.reloadFromStore()
                self.show(error)
            }
        }
        hooks.onDroppedProviders = { [weak self] providers in
            self?.handleDrop(providers)
        }
        hooks.onCompleteOnboarding = { [weak self] in
            self?.defaults.set(true, forKey: DefaultsKey.onboardingComplete)
        }
        hooks.onSetLaunchAtLogin = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled)
        }
        hooks.onSetTimeFormat = { [weak self] timeFormat in
            self?.defaults.set(timeFormat.rawValue, forKey: DefaultsKey.timeFormat)
        }
        hooks.onSetCompactPresentationSize = { [weak self] presentationSize in
            self?.defaults.set(presentationSize.rawValue, forKey: DefaultsKey.compactPresentationSize)
        }
        hooks.onMusicPlayPause = { [weak self] in self?.nowPlayingService.playPause() }
        hooks.onMusicNext = { [weak self] in self?.nowPlayingService.nextTrack() }
        hooks.onMusicPrevious = { [weak self] in self?.nowPlayingService.previousTrack() }
        hooks.onMusicSeek = { [weak self] position in self?.nowPlayingService.seek(to: position) }
        hooks.onReconnectMedia = { [weak self] source in self?.nowPlayingService.reconnect(source) }
        hooks.onOpenMediaAutomationSettings = {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
            NSWorkspace.shared.open(url)
        }
        if previewMode {
            hooks.onSelectAudioOutput = { [weak self] target in
                guard let self,
                      self.viewModel.audioOutputState.isAvailable(target) else { return }
                self.viewModel.audioOutputState.mediaTarget = target
                self.viewModel.audioOutputState.systemTarget = target
                self.viewModel.audioOutputState.mediaDeviceName = target.systemDeviceName
                self.viewModel.audioOutputState.systemDeviceName = target.systemDeviceName
            }
        } else {
            hooks.onRefreshAudioOutputs = { [weak self] in
                self?.audioOutputService.refresh()
            }
            hooks.onSelectAudioOutput = { [weak self] target in
                guard let self else { return }
                do {
                    try self.audioOutputService.select(target)
                } catch {
                    self.show(error)
                }
            }
        }
        hooks.onStartStudioLightPairing = { [weak self] in
            self?.studioLightService.startPairing()
        }
        hooks.onCancelStudioLightPairing = { [weak self] in
            self?.studioLightService.cancelPairing()
        }
        hooks.onPairStudioLight = { [weak self] deviceID in
            self?.studioLightService.pair(deviceID: deviceID)
        }
        hooks.onRetryStudioLight = { [weak self] in
            self?.studioLightService.retry()
        }
        hooks.onForgetStudioLight = { [weak self] in
            self?.studioLightService.forget()
        }
        hooks.onRefreshStudioLight = { [weak self] in
            self?.studioLightService.refresh()
        }
        hooks.onSetStudioLightPower = { [weak self] isOn in
            self?.studioLightService.setPower(isOn)
        }
        hooks.onSetStudioLightBrightness = { [weak self] brightness, final in
            self?.studioLightService.setBrightness(brightness, final: final)
        }
        hooks.onSetStudioLightColorTemperature = { [weak self] temperature, final in
            self?.studioLightService.setColorTemperature(temperature, final: final)
        }
        hooks.onOpenBluetoothSettings = {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
            ) else { return }
            NSWorkspace.shared.open(url)
        }
        hooks.onOpenCameraSettings = {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
            NSWorkspace.shared.open(url)
        }
        hooks.onSetCameraZoom = { [weak self] zoom in
            self?.cameraControlService.setZoom(zoom)
        }
        hooks.onRecenterCamera = { [weak self] in
            guard let self else { return }
            self.cameraControlService.recenter()
            self.persistCameraAim(pan: 0, tilt: 0)
        }
        hooks.onMoveCamera = { [weak self] pan, tilt in
            guard let self else { return }
            self.cameraControlService.setPanTilt(pan: pan, tilt: tilt)
            self.persistCameraAim(pan: pan, tilt: tilt)
        }
        hooks.onSaveCameraPreset = { [weak self] slot, preset in
            guard let self, let uid = self.cameraService.activeDeviceUID else { return }
            self.cameraPresetStore.setPreset(preset, in: slot, for: uid)
        }
        hooks.onSelectCameraPreset = { [weak self] slot in
            guard let self, let uid = self.cameraService.activeDeviceUID else { return }
            self.cameraPresetStore.select(slot, for: uid)
        }
        hooks.onOpenShortcutRecorder = { [weak self] action in
            self?.beginShortcutRecording(for: action)
        }
        hooks.onCommitShortcutRecording = { [weak self] action, recording in
            self?.commitShortcutRecording(recording, for: action)
        }
        hooks.onCancelShortcutRecording = { [weak self] in
            self?.cancelShortcutRecording()
        }
        hooks.onImport = { [weak self] in
            self?.presentImportPanel()
        }
        hooks.onExport = { [weak self] in
            self?.presentExportPanel()
        }
        hooks.onCheckForUpdates = { [weak self] in
            self?.updaterService.checkForUpdates()
        }
        hooks.onQuit = {
            NSApp.terminate(nil)
        }
        viewModel.hooks = hooks

        panelController.onRequestDismiss = { [weak self] reason in
            guard let self else { return }
            let before = self.viewModel.surfaceState
            self.viewModel.handleDismissalRequest(reason)
            PanelDiagnostics.log("dismissal(\(reason)) surface \(before)→\(self.viewModel.surfaceState)")
        }
    }

#if DEBUG
    private func snapshotOutputURL() -> URL? {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--snapshot-output=") }) else {
            return nil
        }
        let path = String(argument.dropFirst("--snapshot-output=".count))
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
#endif

    private func configureStateSynchronization() {
        viewModel.$surfaceState
            .removeDuplicates()
            .sink { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    if [.confirmation, .expanded, .drop, .onboarding, .settings, .mirror].contains(state) {
                        self.updateIdlePillVisibility()
                    }
                    self.updateMediaActivityLevel(for: state)
                    self.updateCameraSession(for: state)
                    PanelDiagnostics.log("surface state → \(state)")
                    // Leaving Settings while a shortcut is being recorded must
                    // restore the temporarily unregistered global hotkeys.
                    if state != .settings, self.viewModel.shortcutRecordingRequest != nil {
                        self.cancelShortcutRecording()
                    }
                    // Menus and modals never survive a surface change. This
                    // must live here, not in a SwiftUI onChange: view updates
                    // for a collapsing/ordered-out panel are not guaranteed to
                    // run, and a stale modal leaves the next open fully
                    // disabled behind an invisible scrim.
                    self.panelController.presentationCoordinator.cancelActivePresentation()
                    self.synchronizePanel(with: state)
                }
            }
            .store(in: &cancellables)

        viewModel.$autoHideExternalPill
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: DefaultsKey.autoHideExternalPill)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.updateIdlePillVisibility()
                }
            }
            .store(in: &cancellables)

        viewModel.$effectiveCompactPresentationSize
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, [.collapsed, .collapsedActivity].contains(self.viewModel.surfaceState) else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.updateCollapsedActivityLayout()
                    self.panelController.refreshCompactPresentation()
                }
            }
            .store(in: &cancellables)
    }

    func synchronizePanel(with state: AppViewModel.SurfaceState) {
        updateCollapsedActivityLayout()
        let panelState = state.panelState
        panelController.present(panelState, activate: panelState.acceptsKeyboardInput)
        applyFullScreenCompactOverride()
    }

    func updateIdlePillVisibility() {
        let pointerGeometry = displayLocator.pointerScreen.flatMap(displayLocator.geometry(for:))
        let shouldHide = IdlePillVisibilityPolicy.shouldHide(
            autoHideExternalPill: viewModel.autoHideExternalPill,
            pointerHasHardwareNotch: pointerGeometry?.hasHardwareNotch
        )
        viewModel.setIdlePillHidden(shouldHide)
    }

    private func handleHotKey(_ action: GlobalHotKeyAction) {
        switch action {
        case .openComposer:
            viewModel.openExpanded()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
        } catch {
            viewModel.errorMessage = error.localizedDescription
            if viewModel.launchAtLogin != loginItemService.isEnabled {
                viewModel.launchAtLogin = loginItemService.isEnabled
            }
        }
    }

}
