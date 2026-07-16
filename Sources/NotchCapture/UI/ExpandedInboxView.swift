import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct LedgerReorderTarget: Equatable {
    let targetID: UUID?
    let placement: AppViewModel.ReorderPlacement
    let destinationPinned: Bool
}

struct LedgerReorderSession: Equatable {
    let draggedItemID: UUID
    var reorderTarget: LedgerReorderTarget?
    var targetedFolderID: UUID?

    init(
        draggedItemID: UUID,
        reorderTarget: LedgerReorderTarget? = nil,
        targetedFolderID: UUID? = nil
    ) {
        self.draggedItemID = draggedItemID
        self.reorderTarget = reorderTarget
        self.targetedFolderID = targetedFolderID
    }

    func previewing(_ items: [AppViewModel.LedgerItem]) -> [AppViewModel.LedgerItem] {
        guard targetedFolderID == nil,
              let reorderTarget,
              reorderTarget.targetID != draggedItemID,
              let dragged = items.first(where: { $0.id == draggedItemID }) else {
            return items
        }

        var preview = items.filter { $0.id != draggedItemID }
        let insertionIndex: Int

        if let targetID = reorderTarget.targetID {
            guard let targetIndex = preview.firstIndex(where: {
                $0.id == targetID && $0.isPinned == reorderTarget.destinationPinned
            }) else { return items }
            insertionIndex = targetIndex + (reorderTarget.placement == .after ? 1 : 0)
        } else {
            let destinationIndices = preview.indices.filter {
                preview[$0].isPinned == reorderTarget.destinationPinned
            }
            if reorderTarget.placement == .before {
                insertionIndex = destinationIndices.first
                    ?? (reorderTarget.destinationPinned ? preview.startIndex : preview.endIndex)
            } else {
                insertionIndex = destinationIndices.last.map { $0 + 1 }
                    ?? (reorderTarget.destinationPinned ? preview.startIndex : preview.endIndex)
            }
        }

        var moved = dragged
        moved.isPinned = reorderTarget.destinationPinned
        preview.insert(moved, at: insertionIndex)
        return preview
    }
}

private struct LedgerInsertionIndicator: View {
    let placement: AppViewModel.ReorderPlacement?

    var body: some View {
        GeometryReader { proxy in
            if let placement {
                Rectangle()
                    .fill(NotchTheme.mint)
                    .frame(height: 2)
                    .shadow(color: NotchTheme.mint.opacity(0.45), radius: 3)
                    .offset(y: placement == .after ? max(0, proxy.size.height - 2) : 0)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LedgerDragPreview: View {
    let item: AppViewModel.LedgerItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .task ? "checkmark.circle" : "note.text")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(NotchTheme.secondaryText)
            Text(item.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .frame(width: 330, height: 48)
        .background(NotchTheme.raisedGraphite.opacity(0.98))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 12, y: 7)
    }
}

private struct IridescentTagLabel: View {
    let name: String
    let count: Int?
    let colorSeed: Double
    var compact = false

    private var gradient: LinearGradient {
        NotchTheme.tagIridescence(seed: colorSeed)
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            Text("@\(name)")
            if let count {
                Text("\(count)")
                    .opacity(0.62)
            }
        }
        .font(.system(size: compact ? 9.5 : 10.5, weight: .medium))
        .foregroundStyle(gradient)
        .frame(height: compact ? 20 : 28)
        .notchHitTarget(Rectangle())
    }
}

enum LedgerDragRegion: Hashable {
    case feed
    case row(UUID)
    case folder(UUID)
    case section(isPinned: Bool)
}

enum LedgerDragDestination: Equatable {
    case reorder(LedgerReorderTarget)
    case folder(UUID)
}

struct LedgerDragResolver {
    static func destination(
        at location: CGPoint,
        regions: [LedgerDragRegion: CGRect],
        items: [AppViewModel.LedgerItem],
        draggedItemID: UUID?,
        currentTarget: LedgerReorderTarget?
    ) -> LedgerDragDestination? {
        guard regions[.feed]?.contains(location) == true else { return nil }

        for (region, frame) in regions where frame.contains(location) {
            if case let .folder(folderID) = region {
                return .folder(folderID)
            }
        }

        for (region, frame) in regions where frame.contains(location) {
            guard case let .row(itemID) = region else { continue }
            if itemID == draggedItemID {
                return currentTarget.map(LedgerDragDestination.reorder)
            }
            guard let item = items.first(where: { $0.id == itemID }) else { continue }
            return .reorder(LedgerReorderTarget(
                targetID: itemID,
                placement: location.y < frame.midY ? .before : .after,
                destinationPinned: item.isPinned
            ))
        }

        for (region, frame) in regions where frame.contains(location) {
            if case let .section(isPinned) = region {
                return .reorder(LedgerReorderTarget(
                    targetID: nil,
                    placement: .before,
                    destinationPinned: isPinned
                ))
            }
        }

        return currentTarget.map(LedgerDragDestination.reorder)
    }
}

private struct LedgerDragRegionPreferenceKey: PreferenceKey {
    static let defaultValue: [LedgerDragRegion: CGRect] = [:]

    static func reduce(
        value: inout [LedgerDragRegion: CGRect],
        nextValue: () -> [LedgerDragRegion: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private extension View {
    func ledgerDragRegion(_ region: LedgerDragRegion) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LedgerDragRegionPreferenceKey.self,
                    value: [region: proxy.frame(in: .named("ledger-feed"))]
                )
            }
        }
    }
}

