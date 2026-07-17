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

struct LedgerDragPresentation: Equatable {
    enum Phase: Equatable {
        case dragging
        case settling(LedgerDragLanding)
    }

    let item: AppViewModel.LedgerItem
    let sourceFrame: CGRect
    let grabOffset: CGSize
    var position: CGPoint
    var phase: Phase
    var releaseVelocity: CGSize
    var scale: CGFloat
    var opacity: Double
    let generation: Int
}

enum LedgerDragLanding: Equatable {
    case reorder(CGRect)
    case folder(CGRect)
    case cancel(CGRect)

    var targetPosition: CGPoint {
        switch self {
        case let .folder(frame):
            CGPoint(x: frame.midX, y: frame.midY)
        case let .reorder(frame), let .cancel(frame):
            LedgerDragLandingResolver.rowPreviewPosition(in: frame)
        }
    }
}

private struct LedgerInsertionIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(reduceMotion ? nil : NotchMotion.insertion, value: placement)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LedgerDragPreview: View {
    let item: AppViewModel.LedgerItem
    let phase: LedgerDragPresentation.Phase

    var body: some View {
        HStack(spacing: 10) {
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
        .shadow(
            color: .black.opacity(phase == .dragging ? 0.52 : 0.38),
            radius: phase == .dragging ? 18 : 12,
            y: phase == .dragging ? 11 : 7
        )
    }
}

private struct TonalTagLabel: View {
    let name: String
    let count: Int?
    let colorSeed: Double
    var compact = false

