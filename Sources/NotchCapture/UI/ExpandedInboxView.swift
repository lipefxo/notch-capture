import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ExpandedInboxView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var focusedField: Field?

    private let floatingComposerMargin: CGFloat = 18
    private let floatingComposerHeight: CGFloat = 60
    private let floatingGlassHeight: CGFloat = 134
    private let ledgerBottomClearance: CGFloat = 96

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
                    .transition(.opacity)
            }
        }
        .onDrop(of: acceptedDropTypes, isTargeted: dropTargetBinding) { providers in
            viewModel.acceptDrop(providers)
        }
        .onExitCommand { viewModel.dismiss() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch Capture inbox")
    }

    private var floatingComposer: some View {
        ZStack(alignment: .bottom) {
            floatingGlassFade

            captureField
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
                Text("Inbox")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(NotchTheme.primaryText)

                Spacer()

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

    private var captureField: some View {
        HStack(spacing: 13) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(NotchTheme.secondaryText)
                .frame(width: 24, height: 24)

            TextField("Search or add a thought", text: $viewModel.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1...2)
                .focused($focusedField, equals: .unifiedInput)
                .onSubmit { viewModel.submitComposer() }
                .accessibilityLabel("Search or add a thought")
                .accessibilityHint(unifiedInputHint)

            if viewModel.canAddComposerText {
                Button {
                    viewModel.submitComposer()
                } label: {
                    HStack(spacing: 5) {
                        Text("Add")
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
                .buttonStyle(.plain)
                .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .keyboardShortcut(.return, modifiers: .command)
                .help("Add this thought to Inbox")
                .accessibilityLabel("Add thought to Inbox")
            } else if viewModel.composerHasMatches {
                Text("\(viewModel.visibleItems.count) \(viewModel.visibleItems.count == 1 ? "match" : "matches")")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: floatingComposerHeight)
        .background {
            ZStack {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NotchTheme.field.opacity(reduceTransparency ? 1 : 0.72))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    colorSchemeContrast == .increased
                        ? Color.white.opacity(0.18)
                        : NotchTheme.controlStroke,
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.42), radius: 14, y: 8)
    }

    private var unifiedInputHint: String {
        if viewModel.canAddComposerText {
            return "No matching items. Press Return to add this thought to Inbox."
        }
        if viewModel.composerHasMatches {
            return "Matching items are shown below."
        }
        return "Type to search. If no item matches, press Return to add a new thought."
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterButton(.all, width: 64)
            filterButton(.tasks, width: 76)

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        [.all, .tasks].contains(viewModel.filter)
                            ? NotchTheme.control
                            : NotchTheme.selectedControl
                    )
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
    }

    private func filterButton(_ filter: AppViewModel.InboxFilter, width: CGFloat) -> some View {
        Button(filter.rawValue) {
            viewModel.filter = filter
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(viewModel.filter == filter ? NotchTheme.primaryText : NotchTheme.secondaryText)
        .frame(width: width, height: 34)
        .background(viewModel.filter == filter ? NotchTheme.selectedControl : NotchTheme.control)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityAddTraits(viewModel.filter == filter ? .isSelected : [])
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
            } else if viewModel.visibleItems.isEmpty {
                EmptyInboxView(
                    filter: viewModel.filter,
                    query: viewModel.composerText,
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
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var feedContent: some View {
        if !viewModel.pinnedItems.isEmpty {
            LedgerSectionHeader(title: "Pinned", count: viewModel.pinnedItems.count)
            ForEach(viewModel.pinnedItems) { item in
                LedgerRowView(item: item, viewModel: viewModel)
            }
        }

        if !viewModel.todayItems.isEmpty {
            LedgerSectionHeader(title: "Today", count: viewModel.todayItems.count)
            ForEach(viewModel.todayItems) { item in
                LedgerRowView(item: item, viewModel: viewModel)
            }
        }

        if !viewModel.earlierItems.isEmpty {
            LedgerSectionHeader(title: "Earlier", count: viewModel.earlierItems.count)
            ForEach(viewModel.earlierItems) { item in
                LedgerRowView(item: item, viewModel: viewModel)
            }
        }
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

private struct LedgerRowView: View {
    let item: AppViewModel.LedgerItem
    @ObservedObject var viewModel: AppViewModel
    @State private var isHovered = false

    private var isSelected: Bool { viewModel.selectedItemID == item.id }
    private var showsActions: Bool { isHovered || isSelected }
    private var isAttachmentOnly: Bool {
        item.attachments.count == 1 && item.detail.isEmpty && item.kind == .note
    }

    var body: some View {
        Group {
            if isAttachmentOnly, let attachment = item.attachments.first {
                AttachmentLedgerRow(item: item, attachment: attachment)
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

            if showsActions {
                inlineActions
                    .layoutPriority(1)
            }
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
            }

            Spacer(minLength: 8)

            if !showsActions {
                Text(CaptureTimestampFormatter.string(from: item.createdAt))
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(NotchTheme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedItemID = isSelected ? nil : item.id
        }
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
            .buttonStyle(.plain)
            .notchHitTarget(Rectangle())
            .help(item.isCompleted ? "Mark incomplete" : "Complete")
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Complete item")
        }
    }

    private var subtitle: String? {
        if !item.detail.isEmpty { return item.detail }
        if let dueDate = item.dueDate {
            if Calendar.current.isDateInToday(dueDate) { return "Today" }
            return dueDate.formatted(date: .abbreviated, time: .omitted)
        }
        if let sourceApp = item.sourceApp { return "Selected from \(sourceApp)" }
        if let listName = item.listName { return listName }
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

        if !viewModel.lists.isEmpty {
            Menu {
                ForEach(viewModel.lists, id: \.self) { list in
                    Button(list) { viewModel.move(item, to: list) }
                }
            } label: {
                Label("Move", systemImage: "tag")
            }
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
                    Text(CaptureTimestampFormatter.string(from: item.createdAt))
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
        .buttonStyle(.plain)
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
            Text(isSearching ? "Press Return to add “\(query)” to Inbox." : emptyDetail)
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
        switch filter {
        case .all: "Your pocket is clear"
        case .tasks: "No open tasks"
        case .due: "Nothing is due"
        case .completed: "No completed items"
        case .archive: "Archive is empty"
        case .trash: "Trash is empty"
        }
    }

    private var emptyDetail: String {
        filter == .all ? "Press ⌃⇧Space anywhere to keep the current selection." : "Items in this view will appear here."
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
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