struct ExpandedInboxView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var focusedField: Field?
    @Namespace private var filterSelection
    @GestureState private var isReorderGestureActive = false
    @State private var reorderSession: LedgerReorderSession?
    @State private var dragRegions: [LedgerDragRegion: CGRect] = [:]
    @State private var dragLocation: CGPoint?
    @State private var dragGrabOffset: CGSize?
    @State private var isCreatingFolder = false
    @State private var folderBeingRenamed: AppViewModel.FolderSummary?
    @State private var renameFolderName = ""
    @State private var folderPendingDeletion: AppViewModel.FolderSummary?
    @State private var tagBeingRenamed: AppViewModel.TagSummary?
    @State private var renameTagName = ""
    @State private var tagPendingDeletion: AppViewModel.TagSummary?

    private let floatingComposerMargin: CGFloat = 18
    private let floatingComposerHeight: CGFloat = 52
    private let floatingGlassHeight: CGFloat = 134
    private let ledgerBottomClearance: CGFloat = 96

    private var draggedItemID: UUID? { reorderSession?.draggedItemID }
    private var reorderTarget: LedgerReorderTarget? { reorderSession?.reorderTarget }
    private var targetedFolderID: UUID? { reorderSession?.targetedFolderID }
    private var previewVisibleItems: [AppViewModel.LedgerItem] {
        reorderSession?.previewing(viewModel.visibleItems) ?? viewModel.visibleItems
    }
    private var previewPinnedItems: [AppViewModel.LedgerItem] {
        previewVisibleItems.filter(\.isPinned)
    }
    private var previewUnpinnedItems: [AppViewModel.LedgerItem] {
        previewVisibleItems.filter { !$0.isPinned }
    }
    private var draggedItem: AppViewModel.LedgerItem? {
        guard let draggedItemID else { return nil }
        return viewModel.items.first { $0.id == draggedItemID }
    }
    private var dragPreviewPosition: CGPoint? {
        guard let dragLocation, let dragGrabOffset else { return nil }
        return CGPoint(
            x: dragLocation.x - dragGrabOffset.width + 165,
            y: dragLocation.y - min(dragGrabOffset.height, 48) + 24
        )
    }

    private enum Field {
        case unifiedInput
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                filterBar
                ledgerBody
            }

            floatingComposer
        }
        .frame(width: NotchTheme.width, height: NotchTheme.maxHeight)
        .background(NotchSurfaceBackground())
        .clipShape(NotchHugShape(bottomRadius: 22))
        .overlay {
            if viewModel.surfaceState == .drop {
                DropTargetOverlay()
                    .transition(dropTransition)
            }
        }
        .onDrop(of: acceptedDropTypes, isTargeted: dropTargetBinding) { providers in
            viewModel.acceptDrop(providers)
        }
        .onExitCommand {
            if !viewModel.tagSuggestions.isEmpty {
                viewModel.dismissTagAutocomplete()
                return
            }
            if reorderSession != nil {
                resetReorderState()
                return
            }
            if viewModel.isAtRoot {
                viewModel.dismiss()
            } else {
                navigate { viewModel.openRoot() }
            }
        }
        .onAppear { focusComposer() }
        .onDisappear { resetReorderState() }
        .onChange(of: viewModel.surfaceState) { _, state in
            if state == .expanded {
                focusComposer()
            } else {
                resetReorderState()
            }
        }
        .onChange(of: focusedField) { _, field in
            if field == .unifiedInput {
                viewModel.focusComposer()
            }
        }
        .onChange(of: viewModel.keyboardFocus) { _, focus in
            if focus == .selectedRow {
                focusedField = nil
            }
        }
        .onChange(of: viewModel.composerText) { oldValue, newValue in
            let event = NSApp.currentEvent
            let isReturnKey = event?.type == .keyDown && (event?.keyCode == 36 || event?.keyCode == 76)
            viewModel.composerTextDidChange(
                from: oldValue,
                to: newValue,
                submittedByReturnKey: isReturnKey
            )
        }
        .onChange(of: isReorderGestureActive) { wasActive, isActive in
            if wasActive, !isActive, reorderSession != nil, dragLocation != nil {
                resetReorderState()
            }
        }
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $viewModel.newFolderName)
            Button("Cancel", role: .cancel) { viewModel.newFolderName = "" }
            Button("Create") { _ = viewModel.createFolder() }
        } message: {
            Text("Create a folder to group related captures.")
        }
        .alert("Rename Folder", isPresented: renameAlertBinding) {
            TextField("Folder name", text: $renameFolderName)
            Button("Cancel", role: .cancel) { folderBeingRenamed = nil }
            Button("Rename") {
                if let folderBeingRenamed {
                    _ = viewModel.renameFolder(folderBeingRenamed, to: renameFolderName)
                }
                folderBeingRenamed = nil
            }
        }
        .confirmationDialog(
            "Delete \(folderPendingDeletion?.name ?? "folder")?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folderPendingDeletion {
                    viewModel.deleteFolder(folderPendingDeletion)
                }
                folderPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { folderPendingDeletion = nil }
        } message: {
            let count = folderPendingDeletion.map { viewModel.totalItemCount(in: $0.id) } ?? 0
            Text("\(count) \(count == 1 ? "item" : "items") will return to Inbox. Nothing will be deleted.")
        }
        .alert("Rename Tag", isPresented: renameTagAlertBinding) {
            TextField("Tag name", text: $renameTagName)
            Button("Cancel", role: .cancel) { tagBeingRenamed = nil }
            Button("Rename") {
                if let tagBeingRenamed {
                    viewModel.renameTag(tagBeingRenamed, to: renameTagName)
                }
                tagBeingRenamed = nil
            }
        } message: {
            Text("Spaces become hyphens. Renaming to an existing tag merges both groups.")
        }
        .confirmationDialog(
            "Delete @\(tagPendingDeletion?.name ?? "tag")?",
            isPresented: deleteTagConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Tag", role: .destructive) {
                if let tagPendingDeletion {
                    viewModel.deleteTag(tagPendingDeletion)
                }
                tagPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { tagPendingDeletion = nil }
        } message: {
            let count = tagPendingDeletion.map { viewModel.totalItemCount(for: $0.id) } ?? 0
            Text("The tag will be removed from \(count) \(count == 1 ? "item" : "items"). No items will be deleted.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch Capture inbox")
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { folderBeingRenamed != nil },
            set: { if !$0 { folderBeingRenamed = nil } }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { folderPendingDeletion != nil },
            set: { if !$0 { folderPendingDeletion = nil } }
        )
    }

    private var renameTagAlertBinding: Binding<Bool> {
        Binding(
            get: { tagBeingRenamed != nil },
            set: { if !$0 { tagBeingRenamed = nil } }
        )
    }

    private var deleteTagConfirmationBinding: Binding<Bool> {
        Binding(
            get: { tagPendingDeletion != nil },
            set: { if !$0 { tagPendingDeletion = nil } }
        )
    }

    private var floatingComposer: some View {
        ZStack(alignment: .bottom) {
            floatingGlassFade

            VStack(spacing: 6) {
                if !viewModel.tagSuggestions.isEmpty {
                    tagAutocomplete
                }
                captureField
            }
            .padding(.horizontal, floatingComposerMargin)
            .padding(.bottom, floatingComposerMargin)
        }
        .frame(maxWidth: .infinity)
        .zIndex(1)
    }

    @ViewBuilder
    private var floatingGlassFade: some View {
        ZStack {
            if reduceTransparency {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: NotchTheme.graphite.opacity(0.72), location: 0.42),
                        .init(color: NotchTheme.ink, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.22), location: 0.28),
                                .init(color: .black.opacity(0.78), location: 0.64),
                                .init(color: .black, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: NotchTheme.graphite.opacity(0.38), location: 0.44),
                        .init(color: NotchTheme.ink.opacity(0.92), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(height: floatingGlassHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if !viewModel.isAtRoot {
                    Button {
                        navigate { viewModel.openRoot() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(PressableIconButtonStyle())
                    .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .help("Back to Inbox")
                    .accessibilityLabel("Back to Inbox")
                }

                Text(viewModel.navigationTitle)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)

                Spacer()

                if viewModel.isAtRoot {
                    Button {
                        viewModel.newFolderName = ""
                        isCreatingFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 13, weight: .regular))
                    }
                    .buttonStyle(PressableIconButtonStyle())
                    .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .help("New folder")
                    .accessibilityLabel("Create a new folder")
                } else if let folder = viewModel.currentFolder {
                    Menu {
                        Button {
                            beginRenaming(folder)
                        } label: {
                            Label("Rename Folder", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            folderPendingDeletion = folder
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 28)
                    .help("Folder actions")
                    .accessibilityLabel("Actions for \(folder.name)")
                }

                Button {
                    viewModel.beginScreenshot()
                } label: {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 13, weight: .regular))
                }
                .buttonStyle(PressableIconButtonStyle())
                .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help("Capture screen region · ⌃⇧S")
                .accessibilityLabel("Capture a screen region")

                Button {
                    viewModel.surfaceState = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .regular))
                }
                .buttonStyle(PressableIconButtonStyle())
                .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help("Settings")
                .accessibilityLabel("Open settings")
            }
            .frame(height: 54)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .background(NotchTheme.ink)
    }

    private func navigate(_ update: () -> Void) {
        if reduceMotion {
            update()
        } else {
            withAnimation(NotchMotion.filter, update)
        }
        resetReorderState()
    }

    private func beginRenaming(_ folder: AppViewModel.FolderSummary) {
        renameFolderName = folder.name
        folderBeingRenamed = folder
    }

    private var captureField: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: reduceMotion || focusedField != .unifiedInput
            )
        ) { context in
            let angle = composerIridescenceAngle(at: context.date)

            captureFieldContent
                .background {
                    composerBackground(angle: angle)
                }
                .clipShape(composerShape)
                .overlay {
                    composerBorder(angle: angle)
                }
        }
        .contentShape(composerShape)
        .shadow(color: .black.opacity(0.42), radius: 14, y: 8)
    }

    private var captureFieldContent: some View {
        HStack(spacing: 13) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(NotchTheme.secondaryText)
                .frame(width: 24, height: 24)

            TextField("Search or add to \(viewModel.captureDestinationName)", text: $viewModel.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1...2)
                .focused($focusedField, equals: .unifiedInput)
                .onKeyPress(.tab) {
                    viewModel.acceptSelectedTagSuggestion() ? .handled : .ignored
                }
                .onKeyPress(.upArrow) {
                    guard !viewModel.tagSuggestions.isEmpty else { return .ignored }
                    viewModel.moveTagSuggestionSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard !viewModel.tagSuggestions.isEmpty else { return .ignored }
                    viewModel.moveTagSuggestionSelection(by: 1)
                    return .handled
                }
                .accessibilityLabel("Search or add to \(viewModel.captureDestinationName)")
                .accessibilityHint(unifiedInputHint)

            if viewModel.canAddComposerText || viewModel.canCreateStandaloneTag {
                Button {
                    viewModel.submitComposer()
                } label: {
                    HStack(spacing: 5) {
                        Text(viewModel.canCreateStandaloneTag ? "Create tag" : "Add")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "return")
                            .font(.system(size: 11, weight: .regular))
                    }
                    .foregroundStyle(NotchTheme.mint)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(NotchTheme.mint.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(NotchPressButtonStyle())
                .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .keyboardShortcut(.return, modifiers: .command)
                .help(
                    viewModel.canCreateStandaloneTag
                        ? "Create this tag group"
                        : "Add this thought to \(viewModel.captureDestinationName)"
                )
                .accessibilityLabel(
                    viewModel.canCreateStandaloneTag
                        ? "Create tag group"
                        : "Add thought to \(viewModel.captureDestinationName)"
                )
            } else if viewModel.composerHasMatches {
                Text("\(viewModel.searchMatchCount) \(viewModel.searchMatchCount == 1 ? "match" : "matches")")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: floatingComposerHeight)
    }

    private var tagAutocomplete: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.tagSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    viewModel.acceptTagSuggestion(suggestion)
                    focusComposer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: suggestionIcon(suggestion))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(suggestionGradient(suggestion))
                            .frame(width: 16)
                        Text(suggestionLabel(suggestion))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(suggestionGradient(suggestion))
                            .lineLimit(1)
                        Spacer()
                        if case let .existing(group) = suggestion {
                            Text("\(group.count)")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(NotchTheme.tertiaryText)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        index == viewModel.selectedTagSuggestionIndex
                            ? NotchTheme.selectedLedger
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(NotchTheme.raisedGraphite.opacity(0.98))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.32), radius: 10, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tag suggestions")
    }

    private func suggestionIcon(_ suggestion: AppViewModel.TagSuggestion) -> String {
        switch suggestion {
        case .existing: "at"
        case .create: "plus"
        }
    }

    private func suggestionLabel(_ suggestion: AppViewModel.TagSuggestion) -> String {
        switch suggestion {
        case let .existing(group): "@\(group.name)"
        case let .create(name): "Create @\(name)"
        }
    }

    private func suggestionGradient(_ suggestion: AppViewModel.TagSuggestion) -> LinearGradient {
        switch suggestion {
        case let .existing(group):
            NotchTheme.tagIridescence(seed: group.tag.colorSeed)
        case .create:
            NotchTheme.tagIridescence(seed: 0)
        }
    }

    private var composerShape: Capsule {
        Capsule()
    }

    private func composerBackground(angle: Angle) -> some View {
        ZStack {
            if !reduceTransparency {
                composerShape
                    .fill(.ultraThinMaterial)
            }

            composerShape
                .fill(NotchTheme.field.opacity(reduceTransparency ? 1 : 0.72))

            if !reduceTransparency {
                composerShape
                    .fill(composerIridescentGradient(angle: angle))
                    .blur(radius: 12)
                    .opacity(focusedField == .unifiedInput ? 0.03 : 0)
                    .animation(composerFocusAnimation, value: focusedField)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func composerBorder(angle: Angle) -> some View {
        ZStack {
            composerShape
                .strokeBorder(composerIridescentGradient(angle: angle), lineWidth: 1)
                .opacity(
                    focusedField == .unifiedInput && colorSchemeContrast != .increased
                        ? 0.35
                        : 0
                )

            composerShape
                .strokeBorder(
                    colorSchemeContrast == .increased
                        ? Color.white.opacity(0.18)
                        : NotchTheme.controlStroke,
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
                .opacity(
                    focusedField == .unifiedInput && colorSchemeContrast != .increased
                        ? 0
                        : 1
                )
        }
        .animation(composerFocusAnimation, value: focusedField)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func composerIridescentGradient(angle: Angle) -> AngularGradient {
        AngularGradient(
            gradient: NotchTheme.composerIridescence,
            center: .center,
            angle: angle
        )
    }

    private func composerIridescenceAngle(at date: Date) -> Angle {
        guard !reduceMotion else { return .degrees(0) }
        let elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: NotchMotion.composerIridescenceCycleDuration)
        return .degrees((elapsed / NotchMotion.composerIridescenceCycleDuration) * 360)
    }

    private var composerFocusAnimation: Animation {
        reduceMotion ? NotchMotion.reducedMotion : NotchMotion.composerFocus
    }

    private var unifiedInputHint: String {
        if viewModel.canCreateStandaloneTag {
            return "Press Return to create this tag group."
        }
        if viewModel.composerIsTagOnly && viewModel.exactComposerTagExists && !viewModel.composerHasMatches {
            return "This tag exists, but no items in the current filter use it."
        }
        if viewModel.canAddComposerText {
            return "No matching items. Press Return to add this thought to \(viewModel.captureDestinationName)."
        }
        if viewModel.composerHasMatches {
            return "Matching items are shown below."
        }
        return "Type to search \(viewModel.isAtRoot ? "all items" : viewModel.captureDestinationName). If no item matches, press Return to add a new thought."
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterButton(.all, width: 64)
            filterButton(.tasks, width: 76)

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(NotchTheme.control)
                if ![.all, .tasks].contains(viewModel.filter) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NotchTheme.selectedControl)
                        .matchedGeometryEffect(id: "selected-filter", in: filterSelection)
                }
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)

                Menu {
                    ForEach([AppViewModel.InboxFilter.due, .completed, .archive, .trash]) { filter in
                        Button {
                            viewModel.filter = filter
                        } label: {
                            Label(filter.rawValue, systemImage: filter.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .regular))
                        .frame(width: 64, height: 34)
                        .foregroundStyle(
                            [.all, .tasks].contains(viewModel.filter)
                                ? NotchTheme.secondaryText
                                : NotchTheme.primaryText
                        )
                        .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityLabel("More inbox filters")
            }
            .frame(width: 64, height: 34)

            if ![.all, .tasks].contains(viewModel.filter) {
                Text(viewModel.filter.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .background(NotchTheme.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
        .animation(reduceMotion ? nil : NotchMotion.filter, value: viewModel.filter)
    }

    private func filterButton(_ filter: AppViewModel.InboxFilter, width: CGFloat) -> some View {
        Button {
            viewModel.filter = filter
        } label: {
            Text(filter.rawValue)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(viewModel.filter == filter ? NotchTheme.primaryText : NotchTheme.secondaryText)
                .frame(width: width, height: 34)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(NotchTheme.control)
                        if viewModel.filter == filter {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(NotchTheme.selectedControl)
                                .matchedGeometryEffect(id: "selected-filter", in: filterSelection)
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchPressButtonStyle(pressedScale: 0.98, pressedOpacity: 0.92))
        .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityAddTraits(viewModel.filter == filter ? .isSelected : [])
    }

    private var dropTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity.animation(NotchMotion.reducedMotion)
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.985))
                .animation(NotchMotion.dropEnter),
            removal: .opacity.animation(NotchMotion.dropExit)
        )
    }

    private func focusComposer() {
        viewModel.focusComposer()
        Task { @MainActor in
            focusedField = .unifiedInput
        }
    }

    private var ledgerBody: some View {
        Group {
            if let error = viewModel.errorMessage {
                VStack(spacing: 0) {
                    InlineErrorView(message: error) {
                        viewModel.errorMessage = nil
                        focusedField = .unifiedInput
                    }
                    .padding(12)
                    itemFeed
                }
            } else if !viewModel.hasVisibleContent {
                EmptyInboxView(
                    filter: viewModel.filter,
                    query: viewModel.composerText,
                    folderName: viewModel.currentFolder?.name,
                    onCompose: { focusedField = .unifiedInput }
                )
                .padding(.bottom, ledgerBottomClearance)
            } else {
                itemFeed
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchTheme.graphite)
    }

    private var itemFeed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                feedContent

                Color.clear
                    .frame(height: ledgerBottomClearance)
                    .accessibilityHidden(true)
            }
            .background(HiddenScrollIndicatorConfigurator())
            .ledgerDragRegion(.feed)
            .overlay(alignment: .top) {
                if draggedItemID != nil, reorderTarget != nil, previewPinnedItems.isEmpty {
                    emptyGroupDropTarget(title: "Drop to pin", isPinned: true)
                }
            }
        }
        .coordinateSpace(name: "ledger-feed")
        .onPreferenceChange(LedgerDragRegionPreferenceKey.self) { dragRegions = $0 }
        .overlay(alignment: .topLeading) {
            if let draggedItem, let dragPreviewPosition {
                LedgerDragPreview(item: draggedItem)
                    .position(dragPreviewPosition)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .simultaneousGesture(reorderGesture)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var feedContent: some View {
        if !viewModel.visibleTagGroups.isEmpty {
            tagShelf
        }

        if !viewModel.visibleFolders.isEmpty {
            ForEach(viewModel.visibleFolders) { folder in
                folderRow(folder)
            }
        }

        if viewModel.isShowingGlobalSearchResults, !viewModel.visibleItems.isEmpty {
            LedgerSectionHeader(title: "Results", count: viewModel.visibleItems.count)
        }

        if !previewPinnedItems.isEmpty {
            reorderSectionHeader(title: "Pinned", count: previewPinnedItems.count, isPinned: true)
            ForEach(previewPinnedItems) { item in
                reorderableRow(item)
            }
        }

        if !previewPinnedItems.isEmpty, !previewUnpinnedItems.isEmpty {
            reorderSectionDivider(isPinned: false)
        }

        ForEach(previewUnpinnedItems) { item in
            reorderableRow(item)
        }

        if draggedItemID != nil, reorderTarget != nil, previewUnpinnedItems.isEmpty {
            emptyGroupDropTarget(title: "Drop to unpin", isPinned: false)
        }
    }

    private var tagShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NotchTheme.tertiaryText)
                .textCase(.uppercase)
                .tracking(0.7)
                .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(viewModel.visibleTagGroups) { group in
                        Button {
                            viewModel.search(for: group.tag)
                            focusComposer()
                        } label: {
                            IridescentTagLabel(
                                name: group.name,
                                count: group.count,
                                colorSeed: group.tag.colorSeed
                            )
                        }
                        .buttonStyle(NotchPressButtonStyle())
                        .contextMenu {
                            Button("Search @\(group.name)") {
                                viewModel.search(for: group.tag)
                                focusComposer()
                            }
                            Button("Rename Tag") {
                                renameTagName = group.name
                                tagBeingRenamed = group.tag
                            }
                            Divider()
                            Button("Delete Tag", role: .destructive) {
                                tagPendingDeletion = group.tag
                            }
                        }
                        .accessibilityLabel("Tag \(group.name), \(group.count) \(group.count == 1 ? "item" : "items")")
                        .accessibilityHint("Searches for this tag")
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1).padding(.leading, 20)
        }
    }

    private func folderRow(_ folder: AppViewModel.FolderSummary) -> some View {
        FolderLedgerRow(
            folder: folder,
            itemCount: viewModel.matchingItemCount(in: folder.id),
            isDropTarget: targetedFolderID == folder.id,
            reduceMotion: reduceMotion,
            onOpen: { navigate { viewModel.openFolder(folder) } },
            onRename: { beginRenaming(folder) },
            onDelete: { folderPendingDeletion = folder }
        )
        .ledgerDragRegion(.folder(folder.id))
    }

    @ViewBuilder
    private func reorderableRow(_ item: AppViewModel.LedgerItem) -> some View {
        if viewModel.canReorderVisibleItems {
            draggableRow(item)
        } else {
            LedgerRowView(item: item, viewModel: viewModel)
        }
    }

    private func draggableRow(_ item: AppViewModel.LedgerItem) -> some View {
        let target = reorderTarget?.targetID == item.id ? reorderTarget : nil
        return LedgerRowView(item: item, viewModel: viewModel)
            .opacity(draggedItemID == item.id && dragLocation != nil ? 0.20 : 1)
            .overlay {
                LedgerInsertionIndicator(placement: target?.placement)
            }
            .ledgerDragRegion(.row(item.id))
            .accessibilityActions {
                if viewModel.canMoveUp(item) {
                    Button("Move up") {
                        commitAccessibleMove { viewModel.moveUp(item) }
                    }
                }
                if viewModel.canMoveDown(item) {
                    Button("Move down") {
                        commitAccessibleMove { viewModel.moveDown(item) }
                    }
                }
            }
    }

    private func commitMoveToFolder(itemID: UUID, folderID: UUID) {
        guard let item = viewModel.items.first(where: { $0.id == itemID }) else {
            resetReorderState()
            return
        }
        let update = {
            viewModel.move(item, to: folderID)
            reorderSession = nil
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(NotchMotion.reorder, update)
        }
    }

    private func reorderSectionHeader(title: String, count: Int, isPinned: Bool) -> some View {
        LedgerSectionHeader(title: title, count: count)
            .overlay {
                LedgerInsertionIndicator(
                    placement: reorderTarget == LedgerReorderTarget(
                        targetID: nil,
                        placement: .before,
                        destinationPinned: isPinned
                    ) ? .before : nil
                )
            }
            .ledgerDragRegion(.section(isPinned: isPinned))
    }

    private func reorderSectionDivider(isPinned: Bool) -> some View {
        Rectangle()
            .fill(NotchTheme.hairline)
            .frame(height: 1)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .overlay {
                LedgerInsertionIndicator(
                    placement: reorderTarget == LedgerReorderTarget(
                        targetID: nil,
                        placement: .before,
                        destinationPinned: isPinned
                    ) ? .before : nil
                )
            }
            .ledgerDragRegion(.section(isPinned: isPinned))
            .accessibilityLabel(isPinned ? "Pinned items" : "Unpinned items")
            .accessibilityHint("Drop an item here to move it to this section")
    }

    private func emptyGroupDropTarget(title: String, isPinned: Bool) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(NotchTheme.mint)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(NotchTheme.raisedGraphite.opacity(0.96))
            .overlay(alignment: .bottom) {
                LedgerInsertionIndicator(
                    placement: reorderTarget == LedgerReorderTarget(
                        targetID: nil,
                        placement: .before,
                        destinationPinned: isPinned
                    ) ? .before : nil
                )
            }
            .ledgerDragRegion(.section(isPinned: isPinned))
            .accessibilityLabel(title)
    }

    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("ledger-feed"))
            .updating($isReorderGestureActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                if reorderSession == nil {
                    guard viewModel.canReorderVisibleItems,
                          let source = dragRegions.first(where: { region, frame in
                              if case .row = region { return frame.contains(value.startLocation) }
                              return false
                          }),
                          case let .row(itemID) = source.key else { return }
                    reorderSession = LedgerReorderSession(draggedItemID: itemID)
                    dragGrabOffset = CGSize(
                        width: value.startLocation.x - source.value.minX,
                        height: value.startLocation.y - source.value.minY
                    )
                }

                dragLocation = value.location
                applyDragDestination(dragDestination(at: value.location))
            }
            .onEnded { value in
                finishReorder(at: value.location)
            }
    }

    private func dragDestination(at location: CGPoint) -> LedgerDragDestination? {
        LedgerDragResolver.destination(
            at: location,
            regions: dragRegions,
            items: previewVisibleItems,
            draggedItemID: draggedItemID,
            currentTarget: reorderTarget
        )
    }

    private func applyDragDestination(_ destination: LedgerDragDestination?) {
        switch destination {
        case let .reorder(target):
            previewReorder(target)
        case let .folder(folderID):
            previewFolderTarget(folderID)
        case nil:
            clearReorderDestination()
        }
    }

    private func finishReorder(at location: CGPoint) {
        let destination = dragDestination(at: location)
        switch destination {
        case let .reorder(target):
            commitReorder(target)
        case let .folder(folderID):
            if let draggedItemID {
                commitMoveToFolder(itemID: draggedItemID, folderID: folderID)
            } else {
                resetReorderState()
            }
        case nil:
            resetReorderState()
        }
        dragLocation = nil
        dragGrabOffset = nil
    }

    private func commitReorder(_ target: LedgerReorderTarget) {
        guard let draggedItemID = reorderSession?.draggedItemID else {
            resetReorderState()
            return
        }
        let update = {
            _ = viewModel.reorder(
                itemID: draggedItemID,
                relativeTo: target.targetID,
                placement: target.placement,
                destinationPinned: target.destinationPinned
            )
            reorderSession = nil
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(NotchMotion.reorder, update)
        }
    }

    private func previewReorder(_ target: LedgerReorderTarget) {
        guard var session = reorderSession,
              target.targetID != session.draggedItemID,
              session.reorderTarget != target || session.targetedFolderID != nil else { return }
        session.reorderTarget = target
        session.targetedFolderID = nil
        updateReorderSession(session)
    }

    private func previewFolderTarget(_ folderID: UUID?) {
        guard var session = reorderSession,
              session.targetedFolderID != folderID else { return }
        session.targetedFolderID = folderID
        updateReorderSession(session)
    }

    private func clearReorderDestination() {
        guard var session = reorderSession,
              session.reorderTarget != nil || session.targetedFolderID != nil else { return }
        session.reorderTarget = nil
        session.targetedFolderID = nil
        updateReorderSession(session)
    }

    private func updateReorderSession(_ session: LedgerReorderSession) {
        if reduceMotion {
            reorderSession = session
        } else {
            withAnimation(NotchMotion.reorder) {
                reorderSession = session
            }
        }
    }

    private func commitAccessibleMove(_ update: () -> Void) {
        if reduceMotion {
            update()
        } else {
            withAnimation(NotchMotion.reorder, update)
        }
    }

    private func resetReorderState() {
        reorderSession = nil
        dragLocation = nil
        dragGrabOffset = nil
    }

    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.surfaceState == .drop },
            set: { isTargeted in
                if isTargeted { viewModel.beginDrop() } else { viewModel.endDrop() }
            }
        )
    }

    private var acceptedDropTypes: [String] {
        [UTType.fileURL.identifier, UTType.url.identifier, UTType.image.identifier, UTType.plainText.identifier]
    }
}

