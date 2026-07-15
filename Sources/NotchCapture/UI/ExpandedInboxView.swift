import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ExpandedInboxView: View {
    @ObservedObject var viewModel: AppViewModel
    @FocusState private var focusedField: Field?
    @State private var showsSearch = false

    private enum Field {
        case composer
        case search
    }

    var body: some View {
        VStack(spacing: 0) {
            notchHeader
            ledgerBody
        }
        .frame(width: NotchTheme.width, height: NotchTheme.maxHeight)
        .background(NotchSurfaceBackground())
        .clipShape(NotchHugShape(bottomRadius: 24))
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

    private var notchHeader: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Text("Inbox")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                if viewModel.isNotchFlowRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(NotchTheme.mint)
                            .frame(width: 5, height: 5)
                        Text("Companion")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(NotchTheme.secondaryText)
                    .accessibilityLabel("NotchFlow companion mode active")
                }

                Button {
                    showsSearch.toggle()
                    if showsSearch { focusedField = .search }
                } label: {
                    Image(systemName: showsSearch ? "xmark" : "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(PressableIconButtonStyle())
                .help(showsSearch ? "Close search" : "Search")
                .accessibilityLabel(showsSearch ? "Close search" : "Search inbox")

                Button {
                    viewModel.surfaceState = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(PressableIconButtonStyle())
                .help("Settings")
                .accessibilityLabel("Open settings")
            }

            if showsSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.tertiaryText)
                    TextField("Search notes, tasks, and files", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .focused($focusedField, equals: .search)
                        .accessibilityLabel("Search inbox")
                }
                .padding(.horizontal, 10)
                .frame(height: 29)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(NotchTheme.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private var ledgerBody: some View {
        VStack(spacing: 0) {
            quickComposer
            filterBar

            if let error = viewModel.errorMessage {
                InlineErrorView(message: error) {
                    viewModel.errorMessage = nil
                    focusedField = .composer
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if viewModel.visibleItems.isEmpty {
                EmptyInboxView(
                    filter: viewModel.filter,
                    isSearching: !viewModel.searchText.isEmpty,
                    onCompose: { focusedField = .composer }
                )
            } else {
                itemFeed
            }
        }
        .background(NotchTheme.graphite)
    }

    private var quickComposer: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NotchTheme.mint)

            TextField("Capture a thought…", text: $viewModel.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...3)
                .focused($focusedField, equals: .composer)
                .onSubmit { viewModel.submitComposer() }
                .accessibilityLabel("Quick capture")
                .accessibilityHint("Type a note and press Return to save it")

            Button {
                viewModel.beginScreenshot()
            } label: {
                Image(systemName: "viewfinder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Capture screen region · ⌃⇧S")
            .accessibilityLabel("Capture a screen region")

            if !viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Save") { viewModel.submitComposer() }
                    .buttonStyle(MintButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                ShortcutKeycap(value: "↩")
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NotchTheme.raisedGraphite.opacity(0.66))
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            filterButton(.all)
            filterButton(.tasks)

            Menu {
                ForEach([AppViewModel.InboxFilter.due, .completed, .archive, .trash]) { filter in
                    Button {
                        viewModel.filter = filter
                    } label: {
                        Label(filter.rawValue, systemImage: filter.systemImage)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 25, height: 24)
                    .foregroundStyle(NotchTheme.secondaryText)
                    .background(Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More inbox filters")

            if ![.all, .tasks].contains(viewModel.filter) {
                Label(viewModel.filter.rawValue, systemImage: viewModel.filter.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTheme.mint)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(NotchTheme.mint.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            Spacer()

            Text("\(viewModel.visibleItems.count) items")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NotchTheme.tertiaryText)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private func filterButton(_ filter: AppViewModel.InboxFilter) -> some View {
        Button(filter.rawValue) {
            viewModel.filter = filter
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(viewModel.filter == filter ? Color.black.opacity(0.82) : NotchTheme.secondaryText)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(viewModel.filter == filter ? NotchTheme.mint : Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityAddTraits(viewModel.filter == filter ? .isSelected : [])
    }

    private var itemFeed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) { feedContent }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var feedContent: some View {
        if !viewModel.pinnedItems.isEmpty {
            LedgerSectionHeader(title: "Pinned", count: viewModel.pinnedItems.count)
                .padding(.top, 2)
            ForEach(viewModel.pinnedItems) { item in
                LedgerRowView(item: item, viewModel: viewModel)
            }
        }

        if !viewModel.todayItems.isEmpty {
            LedgerSectionHeader(title: "Today", count: viewModel.todayItems.count)
                .padding(.top, viewModel.pinnedItems.isEmpty ? 2 : 8)
            ForEach(viewModel.todayItems) { item in
                LedgerRowView(item: item, viewModel: viewModel)
            }
        }

        if !viewModel.earlierItems.isEmpty {
            LedgerSectionHeader(title: "Earlier", count: viewModel.earlierItems.count)
                .padding(.top, 8)
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

private struct LedgerRowView: View {
    let item: AppViewModel.LedgerItem
    @ObservedObject var viewModel: AppViewModel
    @State private var isHovered = false

    private var isSelected: Bool { viewModel.selectedItemID == item.id }
    private var showsActions: Bool { isHovered || isSelected }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Button {
                    viewModel.toggleComplete(item)
                } label: {
                    Image(systemName: completionSymbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.isCompleted ? NotchTheme.mint : Color.white.opacity(0.28))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(item.isCompleted ? "Mark incomplete" : "Complete")
                .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Complete item")

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.isCompleted ? NotchTheme.secondaryText : Color.white.opacity(0.9))
                        .strikethrough(item.isCompleted, color: NotchTheme.secondaryText)
                        .lineLimit(2)

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(isSelected ? 4 : 2)
                            .lineSpacing(2)
                    }
                }

                Spacer(minLength: 6)

                if showsActions {
                    inlineActions
                } else if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(NotchTheme.mint.opacity(0.7))
                        .padding(.top, 3)
                        .accessibilityLabel("Pinned")
                }
            }

            if !item.attachments.isEmpty {
                VStack(spacing: 5) {
                    ForEach(item.attachments) { attachment in
                        AttachmentRow(attachment: attachment)
                    }
                }
                .padding(.leading, 27)
            }

            HStack(spacing: 6) {
                if let list = item.listName {
                    Label(list, systemImage: "folder")
                }
                if let dueDate = item.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                if let source = item.sourceApp {
                    Label(source, systemImage: "arrow.down.left")
                }
                Spacer()
                Text(item.createdAt, style: .relative)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(NotchTheme.tertiaryText)
            .padding(.leading, 27)
        }
        .padding(10)
        .background(isSelected ? NotchTheme.raisedGraphite : Color.white.opacity(isHovered ? 0.055 : 0.032))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isSelected ? NotchTheme.mint.opacity(0.28) : Color.white.opacity(0.055), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture {
            viewModel.selectedItemID = isSelected ? nil : item.id
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kind == .task ? "Task" : "Note"): \(item.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var completionSymbol: String {
        if item.isCompleted { return "checkmark.circle.fill" }
        return item.kind == .task ? "circle" : "circle.dashed"
    }

    private var inlineActions: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.togglePin(item)
            } label: {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
            }
            .help(item.isPinned ? "Unpin" : "Pin")
            .accessibilityLabel(item.isPinned ? "Unpin item" : "Pin item")

            Menu {
                ForEach(viewModel.lists, id: \.self) { list in
                    Button(list) { viewModel.move(item, to: list) }
                }
            } label: {
                Image(systemName: "folder")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Move")
            .accessibilityLabel("Move item")

            Menu {
                Button("Today") {
                    viewModel.setDueDate(Calendar.current.startOfDay(for: .now), for: item)
                }
                Button("Tomorrow") {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)
                    viewModel.setDueDate(tomorrow, for: item)
                }
                if item.dueDate != nil {
                    Divider()
                    Button("Clear due date") { viewModel.setDueDate(nil, for: item) }
                }
            } label: {
                Image(systemName: "calendar")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Due date")
            .accessibilityLabel("Set due date")

            if viewModel.filter == .trash {
                Button { viewModel.restore(item) } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Restore")
                    .accessibilityLabel("Restore item")
                Button { viewModel.deletePermanently(item) } label: { Image(systemName: "trash.slash") }
                    .help("Delete permanently")
                    .accessibilityLabel("Delete item permanently")
            } else {
                if viewModel.filter == .archive {
                    Button { viewModel.restore(item) } label: { Image(systemName: "arrow.uturn.backward") }
                        .help("Restore to Inbox")
                        .accessibilityLabel("Restore item to Inbox")
                } else {
                    Button { viewModel.archive(item) } label: { Image(systemName: "archivebox") }
                        .help("Archive")
                        .accessibilityLabel("Archive item")
                }
                Button { viewModel.trash(item) } label: { Image(systemName: "trash") }
                    .help("Move to Trash")
                    .accessibilityLabel("Move item to Trash")
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .buttonStyle(InlineActionButtonStyle())
    }
}

private struct InlineActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? NotchTheme.mint : Color.white.opacity(0.62))
            .frame(width: 22, height: 22)
            .background(Color.black.opacity(configuration.isPressed ? 0.42 : 0.25))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct AttachmentRow: View {
    let attachment: AppViewModel.LedgerAttachment

    var body: some View {
        Button {
            if let url = attachment.previewURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
            if let url = attachment.previewURL, url.isFileURL {
                QuickLookThumbnail(url: url, fallbackSymbol: symbol)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(attachment.kind == .link ? NotchTheme.mint : Color.white.opacity(0.62))
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
                if let subtitle = attachment.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(NotchTheme.tertiaryText)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 31)
            .background(Color.black.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
        }
        .frame(width: 22, height: 22)
        .background(Color.black.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 44, height: 44),
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
    let isSearching: Bool
    let onCompose: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            Spacer()
            Image(systemName: isSearching ? "magnifyingglass" : filter.systemImage)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(NotchTheme.mint.opacity(0.72))
            Text(isSearching ? "Nothing found" : emptyTitle)
                .font(.system(size: 13, weight: .semibold))
            Text(isSearching ? "Try a different word or clear search." : emptyDetail)
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 230)
            if !isSearching && filter == .all {
                Button("Capture something") { onCompose() }
                    .buttonStyle(MintButtonStyle())
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
            Button("Try again", action: onDismiss)
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NotchTheme.mint)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.orange.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error: \(message)")
    }
}

private struct DropTargetOverlay: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 25, weight: .medium))
            Text("Drop to capture")
                .font(.system(size: 14, weight: .semibold))
            Text("Files, images, links, or text")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.black.opacity(0.54))
        }
        .foregroundStyle(Color.black.opacity(0.78))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchTheme.mint.opacity(0.96))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .padding(12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop files, images, links, or text to capture")
    }
}