    private var gradient: LinearGradient {
        NotchTheme.tagTonalGradient(seed: colorSeed)
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            Text("@\(name)")
                .font(.system(size: compact ? 9.5 : 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(gradient)
            if let count {
                Text("\(count)")
                    .font(.system(size: compact ? 9.5 : 10.5, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
        }
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

struct LedgerDragLandingResolver {
    static func landing(
        for destination: LedgerDragDestination?,
        itemID: UUID,
        sourceFrame: CGRect,
        regions: [LedgerDragRegion: CGRect]
    ) -> LedgerDragLanding {
        switch destination {
        case .reorder:
            guard let rowFrame = regions[.row(itemID)] else {
                return .cancel(sourceFrame)
            }
            return .reorder(rowFrame)
        case let .folder(folderID):
            guard let folderFrame = regions[.folder(folderID)] else {
                return .cancel(sourceFrame)
            }
            return .folder(folderFrame)
        case nil:
            return .cancel(sourceFrame)
        }
    }

    static func livePreviewPosition(pointer: CGPoint, grabOffset: CGSize) -> CGPoint {
        CGPoint(
            x: pointer.x - grabOffset.width + 165,
            y: pointer.y - min(grabOffset.height, 48) + 24
        )
    }

    static func rowPreviewPosition(in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + 165, y: frame.minY + 24)
    }

    static func projectedRelativeVelocity(
        velocity: CGSize,
        from currentPosition: CGPoint,
        to targetPosition: CGPoint
    ) -> Double {
        let remaining = CGVector(
            dx: targetPosition.x - currentPosition.x,
            dy: targetPosition.y - currentPosition.y
        )
        let numerator = velocity.width * remaining.dx + velocity.height * remaining.dy
        let denominator = max(remaining.dx * remaining.dx + remaining.dy * remaining.dy, 1)
        return min(max(numerator / denominator, -1), 1)
    }

    static func shouldCleanUp(completionGeneration: Int, currentGeneration: Int) -> Bool {
        completionGeneration == currentGeneration
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
    @EnvironmentObject private var presentation: NotchPresentationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var focusedField: Field?
    @GestureState private var isReorderGestureActive = false
    @State private var reorderSession: LedgerReorderSession?
    @State private var dragRegions: [LedgerDragRegion: CGRect] = [:]
    @State private var dragPresentation: LedgerDragPresentation?
    @State private var dragGeneration = 0
    @State private var navigationDirection: CGFloat = 1

    private let floatingComposerMargin: CGFloat = 18
    private let composerTextRowHeight: CGFloat = 48
    private let composerImageStripHeight: CGFloat = 64

    private var composerAttachmentExpansion: CGFloat {
        viewModel.composerHasImages ? composerImageStripHeight : 0
    }

    private var floatingComposerHeight: CGFloat {
        composerTextRowHeight + composerAttachmentExpansion
    }

    private var floatingGlassHeight: CGFloat {
        134 + composerAttachmentExpansion
    }

    private var ledgerBottomClearance: CGFloat {
        96 + composerAttachmentExpansion
    }

    private var draggedItemID: UUID? {
        reorderSession?.draggedItemID ?? dragPresentation?.item.id
    }
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
    private enum Field {
        case unifiedInput
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                ledgerBody
                    .id(viewModel.browseLocation)
                    .transition(navigationTransition)
            }

            floatingComposer
        }
        .frame(width: NotchTheme.width, height: NotchTheme.maxHeight)
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
            if viewModel.itemEditSession != nil {
                viewModel.cancelEditing()
                return
            }
            if !viewModel.tagSuggestions.isEmpty {
                viewModel.dismissTagAutocomplete()
                return
            }
            if reorderSession != nil {
                resetReorderState()
                return
            }
            if viewModel.composerHasQuery {
                viewModel.handleDismissalRequest(.escape)
                return
            }
            if viewModel.isAtRoot {
                viewModel.dismiss()
            } else {
                navigate(forward: false) { viewModel.openRoot() }
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
            if focus == .selectedRow || focus == .itemEditor {
                focusedField = nil
            }
        }
        .onChange(of: viewModel.composerText) { oldValue, newValue in
            viewModel.composerTextDidChange(from: oldValue, to: newValue)
        }
        .onChange(of: isReorderGestureActive) { wasActive, isActive in
            if wasActive,
               !isActive,
               reorderSession != nil,
               dragPresentation?.phase == .dragging {
                resetReorderState()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch Capture inbox")
    }

    private var floatingComposer: some View {
        ZStack(alignment: .bottom) {
            floatingGlassFade

            VStack(spacing: 6) {
                if !viewModel.tagSuggestions.isEmpty {
                    tagAutocomplete
                        .transition(tagAutocompleteTransition)
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
                        navigate(forward: false) { viewModel.openRoot() }
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

                inboxFilterMenu

                if viewModel.isAtRoot {
                    Button {
                        viewModel.newFolderName = ""
                        presentCreateFolder()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 13, weight: .regular))
                    }
                    .buttonStyle(PressableIconButtonStyle())
                    .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .help("New folder")
                    .accessibilityLabel("Create a new folder")
                } else if let folder = viewModel.currentFolder {
                    Button {
                        presentFolderActions(folder)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(PressableIconButtonStyle())
                    .frame(width: 28, height: 28)
                    .help("Folder actions")
                    .accessibilityLabel("Actions for \(folder.name)")
                }

                Button {
                    guard viewModel.saveEditing() else { return }
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
                    guard viewModel.saveEditing() else { return }
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

    private var inboxFilterMenu: some View {
        Button {
            presentation.present(NotchMenu(title: "Inbox filter", anchor: CGPoint(x: 278, y: 52), items: AppViewModel.InboxFilter.allCases.map { filter in
                NotchMenuItem(title: filter.rawValue, icon: filter.systemImage, isChecked: viewModel.filter == filter) {
                    viewModel.filter = filter
                }
            }))
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .regular))
        }
        .buttonStyle(
            PressableIconButtonStyle(
                idleForeground: viewModel.filter == .all
                    ? NotchTheme.secondaryText
                    : NotchTheme.primaryText
            )
        )
        .animation(reduceMotion ? nil : NotchMotion.filter, value: viewModel.filter)
        .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help("Inbox filter: \(viewModel.filter.rawValue)")
        .accessibilityLabel("Inbox filter: \(viewModel.filter.rawValue)")
    }

    private func navigate(forward: Bool, _ update: () -> Void) {
        guard viewModel.saveEditing() else { return }
        navigationDirection = forward ? 1 : -1
        if reduceMotion {
            update()
        } else {
            withAnimation(NotchMotion.navigation, update)
        }
        resetReorderState()
    }

    private var navigationTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity.animation(NotchMotion.reducedMotion)
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(x: 12 * navigationDirection))
                .animation(NotchMotion.navigation),
            removal: .opacity
                .combined(with: .offset(x: -12 * navigationDirection))
                .animation(NotchMotion.navigation)
        )
    }

    private func beginRenaming(_ folder: AppViewModel.FolderSummary) {
        presentation.present(NotchModal(kind: .standard, title: "Rename Folder", message: nil, textFieldLabel: "Folder name", draft: folder.name, primaryTitle: "Rename", cancelTitle: "Cancel", onSubmit: { name in
            viewModel.renameFolder(folder, to: name) ? nil : "Enter a folder name."
        }, onCancel: {}))
    }

    private func presentCreateFolder() {
        presentation.present(NotchModal(kind: .standard, title: "New Folder", message: "Create a folder to group related captures.", textFieldLabel: "Folder name", draft: "", primaryTitle: "Create", cancelTitle: "Cancel", onSubmit: { name in
            viewModel.createFolder(named: name) ? nil : "Enter a unique folder name."
        }, onCancel: {}))
    }

    private func presentFolderActions(_ folder: AppViewModel.FolderSummary) {
        presentation.present(NotchMenu(title: folder.name, anchor: CGPoint(x: 350, y: 54), items: [
            NotchMenuItem(title: "Rename Folder", icon: "pencil") { beginRenaming(folder) },
            NotchMenuItem(title: "Delete Folder", icon: "trash", role: .destructive) { presentDeleteFolder(folder) },
        ]))
    }

    private func presentDeleteFolder(_ folder: AppViewModel.FolderSummary) {
        let count = viewModel.totalItemCount(in: folder.id)
        presentation.present(NotchModal(kind: .destructive, title: "Delete \(folder.name)?", message: "\(count) \(count == 1 ? "item" : "items") will return to Inbox. Nothing will be deleted.", textFieldLabel: nil, draft: "", primaryTitle: "Delete Folder", cancelTitle: "Cancel", onSubmit: { _ in
            viewModel.deleteFolder(folder)
            return nil
        }, onCancel: {}))
    }

    private func presentTagActions(_ tag: AppViewModel.TagSummary, count: Int) {
        presentation.present(NotchMenu(title: "@\(tag.name)", anchor: CGPoint(x: 210, y: 150), items: [
            NotchMenuItem(title: "Search @\(tag.name)", icon: "magnifyingglass") {
                viewModel.search(for: tag)
                focusComposer()
            },
            NotchMenuItem(title: "Rename Tag", icon: "pencil") { presentRenameTag(tag) },
            NotchMenuItem(title: "Delete Tag", icon: "trash", role: .destructive) { presentDeleteTag(tag, count: count) },
        ]))
    }

    private func presentRenameTag(_ tag: AppViewModel.TagSummary) {
        presentation.present(NotchModal(kind: .standard, title: "Rename Tag", message: "Spaces become hyphens. Renaming to an existing tag merges both groups.", textFieldLabel: "Tag name", draft: tag.name, primaryTitle: "Rename", cancelTitle: "Cancel", onSubmit: { name in
            viewModel.renameTag(tag, to: name)
            return nil
        }, onCancel: {}))
    }

    private func presentDeleteTag(_ tag: AppViewModel.TagSummary, count: Int) {
        presentation.present(NotchModal(kind: .destructive, title: "Delete @\(tag.name)?", message: "The tag will be removed from \(count) \(count == 1 ? "item" : "items"). No items will be deleted.", textFieldLabel: nil, draft: "", primaryTitle: "Delete Tag", cancelTitle: "Cancel", onSubmit: { _ in
            viewModel.deleteTag(tag)
            return nil
        }, onCancel: {}))
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
        .animation(reduceMotion ? nil : NotchMotion.content, value: viewModel.composerHasImages)
    }

    private var captureFieldContent: some View {
        VStack(spacing: 0) {
            if viewModel.composerHasImages {
                composerImageStrip
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
            }

            captureTextRow
        }
        .frame(height: floatingComposerHeight)
    }

    private var captureTextRow: some View {
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
                .onPasteCommand(of: [.image, .fileURL]) { providers in
                    _ = viewModel.acceptPastedImages(providers)
                }
                .onKeyPress(.return) {
                    viewModel.handleComposerReturn()
                    return .handled
                }
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

            if viewModel.canSubmitComposer {
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
        .frame(height: composerTextRowHeight)
    }

    private var composerImageStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.composerImages) { image in
                    composerImageThumbnail(image)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .frame(height: composerImageStripHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotchTheme.controlStroke.opacity(0.65))
                .frame(height: 1)
                .padding(.horizontal, 14)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pasted images")
    }

    private func composerImageThumbnail(_ image: AppViewModel.ComposerImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let nsImage = NSImage(data: image.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
            }
            .frame(width: 42, height: 42)
            .background(NotchTheme.control)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)
            }

            Button {
                viewModel.removeComposerImage(id: image.id)
                focusComposer()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(NotchTheme.primaryText, NotchTheme.ink.opacity(0.9))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 7, y: -7)
            .help("Remove \(image.filename)")
            .accessibilityLabel("Remove \(image.filename)")
        }
        .padding(.trailing, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Attached image: \(image.filename)")
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
                        suggestionLabel(suggestion)
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

    private var tagAutocompleteTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity.animation(NotchMotion.reducedMotion)
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.98, anchor: .bottom))
                .combined(with: .offset(y: 6))
                .animation(NotchMotion.insertion),
            removal: .opacity.animation(NotchMotion.removal)
        )
    }

