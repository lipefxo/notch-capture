import SwiftUI

struct QuickSnippetsShelfView: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var presentation: NotchPresentationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var addCategoryAnchor: CGRect = .zero
    @FocusState private var editingSnippetID: UUID?

    private let rowHeight: CGFloat = 62

    var body: some View {
        VStack(spacing: 0) {
            header
            categoryStrip
            snippetList
        }
        .background(NotchTheme.ink)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotchTheme.hairline)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick snippets")
    }

    private var header: some View {
        HStack {
            Text("Quick snippets")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                categoryButton(
                    title: "All",
                    count: viewModel.totalQuickSnippetCount,
                    id: nil
                )

                ForEach(viewModel.orderedSnippetCategories) { category in
                    categoryButton(
                        title: category.name,
                        count: viewModel.quickSnippetCount(in: category.id),
                        id: category.id
                    )
                    .contextMenu {
                        Button("Rename") {
                            presentRenameCategory(category)
                        }
                        Button("Delete", role: .destructive) {
                            presentDeleteCategory(category)
                        }
                    }
                    .help("Right-click to rename or delete \(category.name)")
                }

                Button {
                    presentCreateCategory()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .frame(width: 30, height: 28)
                        .background(NotchTheme.control)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(NotchPressButtonStyle())
                .notchHitTarget(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .menuAnchor($addCategoryAnchor)
                .help("New snippet category")
                .accessibilityLabel("Create snippet category")
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 10)
    }

    private func categoryButton(title: String, count: Int, id: UUID?) -> some View {
        let selected = viewModel.selectedSnippetCategoryID == id
        return Button {
            withAnimation(reduceMotion ? nil : NotchMotion.content) {
                viewModel.selectSnippetCategory(id)
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .lineLimit(1)
                Text("\(count)")
                    .foregroundStyle(
                        selected ? NotchTheme.primaryAccent : NotchTheme.tertiaryText
                    )
            }
            .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? NotchTheme.primaryText : NotchTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                selected
                    ? NotchTheme.selectedLedger
                    : NotchTheme.control.opacity(0.72)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        selected
                            ? NotchTheme.primaryAccent.opacity(0.55)
                            : NotchTheme.controlStroke,
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(NotchPressButtonStyle())
        .notchHitTarget(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("\(title), \(count) \(count == 1 ? "snippet" : "snippets")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var snippetList: some View {
        if viewModel.visibleQuickSnippets.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.visibleQuickSnippets) { item in
                        snippetRow(item)
                    }
                }
                .background(CompactVerticalScrollIndicatorConfigurator())
            }
            .scrollIndicators(.visible)
            .frame(height: rowHeight * 3)
            .background(NotchTheme.raisedGraphite.opacity(0.72))
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.totalQuickSnippetCount == 0 ? "bolt" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(NotchTheme.secondaryText)
                .frame(width: 30, height: 30)
                .background(NotchTheme.control)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(emptyStateTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NotchTheme.primaryText)
                Text(emptyStateDetail)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 74)
        .background(NotchTheme.raisedGraphite.opacity(0.72))
    }

    private var emptyStateTitle: String {
        if viewModel.totalQuickSnippetCount == 0 { return "Save your first reusable snippet" }
        if let id = viewModel.selectedSnippetCategoryID,
           let category = viewModel.snippetCategories.first(where: { $0.id == id }) {
            return "No snippets in \(category.name)"
        }
        return "No quick snippets match"
    }

    private var emptyStateDetail: String {
        viewModel.totalQuickSnippetCount == 0
            ? "Type /snippet in the capture field to save text or a link."
            : "Try another category or adjust your search."
    }

    @ViewBuilder
    private func snippetRow(_ item: AppViewModel.LedgerItem) -> some View {
        if viewModel.itemEditSession?.itemID == item.id {
            snippetEditorRow(item)
        } else {
            snippetDisplayRow(item)
                .contextMenu {
                    Button("Edit") { viewModel.beginEditing(item) }
                    Button("Remove from Quick snippets", role: .destructive) {
                        viewModel.setQuickSnippet(item, enabled: false)
                    }
                }
        }
    }

    private func snippetDisplayRow(_ item: AppViewModel.LedgerItem) -> some View {
        snippetRowShell {
            snippetIcon(systemName: snippetSymbol(for: item))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let categoryName = item.snippetCategoryName {
                        Text(categoryName)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(NotchTheme.primaryAccent)
                    }
                    if !item.quickSnippetPreview.isEmpty {
                        Text(item.quickSnippetPreview)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 6)

            Button {
                viewModel.copyQuickSnippet(item)
            } label: {
                let copied = viewModel.copiedSnippetID == item.id
                HStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                    Text(copied ? "Copied" : "Copy")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(copied ? NotchTheme.completionAccent : NotchTheme.primaryAccent)
                .frame(minWidth: 58, minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchPressButtonStyle())
            .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help("Copy \(item.title)")
            .accessibilityLabel(
                viewModel.copiedSnippetID == item.id
                    ? "\(item.title) copied"
                    : "Copy \(item.title)"
            )
        }
    }

    private func snippetEditorRow(_ item: AppViewModel.LedgerItem) -> some View {
        snippetRowShell {
            snippetIcon(systemName: "pencil")

            TextField("", text: snippetEditingDraft(for: item), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1...2)
                .focused($editingSnippetID, equals: item.id)
                .onAppear { editingSnippetID = item.id }
                .onKeyPress(.return, phases: .down) { press in
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    if viewModel.saveEditing() { editingSnippetID = nil }
                    return .handled
                }
                .onExitCommand {
                    editingSnippetID = nil
                    viewModel.cancelEditing()
                }
                .accessibilityLabel("Edit \(item.title)")

            Button {
                if viewModel.saveEditing() { editingSnippetID = nil }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.completionAccent)
                    .frame(width: 26, height: 28)
            }
            .buttonStyle(NotchPressButtonStyle())
            .help("Save snippet")
            .accessibilityLabel("Save snippet")

            Button {
                editingSnippetID = nil
                viewModel.cancelEditing()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .frame(width: 26, height: 28)
            }
            .buttonStyle(NotchPressButtonStyle())
            .help("Cancel editing")
            .accessibilityLabel("Cancel editing")
        }
    }

    private func snippetIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(NotchTheme.secondaryText)
            .frame(width: 30, height: 30)
            .background(NotchTheme.control)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func snippetRowShell<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10, content: content)
            .padding(.horizontal, 20)
            .frame(height: rowHeight)
            .background(NotchTheme.raisedGraphite.opacity(0.72))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(NotchTheme.hairline)
                    .frame(height: 1)
                    .padding(.leading, 60)
            }
    }

    private func snippetEditingDraft(for item: AppViewModel.LedgerItem) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.itemEditSession?.itemID == item.id else { return item.text }
                return viewModel.itemEditSession?.draft ?? item.text
            },
            set: { draft in viewModel.updateEditingDraft(draft) }
        )
    }

    private func snippetSymbol(for item: AppViewModel.LedgerItem) -> String {
        if item.attachments.contains(where: { $0.kind == .link }) { return "link" }
        if item.kind == .task || item.text.contains("- [ ]") { return "checklist" }
        if item.title.localizedCaseInsensitiveContains("follow") { return "text.bubble" }
        return "text.alignleft"
    }

    private func presentCreateCategory() {
        presentation.present(NotchModal(
            kind: .standard,
            title: "New Snippet Category",
            message: "Categories are optional and only organize Quick snippets.",
            textFieldLabel: "Category name",
            draft: "",
            primaryTitle: "Create",
            cancelTitle: "Cancel",
            onSubmit: { name in
                viewModel.createSnippetCategory(named: name)
                    ? nil
                    : (viewModel.errorMessage ?? "Enter a unique category name.")
            },
            onCancel: {}
        ))
    }

    private func presentRenameCategory(_ category: AppViewModel.SnippetCategorySummary) {
        presentation.present(NotchModal(
            kind: .standard,
            title: "Rename Snippet Category",
            message: nil,
            textFieldLabel: "Category name",
            draft: category.name,
            primaryTitle: "Rename",
            cancelTitle: "Cancel",
            onSubmit: { name in
                viewModel.renameSnippetCategory(category, to: name)
                    ? nil
                    : (viewModel.errorMessage ?? "Enter a unique category name.")
            },
            onCancel: {}
        ))
    }

    private func presentDeleteCategory(_ category: AppViewModel.SnippetCategorySummary) {
        let count = viewModel.quickSnippetCount(in: category.id)
        presentation.present(NotchModal(
            kind: .destructive,
            title: "Delete \(category.name)?",
            message: "\(count) \(count == 1 ? "snippet" : "snippets") will remain available under All.",
            textFieldLabel: nil,
            draft: "",
            primaryTitle: "Delete Category",
            cancelTitle: "Cancel",
            onSubmit: { _ in
                viewModel.deleteSnippetCategory(category)
                return nil
            },
            onCancel: {}
        ))
    }
}
