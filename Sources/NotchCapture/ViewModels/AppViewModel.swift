import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    enum ItemKind: String, Codable, Hashable {
        case note
        case task
    }

    enum ComposerCommand: String, CaseIterable, Identifiable, Hashable {
        case folder

        var id: String { rawValue }
        var completion: String { "/\(rawValue) " }
        var title: String {
            switch self {
            case .folder: "Create folder"
            }
        }
        var detail: String {
            switch self {
            case .folder: "Create a top-level folder"
            }
        }
        var icon: String {
            switch self {
            case .folder: "folder.badge.plus"
            }
        }
    }

    enum ReorderPlacement: Hashable {
        case before
        case after
    }

    @Published var surfaceState: SurfaceState
    @Published var items: [LedgerItem] {
        didSet { invalidateDerivedLedger() }
    }
    @Published var selectedItemID: UUID?
    @Published var selectedFolderID: UUID?
    @Published private(set) var keyboardFocus: KeyboardFocus = .composer
    @Published var browseLocation: BrowseLocation = .root {
        didSet { invalidateDerivedLedger() }
    }
    @Published var filter: InboxFilter = .all {
        didSet { invalidateDerivedLedger() }
    }
    @Published var composerText = "" {
        didSet { invalidateDerivedLedger() }
    }
    @Published private(set) var composerImages: [ComposerImage] = []
    @Published var confirmation: Confirmation?
    @Published var itemEditSession: ItemEditSession?
    @Published var errorMessage: String?
    @Published var folders: [FolderSummary] {
        didSet { invalidateDerivedLedger() }
    }
    @Published var tags: [TagSummary] {
        didSet { invalidateDerivedLedger() }
    }
    @Published var newFolderName = ""
    @Published private(set) var selectedTagSuggestionIndex = 0
    @Published private(set) var selectedComposerCommandIndex = 0
    @Published private(set) var isTagAutocompleteDismissed = false
    @Published var autoHideExternalPill: Bool
    @Published var launchAtLogin: Bool {
        didSet { hooks.onSetLaunchAtLogin(launchAtLogin) }
    }
    @Published var timeFormat: TimeFormat {
        didSet { hooks.onSetTimeFormat(timeFormat) }
    }
    @Published var compactPresentationSize: CompactPresentationSize {
        didSet { hooks.onSetCompactPresentationSize(compactPresentationSize) }
    }
    /// False when Sparkle is inert (bare `swift run`, design previews).
    @Published var updatesEnabled = false
    @Published var nowPlaying: NowPlayingSnapshot?
    @Published var nowPlayingArtwork: NSImage?
    @Published var pomodoro: PomodoroState
    @Published var collapsedActivityLayout = CollapsedActivityLayout()
    @Published var isPomodoroCardVisible = false
    @Published var expandedUtilityFocus: UtilityFocus?
    @Published var onboardingStep: OnboardingStep = .welcome
    @Published private(set) var isIdlePillHidden = false
    @Published var shortcuts: [Shortcut]
    @Published var shortcutRecordingRequest: ShortcutRecordingRequest?
    /// Items whose completion is committed but still "held" in place so the
    /// completion choreography (check pop + wash) can land before the row
    /// reorders or leaves the filtered list. Held items keep their pre-completion
    /// filter/sort behavior; persistence is not deferred.
    @Published private(set) var completionHoldIDs: Set<UUID> = [] {
        didSet { invalidateDerivedLedger() }
    }
    private var completionHoldTasks: [UUID: Task<Void, Never>] = [:]

    var hooks: Hooks
    private let now: () -> Date
    private var composerDraftID = UUID()

    /// Memoized derived state. The filter/sort pipeline over all items runs
    /// often (several times per render pass), so it is computed at most once
    /// per mutation of the inputs instead of on every access.
    private var cachedVisibleItems: [LedgerItem]?
    private var cachedVisibleFolders: [FolderSummary]?
    private var cachedVisibleTagGroups: [TagGroup]?
    private var cachedParsedQuery: (source: String, parsed: ParsedTagText)?

    private func invalidateDerivedLedger() {
        cachedVisibleItems = nil
        cachedVisibleFolders = nil
        cachedVisibleTagGroups = nil
    }

    init(
        surfaceState: SurfaceState = .collapsed,
        items: [LedgerItem] = [],
        folders: [FolderSummary] = [],
        tags: [TagSummary] = [],
        autoHideExternalPill: Bool = false,
        launchAtLogin: Bool = false,
        timeFormat: TimeFormat = .twelveHour,
        compactPresentationSize: CompactPresentationSize = .minimal,
        nowPlaying: NowPlayingSnapshot? = nil,
        nowPlayingArtwork: NSImage? = nil,
        pomodoro: PomodoroState = PomodoroState(),
        shortcuts: [Shortcut] = [
            Shortcut(action: .openComposer, title: "Open composer", displayValue: "⌃⇧N")
        ],
        hooks: Hooks = Hooks(),
        now: @escaping () -> Date = { .now }
    ) {
        self.surfaceState = surfaceState
        self.items = items
        self.itemEditSession = nil
        self.folders = folders
        self.tags = tags
        self.autoHideExternalPill = autoHideExternalPill
        self.launchAtLogin = launchAtLogin
        self.timeFormat = timeFormat
        self.compactPresentationSize = compactPresentationSize
        self.nowPlaying = nowPlaying
        self.nowPlayingArtwork = nowPlayingArtwork
        self.pomodoro = pomodoro
        self.expandedUtilityFocus = nil
        self.shortcuts = shortcuts
        self.hooks = hooks
        self.now = now
    }

    var visibleItems: [LedgerItem] {
        if let cachedVisibleItems { return cachedVisibleItems }
        let query = parsedComposerQuery
        let visible = items
            .filter(matchesFilter)
            .filter(matchesBrowseLocation)
            .filter { item in
                matchesQuery(item, query: query)
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return itemComesBefore(lhs, rhs)
            }
        cachedVisibleItems = visible
        return visible
    }

    var pinnedItems: [LedgerItem] { visibleItems.filter(\.isPinned) }
    var unpinnedItems: [LedgerItem] { visibleItems.filter { !$0.isPinned } }

    var visibleFolders: [FolderSummary] {
        if let cachedVisibleFolders { return cachedVisibleFolders }
        let visible = computeVisibleFolders()
        cachedVisibleFolders = visible
        return visible
    }

    private func computeVisibleFolders() -> [FolderSummary] {
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

    /// `/folder` is deliberately a complete command rather than search text.
    /// It must begin the composer text and be followed by whitespace or end of input,
    /// so `/folderish` remains an ordinary capture/search query.
    private var folderCommandName: String? {
        let command = "/folder"
        guard composerText.count >= command.count,
              composerText.prefix(command.count).caseInsensitiveCompare(command) == .orderedSame else {
            return nil
        }
        let remainder = composerText.dropFirst(command.count)
        guard remainder.isEmpty || remainder.first?.isWhitespace == true else { return nil }
        return String(remainder)
    }

    private var slashCommandQuery: String? {
        guard composerText.first == "/" else { return nil }
        let query = String(composerText.dropFirst())
        guard !query.contains(where: \.isWhitespace) else { return nil }
        return query
    }

    var isFolderCommandActive: Bool { folderCommandName != nil }
    var composerCommandSuggestions: [ComposerCommand] {
        guard let query = slashCommandQuery else { return [] }
        guard !query.isEmpty else { return ComposerCommand.allCases }
        return ComposerCommand.allCases.filter {
            $0.rawValue.range(
                of: query,
                options: [.caseInsensitive, .anchored]
            ) != nil
        }
    }
    var composerHasQuery: Bool { !isFolderCommandActive && !normalizedComposerText.isEmpty }
    var composerHasImages: Bool { !composerImages.isEmpty }
    var composerHasDraft: Bool { !normalizedComposerText.isEmpty || composerHasImages }
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
        !isFolderCommandActive && composerHasQuery && searchMatchCount == 0 && !parsedComposerQuery.isTagOnly
    }
    var canSubmitComposer: Bool {
        isFolderCommandActive || composerHasImages || canAddComposerText || canCreateStandaloneTag
    }
    var composerActionLabel: String {
        if isFolderCommandActive { return "Create folder" }
        if canCreateStandaloneTag { return "Create tag" }
        return "Add"
    }

    var visibleTagGroups: [TagGroup] {
        if let cachedVisibleTagGroups { return cachedVisibleTagGroups }
        let groups = computeVisibleTagGroups()
        cachedVisibleTagGroups = groups
        return groups
    }

    private func computeVisibleTagGroups() -> [TagGroup] {
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
        guard !isFolderCommandActive,
              !isTagAutocompleteDismissed,
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

    func advanceOnboarding() {
        guard let next = OnboardingStep(rawValue: onboardingStep.rawValue + 1) else { return }
        onboardingStep = next
    }

    func retreatOnboarding() {
        guard let previous = OnboardingStep(rawValue: onboardingStep.rawValue - 1) else { return }
        onboardingStep = previous
    }

    func finishOnboarding() {
        guard surfaceState == .onboarding else { return }
        hooks.onCompleteOnboarding()
        openExpanded()
    }

    func setIdlePillHidden(_ isHidden: Bool) {
        isIdlePillHidden = isHidden
        guard [.dormant, .collapsed, .collapsedActivity].contains(surfaceState) else { return }
        surfaceState = isHidden ? .dormant : idleSurfaceState
    }

    func dismiss() {
        itemEditSession = nil
        flushCompletionHolds()
        clearSelection()
        resetComposerDraft()
        errorMessage = nil
        surfaceState = isIdlePillHidden ? .dormant : idleSurfaceState
        hooks.onDismiss()
    }

    /// Pass `capturingAnyway` (⌘Return) to create a new item even when the
    /// text matches existing items; plain Return selects the first match.
    func submitComposer(capturingAnyway: Bool = false) {
        if let proposedFolderName = folderCommandName {
            guard let folderID = createFolderAndReturnID(named: proposedFolderName) else { return }
            openCreatedFolder(id: folderID)
            return
        }

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
        let capturesDespiteMatches = capturingAnyway
            && composerHasQuery
            && !parsedComposerQuery.isTagOnly
        guard canAddComposerText || capturesDespiteMatches else {
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
        selectedComposerCommandIndex = 0
        isTagAutocompleteDismissed = false
    }

    @discardableResult
    func acceptSelectedComposerCommand() -> Bool {
        let commands = composerCommandSuggestions
        guard !commands.isEmpty else { return false }
        let index = min(selectedComposerCommandIndex, commands.count - 1)
        acceptComposerCommand(commands[index])
        return true
    }

    func acceptComposerCommand(_ command: ComposerCommand) {
        composerText = command.completion
        selectedComposerCommandIndex = 0
    }

    func moveComposerCommandSelection(by offset: Int) {
        let count = composerCommandSuggestions.count
        guard count > 0 else { return }
        selectedComposerCommandIndex = (selectedComposerCommandIndex + offset + count) % count
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
        if acceptSelectedComposerCommand() { return }
        if isFolderCommandActive {
            submitComposer()
            return
        }
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

    /// Opens a newly created folder without resetting attachment state. This keeps
    /// an in-flight paste tied to the same draft while the command text clears.
    private func openCreatedFolder(id: UUID) {
        clearSelection()
        composerText = ""
        errorMessage = nil
        browseLocation = .folder(id)
        keyboardFocus = .composer
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

    /// The user-configured display value for a shortcut, for labels that must
    /// not go stale when shortcuts are rebound in Settings.
    func shortcutDisplayValue(for action: Shortcut.Action) -> String {
        if let display = shortcuts.first(where: { $0.action == action })?.displayValue,
           !display.isEmpty {
            return display
        }
        return "⌃⇧N"
    }

    func beginEditing(_ item: LedgerItem) {
        // Attachment-only items are editable too: the draft starts empty and
        // becomes the item's caption (saveEditing allows empty text when
        // attachments exist).
        guard !item.text.isEmpty || !item.attachments.isEmpty else { return }
        selectedFolderID = nil
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
        if surfaceState == .pomodoroComplete {
            acknowledgePomodoro()
            surfaceState = isIdlePillHidden ? .dormant : idleSurfaceState
            return
        }
        switch reason {
        case .escape:
            if itemEditSession != nil {
                cancelEditing()
            } else if !tagSuggestions.isEmpty {
                dismissTagAutocomplete()
            } else if keyboardFocus == .selectedRow,
                      selectedItemID != nil || selectedFolderID != nil {
                clearSelection()
                focusComposer()
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
        selectedFolderID = nil
        selectedItemID = item.id
        keyboardFocus = .selectedRow
    }

    private enum LedgerKeyboardRow: Equatable {
        case folder(UUID)
        case item(UUID)
    }

    /// The rows arrow keys walk, in rendered order: folders, then pinned,
    /// then unpinned items.
    private var keyboardNavigationRows: [LedgerKeyboardRow] {
        visibleFolders.map { .folder($0.id) }
            + (pinnedItems + unpinnedItems).map { .item($0.id) }
    }

    private var selectedKeyboardRow: LedgerKeyboardRow? {
        if let selectedFolderID { return .folder(selectedFolderID) }
        if let selectedItemID { return .item(selectedItemID) }
        return nil
    }

    private func applyKeyboardSelection(_ row: LedgerKeyboardRow) {
        switch row {
        case let .folder(id):
            selectedFolderID = id
            selectedItemID = nil
        case let .item(id):
            selectedItemID = id
            selectedFolderID = nil
        }
        keyboardFocus = .selectedRow
    }

    /// Arrow-key navigation over the visible rows in their rendered order.
    /// Moving down from the composer enters the ledger at the first row;
    /// moving up past the first row returns focus to the composer. Returns
    /// false when there is nothing to navigate.
    @discardableResult
    func moveLedgerSelection(by offset: Int) -> Bool {
        let rows = keyboardNavigationRows
        guard !rows.isEmpty else { return false }

        guard keyboardFocus == .selectedRow,
              let selectedKeyboardRow,
              let index = rows.firstIndex(of: selectedKeyboardRow) else {
            guard offset > 0 else { return false }
            applyKeyboardSelection(rows[0])
            return true
        }

        let next = index + offset
        if next < 0 {
            clearSelection()
            focusComposer()
            return true
        }
        guard next < rows.count else { return true }
        applyKeyboardSelection(rows[next])
        return true
    }

    func emptyTrash() {
        // The hook reloads the ledger synchronously, so the trash page's rows
        // leave inside this transaction rather than vanishing.
        withAnimation(ledgerRemovalAnimation) {
            hooks.onEmptyTrash()
        }
    }

    @discardableResult
    func performSelectedRowKeyboardCommand(_ command: LedgerRowKeyboardCommand) -> Bool {
        guard keyboardFocus == .selectedRow else { return false }

        switch command {
        case .moveSelectionUp:
            return moveLedgerSelection(by: -1)
        case .moveSelectionDown:
            return moveLedgerSelection(by: 1)
        case .toggleCompletion:
            if let folder = selectedVisibleFolder {
                openFolder(folder)
                focusComposer()
                return true
            }
            guard let item = selectedVisibleItem else { return false }
            toggleComplete(item)
            return true
        case .moveToTrash:
            // Deleting a folder needs its confirmation dialog; a bare delete
            // key on a selected folder is swallowed rather than destructive.
            if selectedVisibleFolder != nil { return true }
            guard let item = selectedVisibleItem else { return false }
            guard !item.isTrashed else { return true }
            let removedIndex = keyboardNavigationRows.firstIndex(of: .item(item.id))
            trash(item)
            let remainingRows = keyboardNavigationRows
            if let removedIndex, !remainingRows.isEmpty {
                // The row after the deletion slides into the same index. When
                // the last row is removed, keep navigating from its predecessor.
                applyKeyboardSelection(remainingRows[min(removedIndex, remainingRows.count - 1)])
            } else {
                focusComposer()
            }
            return true
        }
    }

    private var selectedVisibleFolder: FolderSummary? {
        guard let selectedFolderID else { return nil }
        return visibleFolders.first { $0.id == selectedFolderID }
    }

    private var selectedVisibleItem: LedgerItem? {
        guard let selectedItemID else { return nil }
        return visibleItems.first { $0.id == selectedItemID }
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

        // Undo during the hold is a clean cancel: the row never moved, so its
        // visuals just retract in place within this transaction.
        if !willComplete { cancelCompletionHold(item.id) }

        withAnimation(animation) {
            mutateItem(item.id) {
                $0.isCompleted.toggle()
                $0.completedAt = $0.isCompleted ? .now : nil
            }
            if willComplete { completionHoldIDs.insert(item.id) }
        }
        hooks.onToggleComplete(item.id)

        if willComplete { scheduleCompletionHoldRelease(item.id) }
    }

    private func scheduleCompletionHoldRelease(_ id: UUID) {
        completionHoldTasks[id]?.cancel()
        completionHoldTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NotchMotion.completionHoldDuration))
            guard !Task.isCancelled else { return }
            self?.releaseCompletionHold(id)
        }
    }

    /// Internal rather than private so tests can drive the release
    /// deterministically instead of awaiting the hold timer.
    func releaseCompletionHold(_ id: UUID) {
        completionHoldTasks[id]?.cancel()
        completionHoldTasks[id] = nil
        guard completionHoldIDs.contains(id) else { return }
        let staysVisible = items.first { $0.id == id }
            .map { matchesFilter($0, ignoringCompletionHold: true) } ?? false
        let animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? NotchMotion.reducedMotion
            : (staysVisible ? NotchMotion.completionSettle : NotchMotion.completionExit)
        withAnimation(animation) {
            _ = completionHoldIDs.remove(id)
        }
    }

    private func cancelCompletionHold(_ id: UUID) {
        completionHoldTasks[id]?.cancel()
        completionHoldTasks[id] = nil
        completionHoldIDs.remove(id)
    }

    private func flushCompletionHolds() {
        for task in completionHoldTasks.values { task.cancel() }
        completionHoldTasks.removeAll()
        completionHoldIDs.removeAll()
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

    /// Folders are a single, flat collection. Reordering only rewrites their
    /// display ranks; it never changes an item's folder membership.
    var canReorderFolders: Bool {
        browseLocation == .root && filter == .all && parsedComposerQuery.text.isEmpty && parsedComposerQuery.tagNames.isEmpty
    }

    @discardableResult
    func reorderFolder(
        folderID: UUID,
        relativeTo targetID: UUID,
        placement: ReorderPlacement
    ) -> Bool {
        guard canReorderFolders, folderID != targetID else { return false }
        var ordered = folders.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == folderID }),
              let originalTargetIndex = ordered.firstIndex(where: { $0.id == targetID }) else { return false }

        let dragged = ordered.remove(at: sourceIndex)
        let targetIndex = originalTargetIndex > sourceIndex ? originalTargetIndex - 1 : originalTargetIndex
        ordered.insert(dragged, at: targetIndex + (placement == .after ? 1 : 0))

        let assignments = ordered.enumerated().map { index, folder in
            FolderOrderAssignment(id: folder.id, sortOrder: index)
        }
        guard assignments.contains(where: { assignment in
            folders.first(where: { $0.id == assignment.id })?.sortOrder != assignment.sortOrder
        }) else { return false }

        let orderByID = Dictionary(uniqueKeysWithValues: assignments.map { ($0.id, $0.sortOrder) })
        for index in folders.indices {
            if let order = orderByID[folders[index].id] { folders[index].sortOrder = order }
        }
        hooks.onReorderFolders(assignments)
        return true
    }

    func archive(_ item: LedgerItem) {
        withAnimation(ledgerRemovalAnimation) {
            cancelCompletionHold(item.id)
            mutateItem(item.id) { $0.isArchived = true }
        }
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
        withAnimation(ledgerRemovalAnimation) {
            mutateItem(item.id) {
                $0.folderID = folderID
                $0.folderName = destinationName
                $0.sortOrder = topOrder
            }
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
        createFolderAndReturnID(named: proposedName) != nil
    }

    private func createFolderAndReturnID(named proposedName: String) -> UUID? {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Give the folder a name."
            return nil
        }
        guard !folders.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            errorMessage = "That folder already exists."
            return nil
        }
        errorMessage = nil
        guard let folderID = hooks.onCreateFolder(name) else {
            if errorMessage == nil {
                errorMessage = "Could not create the folder."
            }
            return nil
        }
        // The coordinator reloads synchronously. Keep test and alternate hook
        // implementations coherent if they return an ID before updating folders.
        if !folders.contains(where: { $0.id == folderID }) {
            let nextOrder = (folders.map(\.sortOrder).max() ?? -1) + 1
            folders.append(FolderSummary(id: folderID, name: name, sortOrder: nextOrder))
        }
        newFolderName = ""
        return folderID
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
        withAnimation(ledgerRemovalAnimation) {
            cancelCompletionHold(item.id)
            mutateItem(item.id) { $0.isTrashed = true }
        }
        clearSelection()
        hooks.onTrash(item.id)
    }

    func restore(_ item: LedgerItem) {
        withAnimation(ledgerRemovalAnimation) {
            mutateItem(item.id) { $0.isTrashed = false }
        }
        hooks.onRestore(item.id)
    }

    func deletePermanently(_ item: LedgerItem) {
        withAnimation(ledgerRemovalAnimation) {
            cancelCompletionHold(item.id)
            items.removeAll { $0.id == item.id }
        }
        clearSelection()
        hooks.onDeletePermanently(item.id)
    }

    /// Removals share one motion so a row leaving for any non-completion reason
    /// (trash, archive, move, restore) dissolves while the list closes the gap.
    private var ledgerRemovalAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? NotchMotion.reducedMotion
            : NotchMotion.ledgerRemoval
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

    var hasLiveActivity: Bool {
        nowPlaying != nil || pomodoro.isActive
    }

    var idleSurfaceState: SurfaceState {
        hasLiveActivity ? .collapsedActivity : .collapsed
    }

    var collapsedActivityContent: CollapsedActivityContent? {
        switch (nowPlaying, pomodoro.isActive) {
        case let (snapshot?, true): .both(snapshot, pomodoro)
        case let (snapshot?, false): .musicOnly(snapshot)
        case (nil, true): .pomodoroOnly(pomodoro)
        case (nil, false): nil
        }
    }

    func musicPlayPause() { hooks.onMusicPlayPause() }
    func musicNext() { hooks.onMusicNext() }
    func musicPrevious() { hooks.onMusicPrevious() }
    func musicSeek(to position: TimeInterval) { hooks.onMusicSeek(position) }

    func togglePomodoro() {
        isPomodoroCardVisible = true
        hooks.onPomodoroToggle()
    }

    func resetPomodoro() { hooks.onPomodoroReset() }
    func setPomodoroDuration(_ duration: TimeInterval) { hooks.onPomodoroSetDuration(duration) }

    func acknowledgePomodoro() {
        hooks.onPomodoroAcknowledge()
    }

    private var normalizedComposerText: String {
        composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedComposerQuery: ParsedTagText {
        guard !isFolderCommandActive else { return CaptureTagParser.parse("") }
        let source = normalizedComposerText
        if let cachedParsedQuery, cachedParsedQuery.source == source {
            return cachedParsedQuery.parsed
        }
        let parsed = CaptureTagParser.parse(source)
        cachedParsedQuery = (source, parsed)
        return parsed
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
        matchesFilter(item, ignoringCompletionHold: false)
    }

    private func matchesFilter(_ item: LedgerItem, ignoringCompletionHold: Bool) -> Bool {
        // A held item stays on completion-excluding pages until the completion
        // choreography releases it; the release itself asks where the item
        // truly belongs by ignoring the hold.
        let heldOpen = !ignoringCompletionHold && completionHoldIDs.contains(item.id)
        return switch filter {
        case .all:
            !item.isArchived && !item.isTrashed && (
                !item.isCompleted || item.completedAt.map {
                    CompletionVisibility.remainsOnMainPage(completedAt: $0)
                } == true
            )
        case .tasks:
            item.kind == .task && !item.isArchived && !item.isTrashed
                && (!item.isCompleted || heldOpen)
        case .due:
            item.dueDate != nil && !item.isArchived && !item.isTrashed
                && (!item.isCompleted || heldOpen)
        case .completed:
            item.isCompleted && !item.isTrashed
        case .archive:
            item.isArchived && !item.isTrashed
        case .trash:
            item.isTrashed
        }
    }

    private func activityDate(for item: LedgerItem) -> Date {
        // Freeze the sort key while the completion hold is active so the row
        // doesn't jump position until the choreography releases it.
        if completionHoldIDs.contains(item.id) { return item.createdAt }
        return item.completedAt ?? item.createdAt
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
        selectedFolderID = nil
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
        selectedComposerCommandIndex = 0
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
            nowPlaying: NowPlayingSnapshot(
                source: .spotify,
                trackKey: "preview-night-drive",
                title: "Night Drive",
                artist: "Cannons",
                album: "Fever Dream",
                duration: 214,
                isPlaying: true,
                position: 82,
                positionAnchor: .now,
                artworkURL: nil
            ),
            nowPlayingArtwork: NSImage(contentsOf: thumbnailURL),
            pomodoro: PomodoroState(
                duration: 25 * 60,
                phase: .running(endsAt: .now.addingTimeInterval(24 * 60 + 23))
            )
        )
        if let compactSizeArgument = CommandLine.arguments.first(where: {
            $0.hasPrefix("--preview-compact-size=")
        }) {
            let value = String(compactSizeArgument.dropFirst("--preview-compact-size=".count))
            model.compactPresentationSize = CompactPresentationSize.fromStoredValue(value)
        }
        model.selectedItemID = selectedTask.id
        if CommandLine.arguments.contains("--preview-music-only") {
            model.pomodoro = PomodoroState(duration: 25 * 60)
        } else if CommandLine.arguments.contains("--preview-pomodoro-only") {
            model.nowPlaying = nil
            model.nowPlayingArtwork = nil
        }
        if CommandLine.arguments.contains("--preview-music-paused"),
           var snapshot = model.nowPlaying {
            snapshot.isPlaying = false
            snapshot.positionAnchor = .now
            model.nowPlaying = snapshot
        }
        if CommandLine.arguments.contains("--preview-pomodoro-paused") {
            model.pomodoro.phase = .paused(remaining: 24 * 60 + 23)
        }
        if CommandLine.arguments.contains("--preview-completed-item"),
           let index = model.items.firstIndex(where: { $0.id == selectedTask.id }) {
            model.items[index].isCompleted = true
            model.items[index].completedAt = .now
        }
        if CommandLine.arguments.contains("--preview-empty-search") {
            model.composerText = "No matching capture"
        } else if CommandLine.arguments.contains("--preview-folder-search") {
            model.composerText = "Projects"
        } else if CommandLine.arguments.contains("--preview-folder") {
            model.openFolder(projectsFolder)
        }
        return model
    }
}
