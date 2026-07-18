import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

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

    enum TimeFormat: String, CaseIterable, Identifiable {
        case twelveHour = "12-hour"
        case twentyFourHour = "24-hour"

        var id: Self { self }
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
        case itemEditor
        case none
    }

    enum BrowseLocation: Hashable {
        case root
        case folder(UUID)
    }

    struct FolderSummary: Identifiable, Hashable {
        var id: UUID
        var name: String
        var sortOrder: Int

        init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
        }
    }

    struct TagSummary: Identifiable, Hashable {
        var id: UUID
        var name: String
        var colorSeed: Double

        init(id: UUID = UUID(), name: String, colorSeed: Double? = nil) {
            self.id = id
            self.name = name
            self.colorSeed = colorSeed ?? TagColorSeed.stable(for: id)
        }
    }

    struct TagGroup: Identifiable, Hashable {
        var tag: TagSummary
        var count: Int

        var id: UUID { tag.id }
        var name: String { tag.name }
    }

    enum TagSuggestion: Identifiable, Hashable {
        case existing(TagGroup)
        case create(String)

        var id: String {
            switch self {
            case let .existing(group): "tag-\(group.id.uuidString)"
            case let .create(name): "create-\(CaptureTagParser.normalize(name))"
            }
        }

        var name: String {
            switch self {
            case let .existing(group): group.name
            case let .create(name): name
            }
        }
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

        var isImage: Bool {
            kind == .image || kind == .screenshot
        }
    }

    struct LedgerItem: Identifiable, Hashable {
        var id: UUID
        var kind: ItemKind
        var text: String
        var title: String
        var detail: String
        var searchableText: String
        var createdAt: Date
        var dueDate: Date?
        var folderID: UUID?
        var folderName: String?
        var sourceApp: String?
        var isPinned: Bool
        var isCompleted: Bool
        var completedAt: Date?
        var isArchived: Bool
        var isTrashed: Bool
        var sortOrder: Int?
        var tags: [TagSummary]
        var attachments: [LedgerAttachment]

        init(
            id: UUID = UUID(),
            kind: ItemKind = .note,
            title: String,
            detail: String = "",
            text: String? = nil,
            searchableText: String? = nil,
            createdAt: Date = .now,
            dueDate: Date? = nil,
            folderID: UUID? = nil,
            folderName: String? = nil,
            sourceApp: String? = nil,
            isPinned: Bool = false,
            isCompleted: Bool = false,
            completedAt: Date? = nil,
            isArchived: Bool = false,
            isTrashed: Bool = false,
            sortOrder: Int? = nil,
            tags: [TagSummary] = [],
            attachments: [LedgerAttachment] = []
        ) {
            self.id = id
            self.kind = kind
            self.text = text ?? [title, detail].filter { !$0.isEmpty }.joined(separator: "\n")
            self.title = title
            self.detail = detail
            self.searchableText = searchableText ?? CaptureTagParser.removingTagMentions(
                in: [title, detail].filter { !$0.isEmpty }.joined(separator: "\n"),
                matching: tags.map(\.name)
            )
            self.createdAt = createdAt
            self.dueDate = dueDate
            self.folderID = folderID
            self.folderName = folderName
            self.sourceApp = sourceApp
            self.isPinned = isPinned
            self.isCompleted = isCompleted
            self.completedAt = completedAt
            self.isArchived = isArchived
            self.isTrashed = isTrashed
            self.sortOrder = sortOrder
            self.tags = tags
            self.attachments = attachments
        }

        var imageAttachments: [LedgerAttachment] {
            attachments.filter(\.isImage)
        }

        var hasImageAttachments: Bool {
            !imageAttachments.isEmpty
        }

        var displaysOnlyImages: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && tags.isEmpty
                && hasImageAttachments
                && imageAttachments.count == attachments.count
        }

        var displaysAttachmentPrefix: Bool {
            !attachments.isEmpty && !hasImageAttachments
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

    struct ItemEditSession: Equatable {
        let itemID: UUID
        let originalText: String
        var draft: String
    }

    struct ComposerImage: Identifiable, Equatable {
        let id: UUID
        let data: Data
        let typeIdentifier: String
        let filename: String

        init(
            id: UUID = UUID(),
            data: Data,
            typeIdentifier: String,
            filename: String
        ) {
            self.id = id
            self.data = data
            self.typeIdentifier = typeIdentifier
            self.filename = filename
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

    struct ShortcutRecordingRequest: Equatable {
        let action: Shortcut.Action
        let title: String
        let currentValue: String
    }

    struct Hooks {
        var onDismiss: () -> Void = {}
        var onCaptureText: (String, UUID?) -> Void = { _, _ in }
        var onCaptureComposerImages: (String, [ComposerImage], UUID?) -> String? = { _, _, _ in nil }
        var onPastedImageProviders: ([NSItemProvider], UUID) -> Void = { _, _ in }
        var onUndoCapture: (UUID?) -> Void = { _ in }
        var onConfirmationPauseChanged: (Bool, TimeInterval) -> Void = { _, _ in }
        var onToggleComplete: (UUID) -> Void = { _ in }
        var onUpdateText: (UUID, String) -> String? = { _, _ in nil }
        var onTogglePin: (UUID) -> Void = { _ in }
        var onReorder: ([ItemOrderAssignment]) -> Void = { _ in }
        var onArchive: (UUID) -> Void = { _ in }
        var onSetDueDate: (UUID, Date?) -> Void = { _, _ in }
        var onMove: (UUID, UUID?) -> Void = { _, _ in }
        var onCreateFolder: (String) -> Void = { _ in }
        var onRenameFolder: (UUID, String) -> Void = { _, _ in }
        var onDeleteFolder: (UUID) -> Void = { _ in }
        var onCreateTag: (String) -> Void = { _ in }
        var onRenameTag: (UUID, String) -> Void = { _, _ in }
        var onDeleteTag: (UUID) -> Void = { _ in }
        var onTrash: (UUID) -> Void = { _ in }
        var onRestore: (UUID) -> Void = { _ in }
        var onDeletePermanently: (UUID) -> Void = { _ in }
        var onDroppedProviders: ([NSItemProvider]) -> Void = { _ in }
        var onBeginScreenshot: () -> Void = {}
        var onRequestAccessibility: () -> Void = {}
        var onRequestScreenRecording: () -> Void = {}
        var onSetLaunchAtLogin: (Bool) -> Void = { _ in }
        var onSetOwnership: (NotchOwnership) -> Void = { _ in }
        var onSetTimeFormat: (TimeFormat) -> Void = { _ in }
        var onOpenShortcutRecorder: (Shortcut.Action) -> Void = { _ in }
        var onCommitShortcutRecording: (Shortcut.Action, ShortcutRecording) -> String? = { _, _ in nil }
        var onCancelShortcutRecording: () -> Void = {}
        var onImport: () -> Void = {}
        var onExport: () -> Void = {}
        var onQuit: () -> Void = {}
    }

    @Published var surfaceState: SurfaceState
    @Published var items: [LedgerItem]
    @Published var selectedItemID: UUID?
    @Published private(set) var keyboardFocus: KeyboardFocus = .composer
    @Published var browseLocation: BrowseLocation = .root
    @Published var filter: InboxFilter = .all
    @Published var composerText = ""
    @Published private(set) var composerImages: [ComposerImage] = []
    @Published var confirmation: Confirmation?
    @Published var itemEditSession: ItemEditSession?
    @Published var errorMessage: String?
    @Published var folders: [FolderSummary]
    @Published var tags: [TagSummary]
    @Published var newFolderName = ""
    @Published private(set) var selectedTagSuggestionIndex = 0
    @Published private(set) var isTagAutocompleteDismissed = false
    @Published var ownership: NotchOwnership {
        didSet { hooks.onSetOwnership(ownership) }
    }
    @Published var autoHideExternalPill: Bool
    @Published var launchAtLogin: Bool {
        didSet { hooks.onSetLaunchAtLogin(launchAtLogin) }
    }
    @Published var timeFormat: TimeFormat {
        didSet { hooks.onSetTimeFormat(timeFormat) }
    }
    @Published var accessibilityGranted: Bool
    @Published var screenRecordingGranted: Bool
    @Published var onboardingPage = 0
    @Published var isNotchFlowRunning = false
    @Published var shortcuts: [Shortcut]
    @Published var shortcutRecordingRequest: ShortcutRecordingRequest?

    var hooks: Hooks
    private let now: () -> Date
    private var composerDraftID = UUID()

    init(
        surfaceState: SurfaceState = .collapsed,
        items: [LedgerItem] = [],
        folders: [FolderSummary] = [],
        tags: [TagSummary] = [],
        ownership: NotchOwnership = .automatic,
        autoHideExternalPill: Bool = false,
        launchAtLogin: Bool = false,
        timeFormat: TimeFormat = .twelveHour,
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
        self.itemEditSession = nil
        self.folders = folders
        self.tags = tags
        self.ownership = ownership
        self.autoHideExternalPill = autoHideExternalPill
        self.launchAtLogin = launchAtLogin
        self.timeFormat = timeFormat
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
        self.shortcuts = shortcuts
        self.hooks = hooks
        self.now = now
    }

    var visibleItems: [LedgerItem] {
        let query = parsedComposerQuery
        return items
            .filter(matchesFilter)
            .filter(matchesBrowseLocation)
            .filter { item in
                matchesQuery(item, query: query)
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return itemComesBefore(lhs, rhs)
            }
    }

    var pinnedItems: [LedgerItem] { visibleItems.filter(\.isPinned) }
    var unpinnedItems: [LedgerItem] { visibleItems.filter { !$0.isPinned } }

    var visibleFolders: [FolderSummary] {
        guard browseLocation == .root else { return [] }
        let query = parsedComposerQuery
        guard query.tagNames.isEmpty else { return [] }
        return folders
            .filter { folder in
                filter == .all || matchingItemCount(in: folder.id) > 0
            }
            .filter { folder in
                query.text.isEmpty || folder.name.localizedCaseInsensitiveContains(query.text)
            }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var currentFolder: FolderSummary? {
        guard case let .folder(id) = browseLocation else { return nil }
        return folders.first { $0.id == id }
    }

    var navigationTitle: String { currentFolder?.name ?? "Capture" }
    var captureDestinationID: UUID? { currentFolder?.id }
    var captureDestinationName: String { currentFolder?.name ?? "Inbox" }
    var isAtRoot: Bool { browseLocation == .root }
    var isShowingGlobalSearchResults: Bool { isAtRoot && composerHasQuery }
    var canReorderVisibleItems: Bool {
        !isShowingGlobalSearchResults && itemEditSession == nil
    }
    var hasVisibleContent: Bool {
        !visibleTagGroups.isEmpty || !visibleFolders.isEmpty || !visibleItems.isEmpty
    }
    var showsInboxSection: Bool { isAtRoot && !composerHasQuery && !visibleItems.isEmpty }

    var composerHasQuery: Bool { !normalizedComposerText.isEmpty }
    var composerHasImages: Bool { !composerImages.isEmpty }
    var composerHasDraft: Bool { composerHasQuery || composerHasImages }
    var searchMatchCount: Int { visibleFolders.count + visibleItems.count }
    var composerHasMatches: Bool { composerHasQuery && searchMatchCount > 0 }
    var canCreateStandaloneTag: Bool {
        guard !composerHasImages else { return false }
        let query = parsedComposerQuery
        guard query.isTagOnly, query.tagNames.count == 1 else { return false }
        let normalized = CaptureTagParser.normalize(query.tagNames[0])
        return !tags.contains { CaptureTagParser.normalize($0.name) == normalized }
    }
    var composerIsTagOnly: Bool { parsedComposerQuery.isTagOnly }
    var exactComposerTagExists: Bool {
        let query = parsedComposerQuery
        guard query.isTagOnly, query.tagNames.count == 1 else { return false }
        let normalized = CaptureTagParser.normalize(query.tagNames[0])
        return tags.contains { CaptureTagParser.normalize($0.name) == normalized }
    }
    var canAddComposerText: Bool {
        composerHasQuery && searchMatchCount == 0 && !parsedComposerQuery.isTagOnly
    }
    var canSubmitComposer: Bool {
        composerHasImages || canAddComposerText || canCreateStandaloneTag
    }

    var visibleTagGroups: [TagGroup] {
        guard isAtRoot, !composerHasQuery else { return [] }
        return tags.compactMap { tag in
            let count = filteredItemCount(for: tag.id)
            guard filter == .all || count > 0 else { return nil }
            return TagGroup(tag: tag, count: count)
        }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var tagSuggestions: [TagSuggestion] {
        guard !isTagAutocompleteDismissed,
              let fragment = CaptureTagParser.activeTagFragment(in: composerText) else { return [] }
        let normalized = CaptureTagParser.normalize(fragment)
        let matches = tags
            .filter { normalized.isEmpty || CaptureTagParser.normalize($0.name).hasPrefix(normalized) }
            .map { TagGroup(tag: $0, count: filteredItemCount(for: $0.id)) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        let canCreate = !fragment.isEmpty &&
            !tags.contains(where: { CaptureTagParser.normalize($0.name) == normalized })
        let existingLimit = canCreate ? 4 : 5
        var suggestions = matches.prefix(existingLimit).map(TagSuggestion.existing)
        if canCreate {
            suggestions.append(.create(fragment))
        }
        return Array(suggestions.prefix(5))
    }

    func openExpanded() {
        errorMessage = nil
        keyboardFocus = .composer
        surfaceState = .expanded
    }

    func dismiss() {
        itemEditSession = nil
        clearSelection()
        resetComposerDraft()
        errorMessage = nil
        surfaceState = shouldYieldIdleSurface ? .dormant : .collapsed
        hooks.onDismiss()
    }

    func submitComposer() {
        let text = normalizedComposerText
        if composerHasImages {
            errorMessage = nil
            if let persistenceError = hooks.onCaptureComposerImages(
                text,
                composerImages,
                captureDestinationID
            ) {
                errorMessage = persistenceError
                return
            }
            filter = .all
            resetComposerDraft()
            return
        }
        guard !text.isEmpty else {
            return
        }
        if canCreateStandaloneTag {
            let name = parsedComposerQuery.tagNames[0]
            errorMessage = nil
            hooks.onCreateTag(name)
            resetComposerDraft()
            return
        }
        guard canAddComposerText else {
            if let folder = visibleFolders.first {
                openFolder(folder)
            } else if let item = visibleItems.first {
                select(item)
            }
            return
        }
        errorMessage = nil
        filter = .all
        hooks.onCaptureText(text, captureDestinationID)
        resetComposerDraft()
    }

    @discardableResult
    func acceptPastedImages(_ providers: [NSItemProvider]) -> Bool {
        let imageProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !imageProviders.isEmpty else { return false }
        errorMessage = nil
        hooks.onPastedImageProviders(imageProviders, composerDraftID)
        return true
    }

    func appendComposerImages(_ images: [ComposerImage]) {
        guard !images.isEmpty else { return }
        composerImages.append(contentsOf: images)
        errorMessage = nil
        keyboardFocus = .composer
    }

    func appendComposerImages(_ images: [ComposerImage], toComposerDraft draftID: UUID) {
        guard draftID == composerDraftID else { return }
        appendComposerImages(images)
    }

    func showComposerPasteError(_ message: String, forComposerDraft draftID: UUID) {
        guard draftID == composerDraftID else { return }
        errorMessage = message
    }

    func removeComposerImage(id: UUID) {
        composerImages.removeAll { $0.id == id }
        keyboardFocus = .composer
    }

    func composerTextDidChange(from _: String, to _: String) {
        selectedTagSuggestionIndex = 0
        isTagAutocompleteDismissed = false
    }

    @discardableResult
    func acceptSelectedTagSuggestion() -> Bool {
        let suggestions = tagSuggestions
        guard !suggestions.isEmpty else { return false }
        let index = min(selectedTagSuggestionIndex, suggestions.count - 1)
        acceptTagSuggestion(suggestions[index])
        return true
    }

    func handleComposerReturn() {
        if composerIsTagOnly && (canCreateStandaloneTag || exactComposerTagExists) {
            submitComposer()
            return
        }
        if !acceptSelectedTagSuggestion() {
            submitComposer()
        }
    }

    func acceptTagSuggestion(_ suggestion: TagSuggestion) {
        guard let at = composerText.lastIndex(of: "@") else { return }
        composerText.replaceSubrange(at..., with: "@\(suggestion.name) ")
        selectedTagSuggestionIndex = 0
        isTagAutocompleteDismissed = true
    }

    func moveTagSuggestionSelection(by offset: Int) {
        let count = tagSuggestions.count
        guard count > 0 else { return }
        selectedTagSuggestionIndex = (selectedTagSuggestionIndex + offset + count) % count
    }

    func dismissTagAutocomplete() {
        isTagAutocompleteDismissed = true
    }

    func search(for tag: TagSummary) {
        clearSelection()
        browseLocation = .root
        resetComposerDraft()
        composerText = "@\(tag.name) "
        isTagAutocompleteDismissed = true
        keyboardFocus = .composer
    }

    func renameTag(_ tag: TagSummary, to proposedName: String) {
        let name = CaptureTagParser.normalizedDisplayName(proposedName)
        guard !name.isEmpty else {
            errorMessage = "Give the tag a name."
            return
        }
        hooks.onRenameTag(tag.id, name)
    }

    func deleteTag(_ tag: TagSummary) {
        hooks.onDeleteTag(tag.id)
    }

    func totalItemCount(for tagID: UUID) -> Int {
        items.count { item in item.tags.contains { $0.id == tagID } }
    }

    func openFolder(_ folder: FolderSummary) {
        clearSelection()
        resetComposerDraft()
        errorMessage = nil
        browseLocation = .folder(folder.id)
    }

    func openRoot() {
        clearSelection()
        resetComposerDraft()
        errorMessage = nil
        browseLocation = .root
    }

    func reconcileBrowsingLocation() {
        guard case let .folder(id) = browseLocation,
              !folders.contains(where: { $0.id == id }) else { return }
        openRoot()
    }

    func focusComposer() {
        keyboardFocus = .composer
    }

    func beginEditing(_ item: LedgerItem) {
        guard !item.text.isEmpty else { return }
        selectedItemID = item.id
        keyboardFocus = .itemEditor
        errorMessage = nil
        itemEditSession = ItemEditSession(
            itemID: item.id,
            originalText: item.text,
            draft: item.text
        )
    }

    func updateEditingDraft(_ draft: String) {
        guard var session = itemEditSession else { return }
        session.draft = draft
        itemEditSession = session
    }

    @discardableResult
    func saveEditing(resumeRowFocus: Bool = true) -> Bool {
        guard let session = itemEditSession,
              let item = items.first(where: { $0.id == session.itemID }) else {
            itemEditSession = nil
            return true
        }
        guard !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !item.attachments.isEmpty else {
            errorMessage = ItemRepositoryError.emptyCapture.localizedDescription
            selectedItemID = session.itemID
            keyboardFocus = .itemEditor
            return false
        }

        errorMessage = nil
        if let persistenceError = hooks.onUpdateText(session.itemID, session.draft) {
            errorMessage = persistenceError
            selectedItemID = session.itemID
            keyboardFocus = .itemEditor
            return false
        }

        applyEditedText(session.draft, to: session.itemID)
        itemEditSession = nil
        if resumeRowFocus {
            selectedItemID = session.itemID
            keyboardFocus = .selectedRow
        } else if keyboardFocus == .itemEditor {
            keyboardFocus = .none
        }
        return true
    }

    func cancelEditing() {
        guard let session = itemEditSession else { return }
        itemEditSession = nil
        selectedItemID = session.itemID
        keyboardFocus = .selectedRow
        errorMessage = nil
    }

    func handleDismissalRequest(_ reason: PanelDismissalReason) {
        switch reason {
        case .escape:
            if itemEditSession != nil {
                cancelEditing()
            } else if !tagSuggestions.isEmpty {
                dismissTagAutocomplete()
            } else if composerHasDraft {
                clearComposerQuery()
            } else if !isAtRoot {
                openRoot()
                focusComposer()
            } else {
                dismiss()
            }
        case .externalClick where itemEditSession != nil:
            if saveEditing() { dismiss() }
        case .externalClick, .automatic:
            dismiss()
        }
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
        let willComplete = !item.isCompleted
        let animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? NotchMotion.reducedMotion
            : (willComplete ? NotchMotion.completion : NotchMotion.completionReopen)

        withAnimation(animation) {
            mutateItem(item.id) {
                $0.isCompleted.toggle()
                $0.completedAt = $0.isCompleted ? .now : nil
            }
        }
        hooks.onToggleComplete(item.id)
    }

    func togglePin(_ item: LedgerItem) {
        let destinationPinned = !item.isPinned
        let topOrder = (items
            .filter { $0.isPinned == destinationPinned && $0.folderID == item.folderID }
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
        guard canReorderVisibleItems else { return false }
        let sourcePinned = dragged.isPinned
        guard targetID != itemID else { return false }
        if let targetID,
           items.first(where: { $0.id == targetID })?.folderID != dragged.folderID {
            return false
        }

        var destination = items
            .filter {
                $0.folderID == dragged.folderID && $0.isPinned == destinationPinned && $0.id != itemID
            }
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
                    .filter {
                        $0.folderID == dragged.folderID && $0.isPinned == pinnedState && $0.id != itemID
                    }
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

    func move(_ item: LedgerItem, to folderID: UUID?) {
        guard item.folderID != folderID else { return }
        let destinationName = folderID.flatMap { id in folders.first(where: { $0.id == id })?.name }
        let topOrder = (items
            .filter { $0.folderID == folderID && $0.isPinned == item.isPinned }
            .compactMap(\.sortOrder)
            .min() ?? 0) - 1
        mutateItem(item.id) {
            $0.folderID = folderID
            $0.folderName = destinationName
            $0.sortOrder = topOrder
        }
        clearSelection()
        hooks.onMove(item.id, folderID)
    }

    @discardableResult
    func createFolder() -> Bool {
        createFolder(named: newFolderName)
    }

    @discardableResult
    func createFolder(named proposedName: String) -> Bool {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Give the folder a name."
            return false
        }
        guard !folders.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            errorMessage = "That folder already exists."
            return false
        }
        errorMessage = nil
        hooks.onCreateFolder(name)
        newFolderName = ""
        return true
    }

    @discardableResult
    func renameFolder(_ folder: FolderSummary, to proposedName: String) -> Bool {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Give the folder a name."
            return false
        }
        guard !folders.contains(where: {
            $0.id != folder.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            errorMessage = "That folder already exists."
            return false
        }
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index].name = name
        }
        for index in items.indices where items[index].folderID == folder.id {
            items[index].folderName = name
        }
        errorMessage = nil
        hooks.onRenameFolder(folder.id, name)
        return true
    }

    func deleteFolder(_ folder: FolderSummary) {
        for isPinned in [true, false] {
            let contained = items
                .filter { $0.folderID == folder.id && $0.isPinned == isPinned }
                .sorted(by: itemComesBefore)
            let inboxTop = (items
                .filter { $0.folderID == nil && $0.isPinned == isPinned }
                .compactMap(\.sortOrder)
                .min() ?? 0) - 1
            for (offset, containedItem) in contained.enumerated() {
                mutateItem(containedItem.id) {
                    $0.folderID = nil
                    $0.folderName = nil
                    $0.sortOrder = inboxTop - contained.count + offset
                }
            }
        }
        folders.removeAll { $0.id == folder.id }
        if browseLocation == .folder(folder.id) {
            openRoot()
        }
        hooks.onDeleteFolder(folder.id)
    }

    func totalItemCount(in folderID: UUID) -> Int {
        items.count { $0.folderID == folderID }
    }

    func matchingItemCount(in folderID: UUID) -> Int {
        items.count { $0.folderID == folderID && matchesFilter($0) }
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

    private var parsedComposerQuery: ParsedTagText {
        CaptureTagParser.parse(normalizedComposerText)
    }

    private func matchesQuery(_ item: LedgerItem, query: ParsedTagText) -> Bool {
        let textMatches = query.text.isEmpty ||
            item.searchableText.localizedCaseInsensitiveContains(query.text) ||
            item.attachments.contains { $0.name.localizedCaseInsensitiveContains(query.text) }
        guard textMatches else { return false }
        guard !query.tagNames.isEmpty else { return true }
        let requested = Set(query.tagNames.map(CaptureTagParser.normalize))
        return item.tags.contains { requested.contains(CaptureTagParser.normalize($0.name)) }
    }

    private func filteredItemCount(for tagID: UUID) -> Int {
        items.count { item in
            matchesFilter(item) && item.tags.contains { $0.id == tagID }
        }
    }

    private func matchesBrowseLocation(_ item: LedgerItem) -> Bool {
        switch browseLocation {
        case .root:
            return composerHasQuery || item.folderID == nil
        case let .folder(id):
            return item.folderID == id
        }
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

    private func applyEditedText(_ text: String, to itemID: UUID) {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }) else { return }
        let parsed = CaptureTagParser.parse(text)
        var resolvedTags: [TagSummary] = []

        for proposedName in parsed.tagNames {
            let normalized = CaptureTagParser.normalize(proposedName)
            if let existing = tags.first(where: { CaptureTagParser.normalize($0.name) == normalized }) {
                resolvedTags.append(existing)
            } else {
                let created = TagSummary(name: CaptureTagParser.normalizedDisplayName(proposedName))
                tags.append(created)
                resolvedTags.append(created)
            }
        }

        let lines = text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let attachments = items[itemIndex].attachments
        let title = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? attachments.first?.name
            ?? "Untitled capture"

        items[itemIndex].text = text
        items[itemIndex].title = title
        items[itemIndex].detail = lines.dropFirst().joined(separator: "\n")
        items[itemIndex].tags = resolvedTags
        items[itemIndex].searchableText = CaptureTagParser.removingTagMentions(
            in: text,
            matching: resolvedTags.map(\.name)
        )
    }

    private func clearSelection() {
        selectedItemID = nil
        keyboardFocus = .none
    }

    private func clearComposerQuery() {
        clearSelection()
        resetComposerDraft()
        errorMessage = nil
        keyboardFocus = .composer
    }

    private func resetComposerDraft() {
        composerText = ""
        composerImages = []
        composerDraftID = UUID()
        selectedTagSuggestionIndex = 0
        isTagAutocompleteDismissed = false
    }
}

extension AppViewModel {
    static var preview: AppViewModel {
        let calendar = Calendar.current
        let today = Date.now
        let thumbnailURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Design/reference-thumbnail.png")
        let projectsFolder = FolderSummary(name: "Projects", sortOrder: 0)
        let lipeTag = TagSummary(name: "Lipe", colorSeed: 0.02)
        let launchTag = TagSummary(name: "Launch", colorSeed: 0.34)
        let ideasTag = TagSummary(name: "Ideas", colorSeed: 0.70)
        let pinned = LedgerItem(
            title: "Review launch notes",
            detail: "Selected from Safari",
            createdAt: calendar.date(bySettingHour: 10, minute: 32, second: 0, of: today) ?? today,
            isPinned: true,
            tags: [lipeTag, launchTag]
        )
        let selectedTask = LedgerItem(
            kind: .task,
            title: "Book studio time @Lipe",
            createdAt: calendar.date(bySettingHour: 9, minute: 42, second: 0, of: today) ?? today,
            dueDate: today,
            tags: [lipeTag]
        )
        let model = AppViewModel(
            surfaceState: .expanded,
            items: [
                pinned,
                LedgerItem(
                    title: "Projects capture flow",
                    detail: "Folder organization pass",
                    folderID: projectsFolder.id,
                    folderName: projectsFolder.name,
                    sortOrder: 0
                ),
                LedgerItem(
                    title: "IMG_2147.jpg",
                    text: "",
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
                    text: "",
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
            folders: [projectsFolder],
            tags: [lipeTag, launchTag, ideasTag],
            accessibilityGranted: true
        )
        model.selectedItemID = selectedTask.id
        if CommandLine.arguments.contains("--preview-folder-search") {
            model.composerText = "Projects"
        } else if CommandLine.arguments.contains("--preview-folder") {
            model.openFolder(projectsFolder)
        }
        return model
    }
}