    private func suggestionIcon(_ suggestion: AppViewModel.TagSuggestion) -> String {
        switch suggestion {
        case .existing: "at"
        case .create: "plus"
        }
    }

    @ViewBuilder
    private func suggestionLabel(_ suggestion: AppViewModel.TagSuggestion) -> some View {
        switch suggestion {
        case let .existing(group):
            Text("@\(group.name)")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
        case let .create(name):
            Text("Create ")
                .font(.system(size: 11.5, weight: .medium))
            + Text("@\(name)")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
        }
    }

    private func suggestionGradient(_ suggestion: AppViewModel.TagSuggestion) -> LinearGradient {
        switch suggestion {
        case let .existing(group):
            NotchTheme.tagTonalGradient(seed: group.tag.colorSeed)
        case .create:
            NotchTheme.tagTonalGradient(seed: 0)
        }
    }

    private var composerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
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
        if viewModel.composerHasImages {
            let count = viewModel.composerImages.count
            return "\(count) \(count == 1 ? "image is" : "images are") attached. Press Return to add this capture to \(viewModel.captureDestinationName)."
        }
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

    private var dropTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity.animation(NotchMotion.reducedMotion)
        }
        return .asymmetric(
            insertion: .identity,
            removal: .opacity.animation(NotchMotion.dropExit)
        )
    }

    private func focusComposer() {
        guard viewModel.saveEditing() else { return }
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
            if let presentation = dragPresentation {
                LedgerDragPreview(item: presentation.item, phase: presentation.phase)
                    .scaleEffect(reduceMotion ? 1 : presentation.scale)
                    .opacity(presentation.opacity)
                    .position(presentation.position)
                    .transition(.opacity.animation(NotchMotion.removal))
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
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(viewModel.visibleTagGroups) { group in
                    HStack(spacing: 3) {
                        Button {
                            viewModel.search(for: group.tag)
                            focusComposer()
                        } label: {
                            TonalTagLabel(name: group.name, count: group.count, colorSeed: group.tag.colorSeed)
                        }
                        .buttonStyle(NotchPressButtonStyle())
                        Button {
                            presentTagActions(group.tag, count: group.count)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(NotchTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Actions for tag \(group.name)")
                    }
                    .accessibilityLabel("Tag \(group.name), \(group.count) \(group.count == 1 ? "item" : "items")")
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
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
            onOpen: { navigate(forward: true) { viewModel.openFolder(folder) } },
            onRename: { beginRenaming(folder) },
            onDelete: { presentDeleteFolder(folder) }
        )
        .ledgerDragRegion(.folder(folder.id))
    }

    private func reorderableRow(_ item: AppViewModel.LedgerItem) -> some View {
        let target = reorderTarget?.targetID == item.id ? reorderTarget : nil
        let isDragSource = dragPresentation?.item.id == item.id
        return LedgerRowView(item: item, viewModel: viewModel)
            .opacity(isDragSource ? 0.18 : 1)
            .overlay {
                LedgerInsertionIndicator(placement: target?.placement)
            }
            .ledgerDragRegion(.row(item.id))
            .animation(
                reduceMotion ? nil : NotchMotion.dragLanding.animation,
                value: isDragSource
            )
            .accessibilityActions {
                if viewModel.canReorderVisibleItems {
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
            .transition(completionRemovalTransition(for: item))
    }

    private func completionRemovalTransition(for item: AppViewModel.LedgerItem) -> AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }
        return .modifier(
            active: LedgerCompletionExitModifier(
                progress: 1,
                wasCompleted: item.isCompleted
            ),
            identity: LedgerCompletionExitModifier(
                progress: 0,
                wasCompleted: item.isCompleted
            )
        )
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
                          case let .row(itemID) = source.key,
                          let item = viewModel.items.first(where: { $0.id == itemID }) else { return }
                    reorderSession = LedgerReorderSession(draggedItemID: itemID)
                    beginDrag(
                        item: item,
                        sourceFrame: source.value,
                        grabOffset: CGSize(
                            width: value.startLocation.x - source.value.minX,
                            height: value.startLocation.y - source.value.minY
                        ),
                        pointer: value.location
                    )
                }

                updateDragPosition(value.location)
                applyDragDestination(dragDestination(at: value.location))
            }
            .onEnded { value in
                finishReorder(at: value.location, velocity: value.velocity)
            }
    }

    private func beginDrag(
        item: AppViewModel.LedgerItem,
        sourceFrame: CGRect,
        grabOffset: CGSize,
        pointer: CGPoint
    ) {
        dragGeneration &+= 1
        let generation = dragGeneration
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragPresentation = LedgerDragPresentation(
                item: item,
                sourceFrame: sourceFrame,
                grabOffset: grabOffset,
                position: LedgerDragLandingResolver.livePreviewPosition(
                    pointer: pointer,
                    grabOffset: grabOffset
                ),
                phase: .dragging,
                releaseVelocity: .zero,
                scale: reduceMotion ? 1 : 0.985,
                opacity: 1,
                generation: generation
            )
        }

        guard !reduceMotion else { return }
        Task { @MainActor in
            await Task.yield()
            guard dragPresentation?.generation == generation,
                  dragPresentation?.phase == .dragging else { return }
            withAnimation(NotchMotion.dragLift.animation) {
                dragPresentation?.scale = 1
            }
        }
    }

    private func updateDragPosition(_ location: CGPoint) {
        guard var presentation = dragPresentation,
              presentation.phase == .dragging else { return }
        presentation.position = LedgerDragLandingResolver.livePreviewPosition(
            pointer: location,
            grabOffset: presentation.grabOffset
        )
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragPresentation = presentation
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

    private func finishReorder(at location: CGPoint, velocity: CGSize) {
        guard var presentation = dragPresentation,
              presentation.phase == .dragging else {
            resetReorderState()
            return
        }

        let destination = dragDestination(at: location)
        let landing = LedgerDragLandingResolver.landing(
            for: destination,
            itemID: presentation.item.id,
            sourceFrame: presentation.sourceFrame,
            regions: dragRegions
        )

        switch destination {
        case let .reorder(target):
            commitReorder(itemID: presentation.item.id, target: target)
        case let .folder(folderID):
            commitMoveToFolder(item: presentation.item, folderID: folderID)
        case nil:
            reorderSession = nil
        }

        presentation.phase = .settling(landing)
        presentation.releaseVelocity = velocity
        let relativeVelocity = LedgerDragLandingResolver.projectedRelativeVelocity(
            velocity: velocity,
            from: presentation.position,
            to: landing.targetPosition
        )
        let generation = presentation.generation

        if reduceMotion {
            dragPresentation = presentation
            withAnimation(NotchMotion.reducedMotion, completionCriteria: .logicallyComplete) {
                dragPresentation?.opacity = 0
            } completion: {
                completeDragLanding(generation: generation)
            }
            return
        }

        withAnimation(
            NotchMotion.landing(initialVelocity: relativeVelocity),
            completionCriteria: .logicallyComplete
        ) {
            presentation.position = landing.targetPosition
            presentation.scale = switch landing {
            case .folder: 0.94
            case .reorder, .cancel: 0.985
            }
            if case .folder = landing {
                presentation.opacity = 0
            }
            dragPresentation = presentation
        } completion: {
            completeDragLanding(generation: generation)
        }
    }

    private func commitReorder(itemID: UUID, target: LedgerReorderTarget) {
        let update = {
            _ = viewModel.reorder(
                itemID: itemID,
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

    private func commitMoveToFolder(item: AppViewModel.LedgerItem, folderID: UUID) {
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

    private func completeDragLanding(generation: Int) {
        guard LedgerDragLandingResolver.shouldCleanUp(
            completionGeneration: generation,
            currentGeneration: dragPresentation?.generation ?? dragGeneration
        ) else { return }
        dragPresentation = nil
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
        dragGeneration &+= 1
        reorderSession = nil
        dragPresentation = nil
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
    @EnvironmentObject private var presentation: NotchPresentationCoordinator
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
        .scaleEffect(isDropTarget && !reduceMotion ? 1.01 : 1)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : NotchMotion.hover, value: isHovered)
        .animation(reduceMotion ? nil : NotchMotion.filter, value: isDropTarget)
        .overlay(alignment: .trailing) {
            Button {
                presentation.present(NotchMenu(title: folder.name, anchor: CGPoint(x: 330, y: 220), items: [
                    NotchMenuItem(title: "Open Folder", icon: "folder") { onOpen() },
                    NotchMenuItem(title: "Rename Folder", icon: "pencil") { onRename() },
                    NotchMenuItem(title: "Delete Folder", icon: "trash", role: .destructive) { onDelete() },
                ]))
            } label: {
                Image(systemName: "ellipsis.vertical").font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 28)
            }
            .buttonStyle(PressableIconButtonStyle())
            // The chevron remains the final affordance; actions sit immediately before it.
            .padding(.trailing, 34)
            .opacity(isHovered ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Folder \(folder.name), \(itemCount) \(itemCount == 1 ? "item" : "items")")
        .accessibilityHint("Opens this folder")
        .accessibilityAction(named: "Rename Folder", onRename)
        .accessibilityAction(named: "Delete Folder", onDelete)
    }
}

struct LedgerCompletionRevealGeometry {
    static let originX: CGFloat = 30

    static func revealFrame(in rect: CGRect, progress: CGFloat) -> CGRect {
        guard rect.width > 0, rect.height > 0 else { return .zero }

        let clampedProgress = min(max(progress, 0), 1)
        let origin = min(max(rect.minX + originX, rect.minX), rect.maxX)
        guard clampedProgress > 0 else {
            return CGRect(x: origin, y: rect.midY, width: 0, height: 0)
        }

        let extent = rect.width * clampedProgress
        if extent <= rect.height || rect.width <= rect.height {
            let diameter = min(extent, rect.width, rect.height)
            let proposedX = origin - (diameter / 2)
            let x = min(max(proposedX, rect.minX), rect.maxX - diameter)
            return CGRect(
                x: x,
                y: rect.midY - (diameter / 2),
                width: diameter,
                height: diameter
            )
        }

        let stretch = (extent - rect.height) / (rect.width - rect.height)
        let initialLeft = min(max(origin - (rect.height / 2), rect.minX), rect.maxX)
        let initialRight = min(max(origin + (rect.height / 2), rect.minX), rect.maxX)
        let left = initialLeft + ((rect.minX - initialLeft) * stretch)
        let right = initialRight + ((rect.maxX - initialRight) * stretch)
        return CGRect(x: left, y: rect.minY, width: right - left, height: rect.height)
    }

    static func cornerRadius(for revealFrame: CGRect, progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        let maximumRadius = min(revealFrame.width, revealFrame.height) / 2
        return maximumRadius * (1 - clampedProgress)
    }
}

private struct LedgerCompletionRevealMask: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let revealFrame = LedgerCompletionRevealGeometry.revealFrame(
            in: rect,
            progress: progress
        )
        guard revealFrame.width > 0, revealFrame.height > 0 else { return Path() }
        return RoundedRectangle(
            cornerRadius: LedgerCompletionRevealGeometry.cornerRadius(
                for: revealFrame,
                progress: progress
            ),
            style: .continuous
        )
        .path(in: revealFrame)
    }
}

private struct LedgerCompletionFrontHighlightMask: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        guard clampedProgress > 0, clampedProgress < 0.999 else { return Path() }
        let revealFrame = LedgerCompletionRevealGeometry.revealFrame(
            in: rect,
            progress: clampedProgress
        )
        let highlightFrame = CGRect(
            x: revealFrame.maxX - 12,
            y: rect.minY,
            width: 24,
            height: rect.height
        )
        return Path(highlightFrame.intersection(rect))
    }
}

