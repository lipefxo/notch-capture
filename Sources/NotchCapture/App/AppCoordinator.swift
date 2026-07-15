import AppKit
import ApplicationServices
import Combine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator {
    private enum DefaultsKey {
        static let onboardingComplete = "onboardingComplete"
        static let ownership = "notchOwnership"
        static let autoHideExternalPill = "autoHideExternalPill"

        static func shortcut(_ action: GlobalHotKeyAction, field: String) -> String {
            "shortcut.\(action.rawValue).\(field)"
        }
    }

    private let modelContainer: ModelContainer
    private let repository: ItemRepository
    private let attachmentStore: AttachmentStore
    private let packageService: CapturePackageService
    private let selectionService: SelectionCaptureService
    private let screenCaptureService: ScreenCaptureService
    private let screenshotSelection = ScreenshotSelectionCoordinator()
    private let loginItemService: LoginItemService
    private let displayLocator: DisplayLocator
    private let occupancyService: SurfaceOccupancyService
    private let defaults: UserDefaults
    private let previewMode: Bool

    let viewModel: AppViewModel
    private let panelController: PanelController
    private var hotKeyManager: GlobalHotKeyManager?
    private var cancellables: Set<AnyCancellable> = []
    private var previousSurfaceState: AppViewModel.SurfaceState
    private var permissionReturnState: AppViewModel.SurfaceState?
    private var permissionLocalEventMonitor: Any?
    private var permissionGlobalEventMonitor: Any?
    private var permissionActivationObserver: NSObjectProtocol?
    private var permissionRestoreTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) throws {
        self.defaults = defaults
        self.previewMode = CommandLine.arguments.contains("--design-preview")

        let schema = Schema([CaptureItem.self, ItemList.self, Attachment.self])
        let configuration: ModelConfiguration
        if previewMode {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appendingPathComponent("NotchCapture", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            configuration = ModelConfiguration(
                "NotchCapture",
                schema: schema,
                url: directory.appendingPathComponent("NotchCapture.store")
            )
        }
        self.modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        self.attachmentStore = try AttachmentStore()
        self.repository = ItemRepository(
            modelContext: modelContainer.mainContext,
            attachmentStore: attachmentStore
        )
        self.packageService = CapturePackageService(
            modelContext: modelContainer.mainContext,
            attachmentStore: attachmentStore
        )
        self.selectionService = SelectionCaptureService()
        self.screenCaptureService = ScreenCaptureService()
        self.loginItemService = LoginItemService()
        self.displayLocator = DisplayLocator()
        self.occupancyService = SurfaceOccupancyService()

        let ownership = AppViewModel.NotchOwnership(
            rawValue: defaults.string(forKey: DefaultsKey.ownership) ?? ""
        ) ?? .automatic
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
            if initialState == .confirmation {
                preview.confirmation = AppViewModel.Confirmation(
                    title: "Send the revised capture flow",
                    destination: "Inbox"
                )
            }
            self.viewModel = preview
        } else {
            self.viewModel = AppViewModel(
                surfaceState: initialState,
                ownership: ownership,
                autoHideExternalPill: defaults.bool(forKey: DefaultsKey.autoHideExternalPill),
                launchAtLogin: loginItemService.isEnabled,
                accessibilityGranted: selectionService.isAccessibilityTrusted,
                screenRecordingGranted: screenCaptureService.hasPermission
            )
        }
        self.previousSurfaceState = initialState

        let viewModel = self.viewModel
        self.panelController = PanelController(
            displayLocator: displayLocator,
            automaticDismissalEnabled: !previewMode
                && !CommandLine.arguments.contains("--coexistence-test-sequence")
        ) { _ in
            AnyView(NotchSurfaceView(viewModel: viewModel))
        }

        configureHooks()
        configureStateSynchronization()
        configureOccupancy()
    }

    private nonisolated static func requestedPreviewState() -> AppViewModel.SurfaceState {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-state=") }) else {
            return .expanded
        }
        switch argument.dropFirst("--preview-state=".count) {
        case "collapsed": return .collapsed
        case "confirmation": return .confirmation
        case "settings": return .settings
        case "onboarding": return .onboarding
        default: return .expanded
        }
    }

    func start() {
        if !previewMode {
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

        occupancyService.refresh()
        reloadFromStore()
        synchronizePanel(with: viewModel.surfaceState)
#if DEBUG
        if CommandLine.arguments.contains("--coexistence-test-sequence") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.handleHotKey(.openComposer)
                if let self {
                    FileHandle.standardError.write(Data(
                        "Coexistence test opened: state=\(self.viewModel.surfaceState), visible=\(self.panelController.panel.isVisible), frame=\(self.panelController.panel.frame)\n".utf8
                    ))
                }
                try? await Task.sleep(for: .seconds(30))
                self?.viewModel.dismiss()
                if let self {
                    FileHandle.standardError.write(Data(
                        "Coexistence test dismissed: state=\(self.viewModel.surfaceState), visible=\(self.panelController.panel.isVisible)\n".utf8
                    ))
                }
            }
        }
        if previewMode, let output = snapshotOutputURL() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                do {
                    try self?.panelController.writeSnapshot(to: output)
                } catch {
                    FileHandle.standardError.write(Data("Snapshot failed: \(error.localizedDescription)\n".utf8))
                }
            }
        }