@MainActor
enum LedgerScrollAppearance {
    static func hideIndicators(in scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.alphaValue = 0
        scrollView.horizontalScroller?.alphaValue = 0
    }
}

private struct HiddenScrollIndicatorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> MarkerView {
        MarkerView(frame: .zero)
    }

    func updateNSView(_ nsView: MarkerView, context: Context) {
        nsView.configureContainingScrollView()
    }

    final class MarkerView: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureContainingScrollView()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureContainingScrollView()
        }

        func configureContainingScrollView() {
            DispatchQueue.main.async { [weak self] in
                var ancestor: NSView? = self
                while let current = ancestor {
                    if let scrollView = current as? NSScrollView {
                        LedgerScrollAppearance.hideIndicators(in: scrollView)
                        return
                    }
                    ancestor = current.superview
                }
            }
        }
    }
}

private struct FolderLedgerRow: View {
    let folder: AppViewModel.FolderSummary
    let itemCount: Int
    let isDropTarget: Bool
    let reduceMotion: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: isDropTarget ? "folder.badge.plus" : "folder.fill")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(
                        isDropTarget
                            ? NotchTheme.mint
                            : (isHovered ? NotchTheme.primaryText : NotchTheme.secondaryText)
                    )
                    .frame(width: 18, height: 18)

                HStack(spacing: 7) {
                    Text(folder.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(NotchTheme.primaryText)
                        .lineLimit(1)
                    Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        isDropTarget
                            ? NotchTheme.mint
                            : (isHovered ? NotchTheme.secondaryText : NotchTheme.tertiaryText)
                    )
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 50)
            .background(
                isDropTarget
                    ? NotchTheme.mint.opacity(0.08)
                    : (isHovered ? NotchTheme.hoveredLedger : Color.clear)
            )
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(NotchTheme.mint.opacity(0.9), lineWidth: 1.5)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(NotchTheme.hairline)
                    .frame(height: 1)
                    .padding(.leading, 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchPressButtonStyle(pressedScale: 0.995, pressedOpacity: 0.86))
        .scaleEffect(isDropTarget && !reduceMotion ? 1.006 : 1)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : NotchMotion.hover, value: isHovered)
        .animation(reduceMotion ? nil : NotchMotion.hover, value: isDropTarget)
        .contextMenu {
            Button("Open Folder", action: onOpen)
            Button("Rename Folder", action: onRename)
            Divider()
            Button("Delete Folder", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Folder \(folder.name), \(itemCount) \(itemCount == 1 ? "item" : "items")")
        .accessibilityHint("Opens this folder")
        .accessibilityAction(named: "Rename Folder", onRename)
        .accessibilityAction(named: "Delete Folder", onDelete)
    }
}