private struct LedgerCompletionFrontHighlight: View {
    var progress: CGFloat

    var body: some View {
        NotchTheme.completionWash
            .mask {
                LedgerCompletionFrontHighlightMask(progress: progress)
                    .fill(.white)
            }
            .blur(radius: 4)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct LedgerCompletionExitModifier: ViewModifier {
    let progress: Double
    let wasCompleted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if wasCompleted {
            content
                .mask {
                    LedgerCompletionRevealMask(progress: 1 - CGFloat(progress))
                        .fill(.white)
                }
                .scaleEffect(1 - (0.015 * progress))
                .opacity(1 - pow(progress, 3))
        } else {
            content
                .background {
                    ZStack {
                        NotchTheme.completedLedger
                        NotchTheme.completionWash
                    }
                    .mask {
                        LedgerCompletionRevealMask(progress: CGFloat(progress))
                            .fill(.white)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay {
                    LedgerCompletionFrontHighlight(progress: CGFloat(progress))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .scaleEffect(1 - (0.015 * progress))
                .opacity(1 - pow(progress, 3))
        }
    }
}

private struct LedgerRowView: View {
    let item: AppViewModel.LedgerItem
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var presentation: NotchPresentationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isEditorFocused: Bool
    @State private var isHovered = false
    @State private var isMoreActionsHovered = false
    @State private var completionRevealProgress: CGFloat

    private var isSelected: Bool { viewModel.selectedItemID == item.id }
    private var isEditing: Bool { viewModel.itemEditSession?.itemID == item.id }
    private var showsActions: Bool { isHovered || isSelected }
    private var isSingleAttachmentOnly: Bool {
        item.text.isEmpty && item.attachments.count == 1 && item.tags.isEmpty
    }

    init(item: AppViewModel.LedgerItem, viewModel: AppViewModel) {
        self.item = item
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _completionRevealProgress = State(initialValue: item.isCompleted ? 1 : 0)
    }

    var body: some View {
        ZStack {
            completionBackgroundLayer
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if !reduceMotion {
                LedgerCompletionFrontHighlight(progress: completionRevealProgress)
            }

            interactionBackgroundLayer

            rowContent(
                completedPresentation: isEditing && item.isCompleted,
                isInteractive: true
            )

            if !isEditing {
                completedContentLayer
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onChange(of: item.isCompleted) { _, isCompleted in
            let animation = reduceMotion
                ? NotchMotion.reducedMotion
                : (isCompleted ? NotchMotion.completionReveal : NotchMotion.completionRetract)
            withAnimation(animation) {
                completionRevealProgress = isCompleted ? 1 : 0
            }
        }
        .task(id: isEditing) {
            isEditorFocused = isEditing
        }
        .onChange(of: isEditorFocused) { wasFocused, isFocused in
            guard wasFocused, !isFocused, isEditing else { return }
            Task { @MainActor in
                await Task.yield()
                guard isEditing else { return }
                if !viewModel.saveEditing(resumeRowFocus: false) {
                    isEditorFocused = true
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kind == .task ? "Task" : "Note"): \(item.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            if !item.text.isEmpty {
                Button("Edit") { viewModel.beginEditing(item) }
            }
        }
    }

    @ViewBuilder
    private func rowContent(completedPresentation: Bool, isInteractive: Bool) -> some View {
        if item.displaysOnlyImages {
            imageAttachmentRows(
                completedPresentation: completedPresentation,
                isInteractive: isInteractive
            )
        } else if isSingleAttachmentOnly, let attachment = item.attachments.first {
            AttachmentLedgerRow(
                item: item,
                attachment: attachment,
                timeFormat: viewModel.timeFormat,
                searchLocation: viewModel.isShowingGlobalSearchResults
                    ? (item.folderName ?? "Inbox")
                    : nil,
                completedPresentation: completedPresentation,
                isInteractive: isInteractive
            )
        } else if item.hasImageAttachments {
            VStack(spacing: 0) {
                textRow(
                    completedPresentation: completedPresentation,
                    isInteractive: isInteractive
                )
                imageAttachmentRows(
                    completedPresentation: completedPresentation,
                    isInteractive: isInteractive
                )
            }
        } else {
            textRow(
                completedPresentation: completedPresentation,
                isInteractive: isInteractive
            )
        }
    }

    private func imageAttachmentRows(
        completedPresentation: Bool,
        isInteractive: Bool
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(item.imageAttachments) { attachment in
                AttachmentLedgerRow(
                    item: item,
                    attachment: attachment,
                    timeFormat: viewModel.timeFormat,
                    searchLocation: viewModel.isShowingGlobalSearchResults
                        ? (item.folderName ?? "Inbox")
                        : nil,
                    completedPresentation: completedPresentation,
                    isInteractive: isInteractive
                )
            }
        }
    }

    @ViewBuilder
    private var completionBackgroundLayer: some View {
        if reduceMotion {
            NotchTheme.completedLedger
                .opacity(Double(completionRevealProgress))
        } else {
            NotchTheme.completedLedger
                .mask {
                    LedgerCompletionRevealMask(progress: completionRevealProgress)
                        .fill(.white)
                }
        }
    }

    @ViewBuilder
    private var interactionBackgroundLayer: some View {
        if isSelected {
            NotchTheme.selectedLedger
        } else if isHovered {
            NotchTheme.hoveredLedger
        }
    }

    @ViewBuilder
    private var completedContentLayer: some View {
        if reduceMotion {
            rowContent(completedPresentation: true, isInteractive: false)
                .opacity(Double(completionRevealProgress))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            rowContent(completedPresentation: true, isInteractive: false)
                .mask {
                    LedgerCompletionRevealMask(progress: completionRevealProgress)
                        .fill(.white)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func textRow(completedPresentation: Bool, isInteractive: Bool) -> some View {
        HStack(spacing: 11) {
            leadingControl(
                completedPresentation: completedPresentation,
                isInteractive: isInteractive
            )

            selectionContent(
                completedPresentation: completedPresentation,
                isInteractive: isInteractive
            )

            if isInteractive {
                trailingContent
                    .layoutPriority(1)
            } else {
                Color.clear
                    .frame(width: 112, height: 38)
                    .layoutPriority(1)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(minHeight: item.detail.isEmpty ? 56 : 66)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotchTheme.hairline)
                .frame(height: 1)
                .padding(.leading, 20)
        }
    }

    @ViewBuilder
    private func selectionContent(completedPresentation: Bool, isInteractive: Bool) -> some View {
        if isInteractive {
            if isEditing {
                selectionContentLayout(
                    completedPresentation: completedPresentation,
                    isInteractive: true
                )
            } else {
                selectionContentLayout(
                    completedPresentation: completedPresentation,
                    isInteractive: true
                )
                .contentShape(Rectangle())
                .gesture(selectionGesture)
            }
        } else {
            selectionContentLayout(
                completedPresentation: completedPresentation,
                isInteractive: false
            )
        }
    }

    private func selectionContentLayout(
        completedPresentation: Bool,
        isInteractive: Bool
    ) -> some View {
        HStack(spacing: 11) {
            if item.displaysAttachmentPrefix {
                prefixIcon(completedPresentation: completedPresentation)
            }

            if isEditing {
                inlineEditor
            } else {
                displayText(
                    completedPresentation: completedPresentation,
                    isInteractive: isInteractive
                )
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionGesture: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { result in
                switch result {
                case .first:
                    viewModel.beginEditing(item)
                case .second:
                    viewModel.select(item)
                }
            }
    }

    @ViewBuilder
    private func displayText(completedPresentation: Bool, isInteractive: Bool) -> some View {
        if isInteractive {
            displayTextLayout(completedPresentation: completedPresentation, isInteractive: true)
        } else {
            displayTextLayout(completedPresentation: completedPresentation, isInteractive: false)
        }
    }

    private func displayTextLayout(
        completedPresentation: Bool,
        isInteractive: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            titleText(completedPresentation: completedPresentation, isInteractive: isInteractive)
            .font(.system(size: 12.5, weight: .regular))
            .foregroundStyle(completedPresentation ? NotchTheme.secondaryText : NotchTheme.primaryText)
            .strikethrough(completedPresentation, color: NotchTheme.secondaryText)
            .lineLimit(2)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(
                        completedPresentation
                            ? NotchTheme.tertiaryText
                            : (item.dueDate != nil && item.detail.isEmpty
                                ? NotchTheme.dueAccent
                                : NotchTheme.secondaryText)
                    )
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func titleText(completedPresentation: Bool, isInteractive: Bool) -> some View {
        if isInteractive {
            InlineTagTitleText(title: item.title, tags: item.tags) { tag in
                viewModel.search(for: tag)
            }
        } else {
            Text(InlineTagTitleFormatter.attributedTitle(
                item.title,
                tags: item.tags,
                includesLinks: false
            ))
        }
    }

    private var completionStateAnimation: Animation {
        if reduceMotion { return NotchMotion.reducedMotion }
        return item.isCompleted ? NotchMotion.completion : NotchMotion.completionReopen
    }

    private var inlineEditor: some View {
        TextField("", text: editingDraft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .regular))
            .foregroundStyle(NotchTheme.primaryText)
            .multilineTextAlignment(.leading)
            .lineLimit(1...4)
            .focused($isEditorFocused)
            .onKeyPress(.return, phases: .down) { press in
                guard !press.modifiers.contains(.shift) else { return .ignored }
                _ = viewModel.saveEditing()
                return .handled
            }
            .onExitCommand {
                viewModel.cancelEditing()
            }
            .accessibilityLabel("Edit item content")
            .accessibilityHint("Press Return to save, Shift-Return for a new line, or Escape to cancel")
    }

    private var editingDraft: Binding<String> {
        Binding(
            get: {
                guard viewModel.itemEditSession?.itemID == item.id else { return item.text }
                return viewModel.itemEditSession?.draft ?? item.text
            },
            set: { viewModel.updateEditingDraft($0) }
        )
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

    private func prefixIcon(completedPresentation: Bool) -> some View {
        Image(systemName: "note.text")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(
                completedPresentation ? NotchTheme.tertiaryText : NotchTheme.secondaryText
            )
            .frame(width: 32, height: 32)
            .background(NotchTheme.control)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func leadingControl(completedPresentation: Bool, isInteractive: Bool) -> some View {
        if item.isPinned && !showsActions {
            Image(systemName: "pin")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(
                    completedPresentation ? NotchTheme.tertiaryText : NotchTheme.secondaryText
                )
                .frame(width: 20, height: 28)
                .accessibilityLabel("Pinned")
        } else if isInteractive {
            Button {
                viewModel.toggleComplete(item)
            } label: {
                completionControlVisual(completedPresentation: completedPresentation)
            }
            .buttonStyle(NotchPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.82))
            .notchHitTarget(Rectangle())
            .help(item.isCompleted ? "Mark incomplete" : "Complete")
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Complete item")
        } else {
            completionControlVisual(completedPresentation: completedPresentation)
        }
    }

    private func completionControlVisual(completedPresentation: Bool) -> some View {
        ZStack {
            Image(systemName: "circle")
                .opacity(completedPresentation ? 0 : 1)
                .scaleEffect(symbolScale(isVisible: !item.isCompleted))

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(NotchTheme.mint)
                .opacity(completedPresentation ? 1 : 0)
                .scaleEffect(symbolScale(isVisible: item.isCompleted))
        }
        .font(.system(size: 12, weight: .light))
        .foregroundStyle(NotchTheme.secondaryText)
        .frame(width: 20, height: 28)
        .notchHitTarget(Rectangle())
        .animation(completionStateAnimation, value: item.isCompleted)
    }

    private func symbolScale(isVisible: Bool) -> CGFloat {
        guard !reduceMotion else { return 1 }
        return isVisible ? 1 : 0.78
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
        return nil
    }

    private var inlineActions: some View {
        Button {
            presentation.present(NotchMenu(title: item.title, anchor: CGPoint(x: 330, y: 290), items: appMenuItems))
        } label: {
            Text("⋮")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    isMoreActionsHovered ? NotchTheme.primaryText : NotchTheme.secondaryText
                )
                .frame(width: 36, height: 38)
                .background(
                    isMoreActionsHovered ? NotchTheme.control : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onHover { isMoreActionsHovered = $0 }
                .animation(reduceMotion ? nil : NotchMotion.hover, value: isMoreActionsHovered)
        }
        .buttonStyle(.plain)
        .frame(width: 36, height: 38)
        .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help("More actions")
        .accessibilityLabel("More actions for \(item.title)")
    }

    private var appMenuItems: [NotchMenuItem] {
        var items: [NotchMenuItem] = [
            NotchMenuItem(title: "Edit", icon: "pencil", isEnabled: !item.text.isEmpty) { viewModel.beginEditing(item) },
            NotchMenuItem(title: item.isCompleted ? "Mark incomplete" : "Complete", icon: item.isCompleted ? "arrow.uturn.backward" : "checkmark") { viewModel.toggleComplete(item) },
            NotchMenuItem(title: item.isPinned ? "Unpin" : "Pin", icon: item.isPinned ? "pin.slash" : "pin") { viewModel.togglePin(item) },
        ]
        items.append(NotchMenuItem(title: "Move to Inbox", icon: "tray", isEnabled: item.folderID != nil) { viewModel.move(item, to: nil) })
        for folder in viewModel.folders.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            items.append(NotchMenuItem(title: "Move to \(folder.name)", icon: "folder", isEnabled: item.folderID != folder.id) { viewModel.move(item, to: folder.id) })
        }
        if item.isTrashed {
            items.append(NotchMenuItem(title: "Restore", icon: "arrow.uturn.backward") { viewModel.restore(item) })
            items.append(NotchMenuItem(title: "Delete permanently", icon: "trash.slash", role: .destructive) { viewModel.deletePermanently(item) })
        } else {
            items.append(NotchMenuItem(title: item.isArchived ? "Restore to Inbox" : "Archive", icon: item.isArchived ? "arrow.uturn.backward" : "archivebox") {
                item.isArchived ? viewModel.restore(item) : viewModel.archive(item)
            })
            items.append(NotchMenuItem(title: "Move to Trash", icon: "trash", role: .destructive) { viewModel.trash(item) })
        }
        return items
    }

}

private struct AttachmentLedgerRow: View {
    let item: AppViewModel.LedgerItem
    let attachment: AppViewModel.LedgerAttachment
    let timeFormat: AppViewModel.TimeFormat
    let searchLocation: String?
    let completedPresentation: Bool
    let isInteractive: Bool

    @ViewBuilder
    var body: some View {
        if isInteractive {
            Button {
                if let url = attachment.previewURL {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                rowLabel
            }
            .buttonStyle(NotchPressButtonStyle(pressedScale: 0.995, pressedOpacity: 0.88))
            .notchHitTarget(Rectangle())
            .disabled(attachment.previewURL == nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Attachment: \(attachment.name)")
            .accessibilityHint("Opens the captured attachment")
        } else {
            rowLabel
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 12) {
            if !attachment.isImage {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(
                        completedPresentation ? NotchTheme.tertiaryText : NotchTheme.secondaryText
                    )
                    .frame(width: 20)
            }

            if attachment.isImage {
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
                    .foregroundStyle(
                        completedPresentation ? NotchTheme.secondaryText : NotchTheme.primaryText
                    )
                    .strikethrough(completedPresentation, color: NotchTheme.secondaryText)
                    .lineLimit(1)
                if let detail = attachment.subtitle {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(
                            completedPresentation
                                ? NotchTheme.tertiaryText
                                : NotchTheme.secondaryText
                        )
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
                .foregroundStyle(
                    completedPresentation ? NotchTheme.tertiaryText : NotchTheme.secondaryText
                )
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
            Text(isSearching ? "Press Return to add to \(folderName ?? "Inbox")." : emptyDetail)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentIsSettled = false

    var body: some View {
        ZStack {
            NotchTheme.ink.opacity(0.97)

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
            .opacity(contentIsSettled ? 1 : 0)
            .scaleEffect(reduceMotion || contentIsSettled ? 1 : 0.985)
            .animation(
                reduceMotion ? NotchMotion.reducedMotion : NotchMotion.dropEnter,
                value: contentIsSettled
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(NotchTheme.controlStroke, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .padding(12)
        }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                contentIsSettled = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop files, images, links, or text to capture")
    }
}
