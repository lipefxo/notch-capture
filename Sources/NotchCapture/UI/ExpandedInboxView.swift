import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ExpandedSurfaceRevealPlan: Equatable {
    let generation: Int
    let ledgerDelay: TimeInterval
    let composerDelay: TimeInterval
    let revealDuration: TimeInterval

    static func applies(to request: PanelMorphRequest, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, request.kind == .expand else { return false }
        return request.targetState == .expanded || request.targetState == .dropTarget
    }

    static func resolve(
        for request: PanelMorphRequest?,
        reduceMotion: Bool
    ) -> Self? {
        guard let request,
              request.phase == .active,
              applies(to: request, reduceMotion: reduceMotion) else { return nil }
        return Self(
            generation: request.generation,
            ledgerDelay: NotchMotion.expandedLedgerDelay,
            composerDelay: NotchMotion.expandedComposerDelay,
            revealDuration: NotchMotion.expandedElementRevealDuration
        )
    }
}

struct ExpandedInboxView: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var presentation: NotchPresentationCoordinator
    @EnvironmentObject private var morphCoordinator: PanelMorphCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var focusedField: Field?
    /// Row frames update on every scroll frame; they are only read inside
    /// gesture handlers, so they live in a plain reference box instead of
    /// `@State` — writing them must not re-render the whole inbox.
    private final class LedgerDragRegionStore {
        var regions: [LedgerDragRegion: CGRect] = [:]
    }

    @GestureState private var isReorderGestureActive = false
    @State private var reorderSession: LedgerReorderSession?
    @State private var folderReorderSession: FolderReorderSession?
    @State private var dragRegionStore = LedgerDragRegionStore()
    @State private var dragPresentation: LedgerDragPresentation?
    @State private var dragGeneration = 0
    @State private var navigationDirection: CGFloat = 1
    @State private var ledgerAppearance = 1.0
    @State private var composerAppearance = 1.0
    @State private var appearanceGeneration: Int?
    @State private var appearanceTask: Task<Void, Never>?
    @State private var ledgerScrollTask: Task<Void, Never>?
    @State private var folderHeaderMenuAnchor: CGRect = .zero
    @State private var pomodoroMenuAnchor: CGRect = .zero

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
    private var previewFolders: [AppViewModel.FolderSummary] {
        folderReorderSession?.previewing(viewModel.visibleFolders) ?? viewModel.visibleFolders
    }
    private var previewUnpinnedItems: [AppViewModel.LedgerItem] {
        previewVisibleItems.filter { !$0.isPinned }
    }
    private enum Field {
        case unifiedInput
    }

    private enum LedgerScrollTarget: Hashable {
        case folder(UUID)
        case item(UUID)
    }

    private var selectedLedgerScrollTarget: LedgerScrollTarget? {
        guard viewModel.keyboardFocus == .selectedRow else { return nil }
        if let folderID = viewModel.selectedFolderID { return .folder(folderID) }
        if let itemID = viewModel.selectedItemID { return .item(itemID) }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                UtilityShelfView(viewModel: viewModel)
                ledgerBody
                    .id(viewModel.browseLocation)
                    .transition(navigationTransition)
                    .opacity(ledgerAppearance)
                    .offset(y: -NotchMotion.expandedLedgerOffset * (1 - ledgerAppearance))
                    .scaleEffect(
                        x: 1,
                        y: 0.99 + (0.01 * ledgerAppearance),
                        anchor: .top
                    )
            }

            floatingComposer
                .opacity(composerAppearance)
                .offset(y: -NotchMotion.expandedComposerOffset * (1 - composerAppearance))
                .scaleEffect(0.97 + (0.03 * composerAppearance), anchor: .top)
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
            if viewModel.composerHasDraft {
                viewModel.handleDismissalRequest(.escape)
                return
            }
            if viewModel.isAtRoot {
                viewModel.dismiss()
            } else {
                navigate(forward: false) { viewModel.openRoot() }
            }
        }
        .onAppear {
            handleAppearanceRequest(morphCoordinator.request)
        }
        .onDisappear {
            appearanceTask?.cancel()
            ledgerScrollTask?.cancel()
            resetReorderState()
        }
        .onChange(of: morphCoordinator.request) { _, request in
            handleAppearanceRequest(request)
        }
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
            } else if focus == .composer {
                focusedField = .unifiedInput
            }
        }
        .onChange(of: presentation.hasActivePresentation) { hadPresentation, hasPresentation in
            // Menus and modals take key focus while open; hand it back to the
            // composer when they close or typing lands nowhere. Deferred one
            // turn: a focus change requested in the same transaction that
            // removes the modal's focused text field gets dropped by SwiftUI.
            if hadPresentation, !hasPresentation, viewModel.keyboardFocus == .composer {
                Task { @MainActor in
                    await Task.yield()
                    guard !presentation.hasActivePresentation,
                          viewModel.keyboardFocus == .composer else { return }
                    focusedField = .unifiedInput
                }
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
                if !viewModel.composerCommandSuggestions.isEmpty {
                    commandAutocomplete
                        .transition(tagAutocompleteTransition)
                } else if !viewModel.tagSuggestions.isEmpty {
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
                    .menuAnchor($folderHeaderMenuAnchor)
                    .help("Folder actions")
                    .accessibilityLabel("Actions for \(folder.name)")
                }

                pomodoroControl

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

    private var pomodoroControl: some View {
        Button {
            presentPomodoroMenu()
        } label: {
            Group {
                if viewModel.pomodoro.isActive {
                    PomodoroCountdownLabel(state: viewModel.pomodoro)
                        .frame(minWidth: 38)
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .regular))
                }
            }
            .frame(height: 28)
        }
        .buttonStyle(PressableIconButtonStyle(
            idleForeground: viewModel.pomodoro.isActive ? NotchTheme.mint : NotchTheme.secondaryText,
            width: viewModel.pomodoro.isActive ? 42 : 28
        ))
        .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .menuAnchor($pomodoroMenuAnchor)
        .help(viewModel.pomodoro.isActive ? "Focus timer" : "Start a focus timer")
        .accessibilityLabel(viewModel.pomodoro.isActive ? "Focus timer" : "Start a focus timer")
    }

    private func presentPomodoroMenu() {
        var items: [NotchMenuItem] = []
        var style: NotchMenu.Style = .standard
        switch viewModel.pomodoro.phase {
        case .idle:
            style = .pomodoroDurationPicker
            for minutes in [15, 25, 45, 60] {
                items.append(NotchMenuItem(
                    title: String(format: "%d:00", minutes),
                    icon: nil,
                    isChecked: minutes == Int(viewModel.pomodoro.duration / 60)
                ) {
                    viewModel.setPomodoroDuration(TimeInterval(minutes * 60))
                    viewModel.togglePomodoro()
                })
            }
        case .running:
            items.append(NotchMenuItem(title: "Pause", icon: "pause.fill") { viewModel.togglePomodoro() })
            items.append(NotchMenuItem(title: "End session", icon: "stop.fill") { viewModel.resetPomodoro() })
        case .paused:
            items.append(NotchMenuItem(title: "Resume", icon: "play.fill") { viewModel.togglePomodoro() })
            items.append(NotchMenuItem(title: "End session", icon: "stop.fill") { viewModel.resetPomodoro() })
        case .finished:
            items.append(NotchMenuItem(title: "Restart", icon: "arrow.clockwise") {
                viewModel.acknowledgePomodoro()
                viewModel.togglePomodoro()
            })
            items.append(NotchMenuItem(title: "Dismiss", icon: "xmark") { viewModel.acknowledgePomodoro() })
        }
        presentation.present(NotchMenu(
            title: "Focus timer",
            anchor: pomodoroMenuAnchor,
            items: items,
            style: style
        ))
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
        presentation.present(NotchMenu(title: folder.name, anchor: folderHeaderMenuAnchor, items: [
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

    private func presentTagActions(_ tag: AppViewModel.TagSummary, count: Int, anchor: CGRect) {
        presentation.present(NotchMenu(title: "@\(tag.name)", anchor: anchor, items: [
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
        // Only the iridescent chrome lives inside the 30 Hz timeline; the
        // TextField and its content must not re-render on every tick.
        captureFieldContent
            .background {
                iridescentTimeline { angle in
                    composerBackground(angle: angle)
                }
            }
            .clipShape(composerShape)
            .overlay {
                iridescentTimeline { angle in
                    composerBorder(angle: angle)
                }
            }
            .contentShape(composerShape)
            .shadow(color: .black.opacity(0.42), radius: 14, y: 8)
            .animation(reduceMotion ? nil : NotchMotion.content, value: viewModel.composerHasImages)
    }

    private func iridescentTimeline<Chrome: View>(
        @ViewBuilder chrome: @escaping (Angle) -> Chrome
    ) -> some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: reduceMotion || focusedField != .unifiedInput
            )
        ) { context in
            chrome(composerIridescenceAngle(at: context.date))
        }
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
            if focusedField != .unifiedInput {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .frame(width: 24, height: 24)
                    .transition(.opacity)
            }

            TextField("Search, add an item, or / to see actions", text: $viewModel.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1...2)
                .focused($focusedField, equals: .unifiedInput)
                .onPasteCommand(of: [.image, .fileURL]) { providers in
                    _ = viewModel.acceptPastedImages(providers)
                }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        viewModel.submitComposer(capturingAnyway: true)
                    } else {
                        viewModel.handleComposerReturn()
                    }
                    return .handled
                }
                .onKeyPress(.tab) {
                    if viewModel.acceptSelectedComposerCommand() { return .handled }
                    return viewModel.acceptSelectedTagSuggestion() ? .handled : .ignored
                }
                .onKeyPress(.upArrow) {
                    if !viewModel.composerCommandSuggestions.isEmpty {
                        viewModel.moveComposerCommandSelection(by: -1)
                        return .handled
                    }
                    guard !viewModel.tagSuggestions.isEmpty else { return .ignored }
                    viewModel.moveTagSuggestionSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if !viewModel.composerCommandSuggestions.isEmpty {
                        viewModel.moveComposerCommandSelection(by: 1)
                        return .handled
                    }
                    if !viewModel.tagSuggestions.isEmpty {
                        viewModel.moveTagSuggestionSelection(by: 1)
                        return .handled
                    }
                    // Enter the ledger with the keyboard from the composer.
                    return viewModel.moveLedgerSelection(by: 1) ? .handled : .ignored
                }
                .accessibilityLabel("Search, add an item, or / to see actions")
                .accessibilityHint(unifiedInputHint)

            if viewModel.canSubmitComposer {
                Button {
                    viewModel.submitComposer()
                } label: {
                    HStack(spacing: 5) {
                        Text(viewModel.composerActionLabel)
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
                    viewModel.isFolderCommandActive
                        ? "Create a folder"
                        : viewModel.canCreateStandaloneTag
                            ? "Create this tag group"
                            : "Add this thought to \(viewModel.captureDestinationName)"
                )
                .accessibilityLabel(
                    viewModel.isFolderCommandActive
                        ? "Create folder"
                        : viewModel.canCreateStandaloneTag
                            ? "Create tag group"
                            : "Add thought to \(viewModel.captureDestinationName)"
                )
            } else if viewModel.composerHasMatches {
                Text("\(viewModel.searchMatchCount) \(viewModel.searchMatchCount == 1 ? "match" : "matches")")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .lineLimit(1)
                    .help("Return opens the first match · ⌘Return adds a new item anyway")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: composerTextRowHeight)
        .animation(composerFocusAnimation, value: focusedField)
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

    private var commandAutocomplete: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.composerCommandSuggestions.enumerated()), id: \.element.id) { index, command in
                Button {
                    viewModel.acceptComposerCommand(command)
                    focusComposer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: command.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NotchTheme.mint)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(command.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(NotchTheme.primaryText)
                            Text(command.detail)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(NotchTheme.secondaryText)
                        }
                        Spacer()
                        Text("/\(command.rawValue)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(NotchTheme.tertiaryText)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(
                        index == viewModel.selectedComposerCommandIndex
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
        .accessibilityLabel("Composer commands")
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
        RoundedRectangle(cornerRadius: NotchTheme.surfaceBottomRadius, style: .continuous)
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

    private func handleAppearanceRequest(_ request: PanelMorphRequest?) {
        if reduceMotion {
            finishAppearanceImmediately()
            if viewModel.surfaceState == .expanded { focusComposer() }
            return
        }

        guard let request else {
            finishAppearanceImmediately()
            if viewModel.surfaceState == .expanded { focusComposer() }
            return
        }
        guard ExpandedSurfaceRevealPlan.applies(to: request, reduceMotion: false) else {
            appearanceTask?.cancel()
            return
        }

        switch request.phase {
        case .prepared:
            prepareStaggeredAppearance()
        case .active:
            guard let plan = ExpandedSurfaceRevealPlan.resolve(
                for: request,
                reduceMotion: false
            ) else { return }
            beginStaggeredAppearance(plan)
        case .settled:
            finishAppearanceImmediately()
        }
    }

    private func prepareStaggeredAppearance() {
        appearanceTask?.cancel()
        appearanceGeneration = nil
        withoutAppearanceAnimation {
            ledgerAppearance = 0
            composerAppearance = 0
        }
    }

    private func beginStaggeredAppearance(_ plan: ExpandedSurfaceRevealPlan) {
        guard appearanceGeneration != plan.generation else { return }
        prepareStaggeredAppearance()
        appearanceGeneration = plan.generation

        appearanceTask = Task { @MainActor in
            if plan.ledgerDelay > 0 {
                try? await Task.sleep(for: .seconds(plan.ledgerDelay))
            }
            guard !Task.isCancelled,
                  morphCoordinator.request?.generation == plan.generation else { return }
            withAnimation(NotchMotion.easeOut(duration: plan.revealDuration)) {
                ledgerAppearance = 1
            }

            let composerGap = max(0, plan.composerDelay - plan.ledgerDelay)
            if composerGap > 0 {
                try? await Task.sleep(for: .seconds(composerGap))
            }
            guard !Task.isCancelled,
                  morphCoordinator.request?.generation == plan.generation else { return }
            withAnimation(NotchMotion.easeOut(duration: plan.revealDuration)) {
                composerAppearance = 1
            }
            if viewModel.surfaceState == .expanded { focusComposer() }
        }
    }

    private func finishAppearanceImmediately() {
        appearanceTask?.cancel()
        appearanceGeneration = nil
        withoutAppearanceAnimation {
            ledgerAppearance = 1
            composerAppearance = 1
        }
    }

    private func withoutAppearanceAnimation(_ updates: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
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
        ScrollViewReader { proxy in
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
            .onPreferenceChange(LedgerDragRegionPreferenceKey.self) { [dragRegionStore] in
                dragRegionStore.regions = $0
            }
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
            .simultaneousGesture(folderReorderGesture)
            .scrollIndicators(.hidden)
            .onChange(of: selectedLedgerScrollTarget) { _, target in
                scrollToSelectedLedgerRow(target, using: proxy)
            }
        }
    }

    private func scrollToSelectedLedgerRow(
        _ target: LedgerScrollTarget?,
        using proxy: ScrollViewProxy
    ) {
        ledgerScrollTask?.cancel()
        guard let target, reorderSession == nil else { return }

        ledgerScrollTask = Task { @MainActor in
            // Lazy rows and a post-deletion replacement selection may not exist
            // until the next render turn. Ignore a request if navigation has
            // already advanced to a newer target by then.
            await Task.yield()
            guard !Task.isCancelled,
                  selectedLedgerScrollTarget == target,
                  reorderSession == nil else { return }

            if reduceMotion {
                proxy.scrollTo(target)
            } else {
                withAnimation(NotchMotion.keyboardScroll) {
                    // Omitting an anchor asks SwiftUI for the smallest movement
                    // that makes the selected row visible.
                    proxy.scrollTo(target)
                }
            }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        if !viewModel.visibleTagGroups.isEmpty {
            tagShelf
        }

        if !previewFolders.isEmpty {
            ForEach(previewFolders) { folder in
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
                    TagShelfEntry(
                        group: group,
                        onSearch: {
                            viewModel.search(for: group.tag)
                            focusComposer()
                        },
                        onActions: { anchor in
                            presentTagActions(group.tag, count: group.count, anchor: anchor)
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private struct TagShelfEntry: View {
        let group: AppViewModel.TagGroup
        let onSearch: () -> Void
        let onActions: (CGRect) -> Void

        @State private var actionsAnchor: CGRect = .zero

        var body: some View {
            HStack(spacing: 3) {
                Button(action: onSearch) {
                    TonalTagLabel(name: group.name, count: group.count, colorSeed: group.tag.colorSeed)
                }
                .buttonStyle(NotchPressButtonStyle())
                Button {
                    onActions(actionsAnchor)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .menuAnchor($actionsAnchor)
                .accessibilityLabel("Actions for tag \(group.name)")
            }
            .accessibilityLabel("Tag \(group.name), \(group.count) \(group.count == 1 ? "item" : "items")")
        }
    }

    private func folderRow(_ folder: AppViewModel.FolderSummary) -> some View {
        FolderLedgerRow(
            folder: folder,
            itemCount: viewModel.matchingItemCount(in: folder.id),
            isSelected: viewModel.selectedFolderID == folder.id,
            isDropTarget: targetedFolderID == folder.id,
            reduceMotion: reduceMotion,
            onOpen: { navigate(forward: true) { viewModel.openFolder(folder) } },
            onRename: { beginRenaming(folder) },
            onDelete: { presentDeleteFolder(folder) }
        )
        .overlay {
            LedgerInsertionIndicator(
                placement: folderReorderSession?.targetID == folder.id ? folderReorderSession?.placement : nil
            )
        }
        .ledgerDragRegion(.folder(folder.id))
        .id(LedgerScrollTarget.folder(folder.id))
    }

    private func reorderableRow(_ item: AppViewModel.LedgerItem) -> some View {
        let target = reorderTarget?.targetID == item.id ? reorderTarget : nil
        let isDragSource = dragPresentation?.item.id == item.id
        return LedgerRowView(
            item: item,
            isSelected: viewModel.selectedItemID == item.id,
            isEditing: viewModel.itemEditSession?.itemID == item.id,
            timeFormat: viewModel.timeFormat,
            showsSearchLocation: viewModel.isShowingGlobalSearchResults,
            viewModel: viewModel
        )
            .equatable()
            .opacity(isDragSource ? 0.18 : 1)
            .overlay {
                LedgerInsertionIndicator(placement: target?.placement)
            }
            .ledgerDragRegion(.row(item.id))
            .id(LedgerScrollTarget.item(item.id))
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
            .transition(ledgerRowRemovalTransition(for: item))
    }

    private func ledgerRowRemovalTransition(for item: AppViewModel.LedgerItem) -> AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }
        return .modifier(
            active: LedgerRowExitModifier(
                progress: 1,
                wasCompleted: item.isCompleted
            ),
            identity: LedgerRowExitModifier(
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
                          let source = dragRegionStore.regions.first(where: { region, frame in
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

    private var folderReorderGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("ledger-feed"))
            .onChanged { value in
                if folderReorderSession == nil {
                    guard viewModel.canReorderFolders,
                          let source = dragRegionStore.regions.first(where: { region, frame in
                              if case .folder = region { return frame.contains(value.startLocation) }
                              return false
                          }),
                          case let .folder(folderID) = source.key else { return }
                    folderReorderSession = FolderReorderSession(draggedFolderID: folderID)
                }

                guard var session = folderReorderSession else { return }
                guard let target = dragRegionStore.regions.first(where: { region, frame in
                    if case .folder = region { return frame.contains(value.location) }
                    return false
                }), case let .folder(targetID) = target.key, targetID != session.draggedFolderID else {
                    if session.targetID != nil {
                        session.targetID = nil
                        folderReorderSession = session
                    }
                    return
                }

                let placement: AppViewModel.ReorderPlacement = value.location.y < target.value.midY ? .before : .after
                guard session.targetID != targetID || session.placement != placement else { return }
                session.targetID = targetID
                session.placement = placement
                if reduceMotion {
                    folderReorderSession = session
                } else {
                    withAnimation(NotchMotion.reorder) { folderReorderSession = session }
                }
            }
            .onEnded { _ in
                guard let session = folderReorderSession else { return }
                defer { folderReorderSession = nil }
                guard let targetID = session.targetID else { return }
                let update = {
                    _ = viewModel.reorderFolder(
                        folderID: session.draggedFolderID,
                        relativeTo: targetID,
                        placement: session.placement
                    )
                }
                if reduceMotion {
                    update()
                } else {
                    withAnimation(NotchMotion.reorder, update)
                }
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
            regions: dragRegionStore.regions,
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
            regions: dragRegionStore.regions
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
