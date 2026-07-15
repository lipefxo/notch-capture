import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    enum SurfaceState: Equatable {
        case dormant
        case collapsed
        case confirmation
        case expanded
        case drop
        case screenshot
        case onboarding
        case settings
    }

    enum InboxFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case tasks = "Tasks"
        case due = "Due"
        case completed = "Completed"
        case archive = "Archive"
        case trash = "Trash"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .all: "tray.full"
            case .tasks: "checkmark.circle"
            case .due: "calendar"
            case .completed: "checkmark.circle.fill"
            case .archive: "archivebox"
            case .trash: "trash"
            }
        }
    }

    enum NotchOwnership: String, CaseIterable, Identifiable {
        case automatic = "Automatic"
        case companion = "Companion"
        case primary = "Primary"

        var id: Self { self }

        var explanation: String {
            switch self {
            case .automatic:
                "Yield the notch only when NotchFlow is present."
            case .companion:
                "Keep the idle notch completely available to NotchFlow."
            case .primary:
                "Keep Notch Capture visible, even when another notch app is running."
            }
        }
    }

    enum ItemKind: String, Codable, Hashable {
        case note
        case task
    }

    enum ReorderPlacement: Hashable {
        case before
        case after
    }

    enum KeyboardFocus: Equatable {
        case composer
        case selectedRow
        case none
    }

    struct LedgerAttachment: Identifiable, Hashable {
        enum Kind: String, Hashable {
            case file
            case image
            case link
            case screenshot
        }

        var id: UUID
        var kind: Kind
        var name: String
        var subtitle: String?
        var previewURL: URL?

        init(
            id: UUID = UUID(),
            kind: Kind,
            name: String,
            subtitle: String? = nil,
            previewURL: URL? = nil
        ) {
            self.id = id
            self.kind = kind
            self.name = name
            self.subtitle = subtitle
            self.previewURL = previewURL
        }
    }

    struct LedgerItem: Identifiable, Hashable {
        var id: UUID
        var kind: ItemKind
        var title: String
        var detail: String
        var createdAt: Date
        var dueDate: Date?
        var listName: String?
        var sourceApp: String?
        var isPinned: Bool
        var isCompleted: Bool
        var completedAt: Date?
        var isArchived: Bool
        var isTrashed: Bool
        var sortOrder: Int?
        var attachments: [LedgerAttachment]

        init(
            id: UUID = UUID(),
            kind: ItemKind = .note,
            title: String,
            detail: String = "",
            createdAt: Date = .now,
            dueDate: Date? = nil,
            listName: String? = nil,
            sourceApp: String? = nil,
            isPinned: Bool = false,
            isCompleted: Bool = false,
            completedAt: Date? = nil,
            isArchived: Bool = false,
            isTrashed: Bool = false,
            sortOrder: Int? = nil,
            attachments: [LedgerAttachment] = []
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.detail = detail
            self.createdAt = createdAt
            self.dueDate = dueDate
            self.listName = listName
            self.sourceApp = sourceApp
            self.isPinned = isPinned
            self.isCompleted = isCompleted
            self.completedAt = completedAt
            self.isArchived = isArchived
            self.isTrashed = isTrashed
            self.sortOrder = sortOrder
            self.attachments = attachments
        }

        var displaysAttachmentPrefix: Bool {
            !attachments.isEmpty
        }
    }

    struct Confirmation: Equatable {
        static let duration: TimeInterval = 5

        var itemID: UUID?
        var title: String
        var destination: String
        var expiresAt: Date
        var pausedRemaining: TimeInterval?

        init(
            itemID: UUID? = nil,
            title: String,
            destination: String = "Inbox",
            expiresAt: Date = .now.addingTimeInterval(Self.duration),
            pausedRemaining: TimeInterval? = nil
        ) {
            self.itemID = itemID
            self.title = title
            self.destination = destination
            self.expiresAt = expiresAt
            self.pausedRemaining = pausedRemaining
        }

        var isPaused: Bool {
            pausedRemaining != nil
        }

        func remaining(at date: Date) -> TimeInterval {
            max(0, min(Self.duration, pausedRemaining ?? expiresAt.timeIntervalSince(date)))
        }

        func progress(at date: Date) -> Double {
            remaining(at: date) / Self.duration
        }
    }

    enum CaptureFeedback: Equatable {
        case stayExpanded
        case transientConfirmation
    }

    struct Shortcut: Identifiable, Hashable {
        enum Action: String, Hashable {
            case captureSelection
            case openComposer
            case captureRegion
        }

        var action: Action
        var title: String
        var displayValue: String

        var id: Action { action }
    }

    struct Hooks {
        var onDismiss: () -> Void = {}
        var onCaptureText: (String) -> Void = { _ in }
        var onUndoCapture: (UUID?) -> Void = { _ in }
        var onConfirmationPauseChanged: (Bool, TimeInterval) -> Void = { _, _ in }
        var onToggleComplete: (UUID) -> Void = { _ in }
        var onTogglePin: (UUID) -> Void = { _ in }
        var onReorder: ([ItemOrderAssignment]) -> Void = { _ in }
        var onArchive: (UUID) -> Void = { _ in }
        var onSetDueDate: (UUID, Date?) -> Void = { _, _ in }
        var onMove: (UUID, String) -> Void = { _, _ in }
        var onCreateList: (String) -> Void = { _ in }
        var onTrash: (UUID) -> Void = { _ in }
        var onRestore: (UUID) -> Void = { _ in }
        var onDeletePermanently: (UUID) -> Void = { _ in }
        var onDroppedProviders: ([NSItemProvider]) -> Void = { _ in }
        var onBeginScreenshot: () -> Void = {}
        var onRequestAccessibility: () -> Void = {}
        var onRequestScreenRecording: () -> Void = {}
        var onSetLaunchAtLogin: (Bool) -> Void = { _ in }
        var onSetOwnership: (NotchOwnership) -> Void = { _ in }
        var onOpenShortcutRecorder: (Shortcut.Action) -> Void = { _ in }
        var onImport: () -> Void = {}
        var onExport: () -> Void = {}
        var onQuit: () -> Void = {}
    }

    @Published var surfaceState: SurfaceState
    @Published var items: [LedgerItem]
    @Published var selectedItemID: UUID?
    @Published private(set) var keyboardFocus: KeyboardFocus = .composer
    @Published var filter: InboxFilter = .all
    @Published var composerText = ""
    @Published var confirmation: Confirmation?
    @Published var errorMessage: String?
    @Published var lists: [String]
    @Published var newListName = ""
    @Published var ownership: NotchOwnership {
        didSet { hooks.onSetOwnership(ownership) }
    }
    @Published var autoHideExternalPill: Bool
    @Published var launchAtLogin: Bool {
        didSet { hooks.onSetLaunchAtLogin(launchAtLogin) }
    }
    @Published var accessibilityGranted: Bool
    @Published var screenRecordingGranted: Bool
    @Published var onboardingPage = 0
    @Published var isNotchFlowRunning = false
    @Published var shortcuts: [Shortcut]

    var hooks: Hooks
    private let now: () -> Date

    init(
        surfaceState: SurfaceState = .collapsed,
        items: [LedgerItem] = [],
        lists: [String] = ["Work", "Personal", "Ideas"],
        ownership: NotchOwnership = .automatic,
        autoHideExternalPill: Bool = false,
        launchAtLogin: Bool = false,
        accessibilityGranted: Bool = false,
        screenRecordingGranted: Bool = false,
        shortcuts: [Shortcut] = [
            Shortcut(action: .captureSelection, title: "Capture selection", displayValue: "⌃⇧Space"),
            Shortcut(action: .openComposer, title: "Open composer", displayValue: "⌃⇧N"),
            Shortcut(action: .captureRegion, title: "Capture region", displayValue: "⌃⇧S")
        ],
        hooks: Hooks = Hooks(),
        now: @escaping () -> Date = { .now }
    ) {
        self.surfaceState = surfaceState
        self.items = items
        self.lists = lists
        self.ownership = ownership
        self.autoHideExternalPill = autoHideExternalPill
        self.launchAtLogin = launchAtLogin
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
        self.shortcuts = shortcuts
        self.hooks = hooks
        self.now = now
    }

    var visibleItems: [LedgerItem] {
        let query = normalizedComposerText
        return items
            .filter(matchesFilter)
            .filter { item in
                query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
                    || item.detail.localizedCaseInsensitiveContains(query)
                    || item.attachments.contains { $0.name.localizedCaseInsensitiveContains(query) }
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return itemComesBefore(lhs, rhs)
            }
    }

    var pinnedItems: [LedgerItem] { visibleItems.filter(\.isPinned) }
    var unpinnedItems: [LedgerItem] { visibleItems.filter { !$0.isPinned } }

    var composerHasQuery: Bool { !normalizedComposerText.isEmpty }
    var composerHasMatches: Bool { composerHasQuery && !visibleItems.isEmpty }
    var canAddComposerText: Bool { composerHasQuery && visibleItems.isEmpty }

    func openExpanded() {
        errorMessage = nil
        keyboardFocus = .composer
        surfaceState = .expanded
    }

    func dismiss() {
        clearSelection()
        composerText = ""
        errorMessage = nil
        surfaceState = shouldYieldIdleSurface ? .dormant : .collapsed
        hooks.onDismiss()
    }

    func submitComposer() {
        let text = normalizedComposerText
        guard !text.isEmpty else {
            return
        }
        guard canAddComposerText else {
            if let item = visibleItems.first {
                select(item)
            }
            return
        }
        errorMessage = nil
        filter = .all
        hooks.onCaptureText(text)
        composerText = ""
    }

    func focusComposer() {
        keyboardFocus = .composer
    }

    func select(_ item: LedgerItem) {
        guard selectedItemID != item.id else {
            clearSelection()
            return
        }
        selectedItemID = item.id
        keyboardFocus = .selectedRow
    }

    @discardableResult
    func performSelectedRowKeyboardCommand(_ command: LedgerRowKeyboardCommand) -> Bool {
        guard keyboardFocus == .selectedRow,
              let selectedItemID,
              let item = visibleItems.first(where: { $0.id == selectedItemID }) else {
            return false
        }

        switch command {
        case .toggleCompletion:
            toggleComplete(item)
        case .moveToTrash:
            guard !item.isTrashed else { return true }
            trash(item)
        }
        return true
    }

    func showCaptureFeedback(
        for item: LedgerItem,
        feedback: CaptureFeedback,
        destination: String = "Inbox"
    ) {
        errorMessage = nil
        switch feedback {
        case .stayExpanded:
            confirmation = nil
            surfaceState = .expanded
        case .transientConfirmation:
            confirmation = Confirmation(
                itemID: item.id,
                title: item.title,
                destination: destination,
                expiresAt: now().addingTimeInterval(Confirmation.duration)
            )
            surfaceState = .confirmation
        }
    }

    func showConfirmation(for item: LedgerItem, destination: String = "Inbox") {
        showCaptureFeedback(for: item, feedback: .transientConfirmation, destination: destination)
    }

    func undoConfirmation() {
        hooks.onUndoCapture(confirmation?.itemID)
        confirmation = nil
        dismiss()
    }

    func setConfirmationPaused(_ paused: Bool) {
        guard var confirmation else { return }
        let date = now()

        if paused {
            guard confirmation.pausedRemaining == nil else { return }
            confirmation.pausedRemaining = confirmation.remaining(at: date)
        } else {
            guard let remaining = confirmation.pausedRemaining else { return }
            confirmation.pausedRemaining = nil
            confirmation.expiresAt = date.addingTimeInterval(remaining)
        }

        let remaining = confirmation.remaining(at: date)
        self.confirmation = confirmation
        hooks.onConfirmationPauseChanged(paused, remaining)
    }

    func toggleComplete(_ item: LedgerItem) {
        mutateItem(item.id) {
            $0.isCompleted.toggle()
            $0.completedAt = $0.isCompleted ? .now : nil
        }
        hooks.onToggleComplete(item.id)
    }

    func togglePin(_ item: LedgerItem) {
        let destinationPinned = !item.isPinned
        let topOrder = (items
            .filter { $0.isPinned == destinationPinned }
            .compactMap(\.sortOrder)
            .min() ?? 0) - 1
        mutateItem(item.id) {
            $0.isPinned = destinationPinned
            $0.sortOrder = topOrder
        }
        hooks.onTogglePin(item.id)
    }

    @discardableResult
    func reorder(
        itemID: UUID,
        relativeTo targetID: UUID?,
        placement: ReorderPlacement,
        destinationPinned: Bool
    ) -> Bool {
        guard let dragged = items.first(where: { $0.id == itemID }) else { return false }
        let sourcePinned = dragged.isPinned
        guard targetID != itemID else { return false }

        var destination = items
            .filter { $0.isPinned == destinationPinned && $0.id != itemID }
            .sorted(by: itemComesBefore)

        let insertionIndex: Int
        if let targetID,
           let targetIndex = destination.firstIndex(where: { $0.id == targetID }) {
            insertionIndex = targetIndex + (placement == .after ? 1 : 0)
        } else {
            insertionIndex = placement == .before ? 0 : destination.endIndex
        }

        var moved = dragged
        moved.isPinned = destinationPinned
        destination.insert(moved, at: insertionIndex)

        let affectedPinnedStates = sourcePinned == destinationPinned
            ? [destinationPinned]
            : [sourcePinned, destinationPinned]
        var assignments: [ItemOrderAssignment] = []
        for pinnedState in affectedPinnedStates {
            let ordered = pinnedState == destinationPinned
                ? destination
                : items
                    .filter { $0.isPinned == pinnedState && $0.id != itemID }
                    .sorted(by: itemComesBefore)
            assignments.append(contentsOf: ordered.enumerated().map { index, item in
                ItemOrderAssignment(id: item.id, isPinned: pinnedState, sortOrder: index)
            })
        }

        let changed = assignments.contains { assignment in
            guard let item = items.first(where: { $0.id == assignment.id }) else { return true }
            return item.isPinned != assignment.isPinned || item.sortOrder != assignment.sortOrder
        }
        guard changed else { return false }

        let assignmentByID = Dictionary(uniqueKeysWithValues: assignments.map { ($0.id, $0) })
        for index in items.indices {
            guard let assignment = assignmentByID[items[index].id] else { continue }
            items[index].isPinned = assignment.isPinned
            items[index].sortOrder = assignment.sortOrder
        }
        hooks.onReorder(assignments)
        return true
    }

    func moveUp(_ item: LedgerItem) {
        let group = visibleItems.filter { $0.isPinned == item.isPinned }
        guard let index = group.firstIndex(where: { $0.id == item.id }), index > 0 else { return }
        _ = reorder(
            itemID: item.id,
            relativeTo: group[index - 1].id,
            placement: .before,
            destinationPinned: item.isPinned
        )
    }

    func moveDown(_ item: LedgerItem) {
        let group = visibleItems.filter { $0.isPinned == item.isPinned }
        guard let index = group.firstIndex(where: { $0.id == item.id }), index < group.count - 1 else { return }
        _ = reorder(
            itemID: item.id,
            relativeTo: group[index + 1].id,
            placement: .after,
            destinationPinned: item.isPinned
        )
    }

    func canMoveUp(_ item: LedgerItem) -> Bool {
        visibleItems.filter { $0.isPinned == item.isPinned }.first?.id != item.id
    }

    func canMoveDown(_ item: LedgerItem) -> Bool {
        visibleItems.filter { $0.isPinned == item.isPinned }.last?.id != item.id
    }

    func archive(_ item: LedgerItem) {
        mutateItem(item.id) { $0.isArchived = true }
        clearSelection()
        hooks.onArchive(item.id)
    }

    func setDueDate(_ date: Date?, for item: LedgerItem) {
        mutateItem(item.id) {
            $0.kind = .task
            $0.dueDate = date
        }
        hooks.onSetDueDate(item.id, date)
    }

    func updateShortcut(_ action: Shortcut.Action, displayValue: String) {
        guard let index = shortcuts.firstIndex(where: { $0.action == action }) else { return }
        shortcuts[index].displayValue = displayValue
    }

    func move(_ item: LedgerItem, to list: String) {
        mutateItem(item.id) { $0.listName = list }
        hooks.onMove(item.id, list)
    }

    func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Give the list a name."
            return
        }
        guard !lists.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            errorMessage = "That list already exists."
            return
        }
        hooks.onCreateList(name)
        newListName = ""
    }

    func trash(_ item: LedgerItem) {
        mutateItem(item.id) { $0.isTrashed = true }
        clearSelection()
        hooks.onTrash(item.id)
    }

    func restore(_ item: LedgerItem) {
        mutateItem(item.id) { $0.isTrashed = false }
        hooks.onRestore(item.id)
    }

    func deletePermanently(_ item: LedgerItem) {
        items.removeAll { $0.id == item.id }
        clearSelection()
        hooks.onDeletePermanently(item.id)
    }

    func beginDrop() {
        if surfaceState == .expanded { surfaceState = .drop }
    }

    func endDrop() {
        if surfaceState == .drop { surfaceState = .expanded }
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        hooks.onDroppedProviders(providers)
        endDrop()
        return true
    }

    func beginScreenshot() {
        surfaceState = .screenshot
        hooks.onBeginScreenshot()
    }

    private var shouldYieldIdleSurface: Bool {
        ownership == .companion || (ownership == .automatic && isNotchFlowRunning)
    }

    private var normalizedComposerText: String {
        composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesFilter(_ item: LedgerItem) -> Bool {
        switch filter {
        case .all:
            !item.isArchived && !item.isTrashed && (
                !item.isCompleted || item.completedAt.map {
                    CompletionVisibility.remainsOnMainPage(completedAt: $0)
                } == true
            )
        case .tasks:
            item.kind == .task && !item.isArchived && !item.isTrashed && !item.isCompleted
        case .due:
            item.dueDate != nil && !item.isArchived && !item.isTrashed && !item.isCompleted
        case .completed:
            item.isCompleted && !item.isTrashed
        case .archive:
            item.isArchived && !item.isTrashed
        case .trash:
            item.isTrashed
        }
    }

    private func activityDate(for item: LedgerItem) -> Date {
        item.completedAt ?? item.createdAt
    }

    private func itemComesBefore(_ lhs: LedgerItem, _ rhs: LedgerItem) -> Bool {
        switch (lhs.sortOrder, rhs.sortOrder) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        default:
            let leftDate = activityDate(for: lhs)
            let rightDate = activityDate(for: rhs)
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func mutateItem(_ id: UUID, mutation: (inout LedgerItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutation(&items[index])
    }

    private func clearSelection() {
        selectedItemID = nil
        keyboardFocus = .none
    }
}

extension AppViewModel {
    static var preview: AppViewModel {
        let calendar = Calendar.current
        let today = Date.now
        let thumbnailURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Design/reference-thumbnail.png")
        let pinned = LedgerItem(
            title: "Review launch notes",
            detail: "Selected from Safari",
            createdAt: calendar.date(bySettingHour: 10, minute: 32, second: 0, of: today) ?? today,
            isPinned: true
        )
        let selectedTask = LedgerItem(
            kind: .task,
            title: "Book studio time",
            createdAt: calendar.date(bySettingHour: 9, minute: 42, second: 0, of: today) ?? today,
            dueDate: today
        )
        let model = AppViewModel(
            surfaceState: .expanded,
            items: [
                pinned,
                LedgerItem(
                    title: "IMG_2147.jpg",
                    createdAt: calendar.date(bySettingHour: 9, minute: 36, second: 0, of: today) ?? today,
                    attachments: [
                        LedgerAttachment(
                            kind: .image,
                            name: "IMG_2147.jpg",
                            subtitle: "1.2 MB",
                            previewURL: thumbnailURL
                        )
                    ]
                ),
                LedgerItem(
                    title: "cal.com/studio",
                    createdAt: calendar.date(bySettingHour: 9, minute: 28, second: 0, of: today) ?? today,
                    attachments: [
                        LedgerAttachment(
                            kind: .link,
                            name: "cal.com/studio",
                            previewURL: URL(string: "https://cal.com/studio")
                        )
                    ]
                ),
                selectedTask
            ],
            accessibilityGranted: true
        )
        model.selectedItemID = selectedTask.id
        return model
    }
}