#endif
    }

    func stop() {
        hotKeyManager?.unregisterAll()
        hotKeyManager = nil
        occupancyService.stop()
        screenshotSelection.cancel()
        clearPermissionSuspension()
        panelController.dismiss(restoringFocus: false)
    }

    private func configureHooks() {
        var hooks = AppViewModel.Hooks()
        hooks.onDismiss = { [weak self] in
            self?.panelController.dismiss()
        }
        hooks.onCaptureText = { [weak self] text in
            self?.captureManualText(text)
        }
        hooks.onUndoCapture = { [weak self] id in
            self?.undoCapture(id: id)
        }
        hooks.onToggleComplete = { [weak self] id in
            self?.toggleComplete(id: id)
        }
        hooks.onTogglePin = { [weak self] id in
            self?.togglePin(id: id)
        }
        hooks.onArchive = { [weak self] id in
            self?.archive(id: id)
        }
        hooks.onSetDueDate = { [weak self] id, date in
            self?.setDueDate(date, for: id)
        }
        hooks.onMove = { [weak self] id, listName in
            self?.move(id: id, to: listName)
        }
        hooks.onCreateList = { [weak self] name in
            self?.createList(named: name)
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
        hooks.onDroppedProviders = { [weak self] providers in
            self?.handleDrop(providers)
        }
        hooks.onBeginScreenshot = { [weak self] in
            self?.beginScreenshotSelection()
        }
        hooks.onRequestAccessibility = { [weak self] in
            self?.requestAccessibility()
        }
        hooks.onRequestScreenRecording = { [weak self] in
            self?.requestScreenRecording()
        }
        hooks.onSetLaunchAtLogin = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled)
        }
        hooks.onSetOwnership = { [weak self] ownership in
            self?.setOwnership(ownership)
        }
        hooks.onOpenShortcutRecorder = { [weak self] action in
            self?.recordShortcut(for: action)
        }
        hooks.onImport = { [weak self] in
            self?.presentImportPanel()
        }
        hooks.onExport = { [weak self] in
            self?.presentExportPanel()
        }
        hooks.onQuit = {
            NSApp.terminate(nil)
        }
        viewModel.hooks = hooks

        panelController.onRequestDismiss = { [weak self] in
            self?.viewModel.dismiss()
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
                    if self.previousSurfaceState == .onboarding,
                       state == .expanded,
                       self.viewModel.onboardingPage == 2 {
                        self.defaults.set(true, forKey: DefaultsKey.onboardingComplete)
                    }
                    self.previousSurfaceState = state
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
                    self.applyOccupancy(self.occupancyService.snapshot)
                }
            }
            .store(in: &cancellables)
    }

    private func configureOccupancy() {
        occupancyService.onChange = { [weak self] snapshot in
            self?.applyOccupancy(snapshot)
        }
        applyOccupancy(occupancyService.snapshot)
    }

    private func synchronizePanel(with state: AppViewModel.SurfaceState) {
        let panelState: PanelState
        switch state {
        case .dormant: panelState = .dormant
        case .collapsed: panelState = .collapsed
        case .confirmation: panelState = .confirmation
        case .expanded: panelState = .expanded
        case .drop: panelState = .dropTarget
        case .screenshot: panelState = .screenshot
        case .onboarding: panelState = .onboarding
        case .settings: panelState = .settings
        }
        panelController.present(panelState, activate: panelState.acceptsKeyboardInput)
    }

    private func applyOccupancy(_ snapshot: SurfaceOccupancySnapshot) {
        let occupied: Bool
        if let screen = displayLocator.pointerScreen,
           let displayID = displayLocator.displayID(for: screen) {
            occupied = snapshot.isOccupied(displayID: displayID)
        } else {
            occupied = snapshot.hasKnownUtilityRunning
        }
        viewModel.isNotchFlowRunning = occupied

        guard viewModel.surfaceState == .collapsed || viewModel.surfaceState == .dormant else { return }
        let pointerGeometry = displayLocator.pointerScreen.flatMap(displayLocator.geometry(for:))
        let shouldAutoHideExternalPill = viewModel.autoHideExternalPill
            && pointerGeometry?.hasHardwareNotch == false
        let shouldYield = shouldAutoHideExternalPill
            || viewModel.ownership == .companion
            || (viewModel.ownership == .automatic && occupied)
        viewModel.surfaceState = shouldYield ? .dormant : .collapsed
    }

    private func handleHotKey(_ action: GlobalHotKeyAction) {
        clearPermissionSuspension()
        switch action {
        case .captureSelection:
            captureCurrentSelection()
        case .openComposer:
            viewModel.openExpanded()
            synchronizePanel(with: .expanded)
        case .captureRegion:
            beginScreenshotSelection()
        }
    }

    private func captureCurrentSelection() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await selectionService.captureSelection()
                let item = try repository.createItem(from: result)
                presentConfirmation(for: item)
            } catch {
                if case SelectionCaptureError.accessibilityPermissionRequired = error {
                    selectionService.requestAccessibilityAccess()
                }
                viewModel.errorMessage = error.localizedDescription
                viewModel.openExpanded()
            }
        }
    }

    private func captureManualText(_ text: String) {
        do {
            let item = try repository.createItem(text: text, origin: .manual)
            presentCaptureFeedback(for: item, feedback: .stayExpanded)
        } catch {
            show(error)
        }
    }

    @discardableResult
    private func createCapture(
        payload: CapturePayload,
        origin: CaptureOrigin,
        source: CaptureSource = CaptureSource()
    ) throws -> CaptureItem {
        try repository.createItem(from: payload, origin: origin, source: source)
    }

    private func fileAttachment(_ url: URL, order: Int) throws -> Attachment {
        let stored = try attachmentStore.storeFile(at: url)
        return Attachment(
            id: stored.id,
            kind: stored.kind,
            typeIdentifier: stored.typeIdentifier,
            originalFilename: stored.originalFilename,
            relativePath: stored.relativePath,
            order: order
        )
    }

    private func dataAttachment(
        _ data: Data,
        filename: String,
        type: UTType,
        kind: AttachmentKind,
        order: Int
    ) throws -> Attachment {
        let stored = try attachmentStore.storeData(data, filename: filename, type: type, kind: kind)
        return Attachment(
            id: stored.id,
            kind: stored.kind,
            typeIdentifier: stored.typeIdentifier,
            originalFilename: stored.originalFilename,
            relativePath: stored.relativePath,
            order: order
        )
    }

    private func linkAttachment(_ url: URL, order: Int) -> Attachment {
        Attachment(
            kind: .url,
            typeIdentifier: UTType.url.identifier,
            originalFilename: url.host(percentEncoded: false) ?? url.absoluteString,
            url: url,
            order: order
        )
    }

    private func presentConfirmation(for item: CaptureItem) {
        presentCaptureFeedback(for: item, feedback: .transientConfirmation)
    }

    private func presentCaptureFeedback(
        for item: CaptureItem,
        feedback: AppViewModel.CaptureFeedback
    ) {
        reloadFromStore()
        guard let ledger = viewModel.items.first(where: { $0.id == item.id }) else { return }
        viewModel.showCaptureFeedback(for: ledger, feedback: feedback)
        if feedback == .transientConfirmation {
            synchronizePanel(with: .confirmation)
        }
    }

    private func undoCapture(id: UUID?) {
        guard let id, let item = findItem(id) else { return }
        do {
            try repository.deletePermanently(item)
            reloadFromStore()
        } catch {
            show(error)
        }
    }

    private func toggleComplete(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            if item.kind == .note { try repository.setKind(.task, for: item) }
            try repository.setCompleted(!item.isCompleted, for: item)
            reloadFromStore()
        } catch { show(error) }
    }

    private func togglePin(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.setPinned(!item.isPinned, for: item)
            reloadFromStore()
        } catch { show(error) }
    }

    private func archive(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.archive(item)
            reloadFromStore()
        } catch { show(error) }
    }

    private func setDueDate(_ date: Date?, for id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.setDueDate(date, for: item)
            reloadFromStore()
        } catch { show(error) }
    }

    private func move(id: UUID, to listName: String) {
        guard let item = findItem(id) else { return }
        do {
            let lists = try modelContainer.mainContext.fetch(FetchDescriptor<ItemList>())
            let list = try lists.first(where: { $0.name == listName }) ?? repository.createList(name: listName)
            try repository.move(item, to: list)
            reloadFromStore()
        } catch { show(error) }
    }

    private func createList(named name: String) {
        do {
            _ = try repository.createList(name: name)
            reloadFromStore()
        } catch { show(error) }
    }

    private func trash(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.trash(item)
            reloadFromStore()
        } catch { show(error) }
    }

    private func restore(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.restore(item)
            reloadFromStore()
        } catch { show(error) }
    }

    private func deletePermanently(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.deletePermanently(item)
            reloadFromStore()
        } catch { show(error) }
    }

    private func findItem(_ id: UUID) -> CaptureItem? {
        try? modelContainer.mainContext.fetch(FetchDescriptor<CaptureItem>()).first { $0.id == id }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var urls: [URL] = []
            var textParts: [String] = []
            var imagePayloads: [(Data, UTType)] = []
            var storedPaths: [String] = []

            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let url = await loadURL(from: provider, type: .fileURL) {
                    urls.append(url)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let url = await loadURL(from: provider, type: .url) {
                    urls.append(url)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                          let data = await loadData(from: provider, type: .image) {
                    imagePayloads.append((data, .png))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = await loadText(from: provider) {
                    textParts.append(text)
                }
            }

            do {
                var attachments = try urls.enumerated().map { index, url in
                    url.isFileURL ? try fileAttachment(url, order: index) : linkAttachment(url, order: index)
                }
                for (offset, payload) in imagePayloads.enumerated() {
                    attachments.append(try dataAttachment(
                        payload.0,
                        filename: "Dropped Image \(offset + 1).png",
                        type: payload.1,
                        kind: .image,
                        order: attachments.count
                    ))
                }
                storedPaths = attachments.compactMap(\.relativePath)
                let item = try repository.createItem(
                    text: textParts.joined(separator: "\n"),
                    origin: .drop,
                    attachments: attachments
                )
                presentConfirmation(for: item)
            } catch {
                storedPaths.forEach { try? attachmentStore.remove(relativePath: $0) }
                show(error)
            }
        }
    }

    private func loadURL(from provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else if let string = item as? String {
                    continuation.resume(returning: URL(string: string))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadData(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func beginScreenshotSelection() {
        guard screenCaptureService.hasPermission else {
            requestScreenRecording()
            viewModel.errorMessage = "Allow Screen Recording, then use the shortcut again."
            viewModel.openExpanded()
            return
        }
        viewModel.surfaceState = .screenshot
        screenshotSelection.begin { [weak self] selection in
            guard let self else { return }
            guard let selection else {
                self.viewModel.openExpanded()
                return
            }
            Task { @MainActor in
                do {
                    let data = try await self.screenCaptureService.captureRegion(selection.rect, on: selection.screen)
                    let item = try self.repository.createItem(
                        from: .image(data, typeIdentifier: UTType.png.identifier),
                        origin: .screenshot
                    )
                    self.presentConfirmation(for: item)
                } catch {
                    self.show(error)
                }
            }
        }
    }

    private func requestAccessibility() {
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

    private func requestScreenRecording() {
        suspendForSystemPermissionPrompt()
        viewModel.screenRecordingGranted = screenCaptureService.requestPermission()
        if viewModel.screenRecordingGranted {
            schedulePermissionSurfaceRestore()
        }
    }

    /// The notch panel intentionally sits above other notch utilities during an
    /// explicit session. System-owned permission prompts use a lower window level,
    /// so the panel must be removed for the duration of that modal interaction.
    private func suspendForSystemPermissionPrompt() {
        clearPermissionSuspension()
        permissionReturnState = viewModel.surfaceState == .settings ? .settings : .expanded
        panelController.dismiss(restoringFocus: false)

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

    private func clearPermissionSuspension() {
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

    private func setOwnership(_ ownership: AppViewModel.NotchOwnership) {
        defaults.set(ownership.rawValue, forKey: DefaultsKey.ownership)
        applyOccupancy(occupancyService.snapshot)
    }

    private func recordShortcut(for action: AppViewModel.Shortcut.Action) {
        guard let hotKeyAction = globalAction(for: action), let manager = hotKeyManager else { return }
        let currentDisplay = viewModel.shortcuts.first(where: { $0.action == action })?.displayValue ?? ""
        let oldDefinitions = manager.definitions
        manager.unregisterAll()

        guard let recording = ShortcutRecorder.capture(
            title: viewModel.shortcuts.first(where: { $0.action == action })?.title ?? "Shortcut",
            currentValue: currentDisplay
        ) else {
            do { try manager.register(oldDefinitions) } catch { show(error) }
            return
        }

        var definitions = oldDefinitions
        if definitions.contains(where: { $0.key != hotKeyAction && $0.value == recording.definition }) {
            do { try manager.register(oldDefinitions) } catch { show(error) }
            viewModel.errorMessage = "That shortcut is already assigned to another Notch Capture action."
            return
        }
        definitions[hotKeyAction] = recording.definition

        do {
            try manager.register(definitions)
            persistShortcut(recording, for: hotKeyAction)
            viewModel.updateShortcut(action, displayValue: recording.displayValue)
            viewModel.errorMessage = nil
        } catch {
            try? manager.register(oldDefinitions)
            show(error)
        }
    }

    private func loadShortcutDefinitions() -> [GlobalHotKeyAction: GlobalHotKeyDefinition] {
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

    private func updateShortcutDisplayValues() {
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
        case .captureRegion: .captureRegion
        }
    }

    private func presentExportPanel() {
        let panel = NSSavePanel()
        panel.title = "Export Notch Capture Library"
        panel.nameFieldStringValue = "Notch Capture Backup.notchcapture"
        panel.canCreateDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    _ = try self.packageService.export(to: destination)
                    self.viewModel.errorMessage = nil
                } catch { self.show(error) }
            }
        }
    }

    private func presentImportPanel() {
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

    private func reloadFromStore() {
        guard !previewMode else { return }
        do {
            let descriptor = FetchDescriptor<CaptureItem>(
                sortBy: [SortDescriptor(\CaptureItem.updatedAt, order: .reverse)]
            )
            let items = try modelContainer.mainContext.fetch(descriptor)
            let lists = try modelContainer.mainContext.fetch(
                FetchDescriptor<ItemList>(sortBy: [SortDescriptor(\ItemList.sortOrder)])
            )
            if lists.isEmpty {
                for name in ["Work", "Personal", "Ideas"] {
                    _ = try repository.createList(name: name)
                }
                let seeded = try modelContainer.mainContext.fetch(
                    FetchDescriptor<ItemList>(sortBy: [SortDescriptor(\ItemList.sortOrder)])
                )
                viewModel.items = items.map(makeLedgerItem)
                viewModel.lists = seeded.map(\.name)
                return
            }
            viewModel.items = items.map(makeLedgerItem)
            viewModel.lists = lists.map(\.name)
        } catch {
            show(error)
        }
    }

    private func makeLedgerItem(_ item: CaptureItem) -> AppViewModel.LedgerItem {
        let lines = item.text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let detail = lines.dropFirst().joined(separator: "\n")
        let attachments = item.attachments.sorted { $0.order < $1.order }.map { attachment in
            let previewURL: URL?
            if let relativePath = attachment.relativePath {
                previewURL = try? attachmentStore.resolve(relativePath: relativePath)
            } else {
                previewURL = attachment.url
            }
            return AppViewModel.LedgerAttachment(
                id: attachment.id,
                kind: uiAttachmentKind(attachment.kind),
                name: attachment.originalFilename,
                subtitle: attachment.contentType?.localizedDescription,
                previewURL: previewURL
            )
        }
        return AppViewModel.LedgerItem(
            id: item.id,
            kind: item.kind == .task ? .task : .note,
            title: item.displayTitle,
            detail: detail,
            createdAt: item.createdAt,
            dueDate: item.dueDate,
            listName: item.list?.name,
            sourceApp: item.sourceApplicationName,
            isPinned: item.isPinned,
            isCompleted: item.isCompleted,
            isArchived: item.isArchived,
            isTrashed: item.isTrashed,
            attachments: attachments
        )
    }

    private func uiAttachmentKind(_ kind: AttachmentKind) -> AppViewModel.LedgerAttachment.Kind {
        switch kind {
        case .file: .file
        case .image: .image
        case .url: .link
        case .screenshot: .screenshot
        }
    }

    private func show(_ error: Error) {
        viewModel.errorMessage = error.localizedDescription
        viewModel.openExpanded()
    }
}