private struct LedgerRowView: View {
    let item: AppViewModel.LedgerItem
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var isSelected: Bool { viewModel.selectedItemID == item.id }
    private var showsActions: Bool { isHovered || isSelected }
    private var isAttachmentOnly: Bool {
        item.attachments.count == 1 && item.detail.isEmpty && item.kind == .note && item.tags.isEmpty
    }

    var body: some View {
        Group {
            if isAttachmentOnly, let attachment = item.attachments.first {
                AttachmentLedgerRow(
                    item: item,
                    attachment: attachment,
                    timeFormat: viewModel.timeFormat,
                    searchLocation: viewModel.isShowingGlobalSearchResults
                        ? (item.folderName ?? "Inbox")
                        : nil
                )
            } else {
                textRow
            }
        }
        .background(isSelected ? NotchTheme.selectedLedger : (isHovered ? NotchTheme.hoveredLedger : Color.clear))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu { rowActions }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kind == .task ? "Task" : "Note"): \(item.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var textRow: some View {
        HStack(spacing: 11) {
            leadingControl

            selectionContent

            trailingContent
                .layoutPriority(1)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: item.detail.isEmpty ? 56 : 66)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotchTheme.hairline)
                .frame(height: 1)
                .padding(.leading, 20)
        }
    }

    private var selectionContent: some View {
        HStack(spacing: 11) {
            if item.displaysAttachmentPrefix {
                prefixIcon
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(item.isCompleted ? NotchTheme.secondaryText : NotchTheme.primaryText)
                    .strikethrough(item.isCompleted, color: NotchTheme.secondaryText)
                    .lineLimit(2)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(item.dueDate != nil && item.detail.isEmpty ? NotchTheme.dueAccent : NotchTheme.secondaryText)
                    .lineLimit(2)
                }

                if !item.tags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(item.tags) { tag in
                                Button {
                                    viewModel.search(for: tag)
                                } label: {
                                    IridescentTagLabel(
                                        name: tag.name,
                                        count: nil,
                                        colorSeed: tag.colorSeed,
                                        compact: true
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Search @\(tag.name)")
                                .accessibilityLabel("Search tag \(tag.name)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.select(item)
        }
    }

    private var trailingContent: some View {
        ZStack(alignment: .trailing) {
            Text(CaptureTimestampFormatter.string(from: item.createdAt, timeFormat: viewModel.timeFormat))
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(NotchTheme.tertiaryText)
                .lineLimit(1)
                .opacity(showsActions ? 0 : 1)
                .accessibilityHidden(showsActions)

            inlineActions
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)
                .accessibilityHidden(!showsActions)
        }
        .frame(width: 112, height: 38, alignment: .trailing)
        .animation(reduceMotion ? nil : NotchMotion.hover, value: showsActions)
    }

    private var prefixIcon: some View {
        Image(systemName: "note.text")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(NotchTheme.secondaryText)
            .frame(width: 32, height: 32)
            .background(NotchTheme.control)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var leadingControl: some View {
        if item.isPinned && !showsActions {
            Image(systemName: "pin")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(NotchTheme.secondaryText)
                .frame(width: 20, height: 28)
                .accessibilityLabel("Pinned")
        } else {
            Button {
                viewModel.toggleComplete(item)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(item.isCompleted ? NotchTheme.mint : NotchTheme.secondaryText)
                    .frame(width: 20, height: 28)
                    .notchHitTarget(Rectangle())
            }
            .buttonStyle(NotchPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.82))
            .notchHitTarget(Rectangle())
            .help(item.isCompleted ? "Mark incomplete" : "Complete")
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Complete item")
        }
    }

    private var subtitle: String? {
        if viewModel.isShowingGlobalSearchResults {
            return item.folderName.map { "Folder · \($0)" } ?? "Inbox"
        }
        if !item.detail.isEmpty { return item.detail }
        if let dueDate = item.dueDate {
            if Calendar.current.isDateInToday(dueDate) { return "Today" }
            return dueDate.formatted(date: .abbreviated, time: .omitted)
        }
        if let sourceApp = item.sourceApp { return "Selected from \(sourceApp)" }
        if let folderName = item.folderName { return "Folder · \(folderName)" }
        return nil
    }

    private var inlineActions: some View {
        Menu {
            rowActions
        } label: {
            Text("⋮")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotchTheme.secondaryText)
                .frame(width: 36, height: 38)
                .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 36, height: 38)
        .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help("More actions")
        .accessibilityLabel("More actions for \(item.title)")
    }

    @ViewBuilder
    private var rowActions: some View {
        Button {
            viewModel.toggleComplete(item)
        } label: {
            Label(
                item.isCompleted ? "Mark incomplete" : "Complete",
                systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark"
            )
        }

        Button {
            viewModel.togglePin(item)
        } label: {
            Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
        }

        Menu {
            Button("Today") {
                viewModel.setDueDate(Calendar.current.startOfDay(for: .now), for: item)
            }
            Button("Tomorrow") {
                viewModel.setDueDate(Calendar.current.date(byAdding: .day, value: 1, to: .now), for: item)
            }
            if item.dueDate != nil {
                Divider()
                Button("Clear due date") { viewModel.setDueDate(nil, for: item) }
            }
        } label: {
            Label("Due date", systemImage: "calendar")
        }

        Menu {
            Button {
                viewModel.move(item, to: nil)
            } label: {
                Label("Inbox", systemImage: "tray")
            }
            .disabled(item.folderID == nil)

            if !viewModel.folders.isEmpty {
                Divider()
                ForEach(viewModel.folders.sorted(by: { $0.sortOrder < $1.sortOrder })) { folder in
                    Button {
                        viewModel.move(item, to: folder.id)
                    } label: {
                        Label(folder.name, systemImage: "folder")
                    }
                    .disabled(item.folderID == folder.id)
                }
            }
        } label: {
            Label("Move", systemImage: "folder")
        }

        Divider()

        if item.isTrashed {
            Button {
                viewModel.restore(item)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                viewModel.deletePermanently(item)
            } label: {
                Label("Delete permanently", systemImage: "trash.slash")
            }
        } else {
            if item.isArchived {
                Button {
                    viewModel.restore(item)
                } label: {
                    Label("Restore to Inbox", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    viewModel.archive(item)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }

            Button(role: .destructive) {
                viewModel.trash(item)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }
}

private struct AttachmentLedgerRow: View {
    let item: AppViewModel.LedgerItem
    let attachment: AppViewModel.LedgerAttachment
    let timeFormat: AppViewModel.TimeFormat
    let searchLocation: String?

    var body: some View {
        Button {
            if let url = attachment.previewURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .frame(width: 20)

                if attachment.kind == .image || attachment.kind == .screenshot {
                    if let url = attachment.previewURL, url.isFileURL {
                        QuickLookThumbnail(url: url, size: CGSize(width: 56, height: 52), fallbackSymbol: symbol)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .frame(width: 56, height: 52)
                            .background(NotchTheme.control)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(NotchTheme.primaryText)
                        .lineLimit(1)
                    if let detail = attachment.subtitle {
                        Text(detail)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(1)
                    }
                    if let searchLocation {
                        Text(searchLocation == "Inbox" ? "Inbox" : "Folder · \(searchLocation)")
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Text(CaptureTimestampFormatter.string(from: item.createdAt, timeFormat: timeFormat))
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(NotchTheme.tertiaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: attachment.kind == .image || attachment.kind == .screenshot ? 64 : 56)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(NotchTheme.hairline)
                    .frame(height: 1)
                    .padding(.leading, 20)
            }
            .notchHitTarget(Rectangle())
        }
        .buttonStyle(NotchPressButtonStyle(pressedScale: 0.995, pressedOpacity: 0.88))
        .notchHitTarget(Rectangle())
        .disabled(attachment.previewURL == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Attachment: \(attachment.name)")
        .accessibilityHint("Opens the captured attachment")
    }

    private var symbol: String {
        switch attachment.kind {
        case .file: "doc"
        case .image: "photo"
        case .link: "link"
        case .screenshot: "viewfinder"
        }
    }

}

private struct QuickLookThumbnail: View {
    let url: URL
    let size: CGSize
    let fallbackSymbol: String
    @State private var thumbnail: CGImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(NotchTheme.control)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: size.width * 2, height: size.height * 2),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail
            )
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                thumbnail = representation.cgImage
            }
        }
    }
}

private struct EmptyInboxView: View {
    let filter: AppViewModel.InboxFilter
    let query: String
    let folderName: String?
    let onCompose: () -> Void

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: isSearching ? "magnifyingglass" : filter.systemImage)
                .font(.system(size: 22, weight: .ultraLight))
                .foregroundStyle(NotchTheme.secondaryText)
            Text(isSearching ? "No matches" : emptyTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.primaryText)
            Text(isSearching ? "Press Return to add “\(query)” to \(folderName ?? "Inbox")." : emptyDetail)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(NotchTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 230)
                .lineLimit(3)
            if !isSearching && filter == .all {
                Button("Capture something") { onCompose() }
                    .buttonStyle(QuietButtonStyle())
                    .notchHitTarget(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var emptyTitle: String {
        if let folderName, filter == .all {
            return "\(folderName) is empty"
        }
        return switch filter {
        case .all: "Your pocket is clear"
        case .tasks: "No open tasks"
        case .due: "Nothing is due"
        case .completed: "No completed items"
        case .archive: "Archive is empty"
        case .trash: "Trash is empty"
        }
    }

    private var emptyDetail: String {
        if folderName != nil, filter == .all {
            return "Add a thought here or move an item into this folder."
        }
        return filter == .all
            ? "Press ⌃⇧Space anywhere to keep the current selection."
            : "Items in this view will appear here."
    }
}

private struct QuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NotchTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(configuration.isPressed ? NotchTheme.selectedControl : NotchTheme.control)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .notchHitTarget(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: configuration.isPressed)
    }
}

private struct InlineErrorView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 10.5, weight: .medium))
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(CompactTextButtonStyle())
                .notchHitTarget(Rectangle())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NotchTheme.primaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error: \(message)")
    }
}

private struct DropTargetOverlay: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 24, weight: .light))
            Text("Drop to capture")
                .font(.system(size: 14, weight: .medium))
            Text("Files, images, links, or text")
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(NotchTheme.secondaryText)
        }
        .foregroundStyle(NotchTheme.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchTheme.ink.opacity(0.97))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(NotchTheme.controlStroke, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .padding(12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop files, images, links, or text to capture")
    }
}
