import NotchCaptureSync
import SwiftUI

struct MobileRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: MobileCaptureModel
    @State private var showsComposer = false

    var body: some View {
        NavigationStack {
            Group {
                if model.visibleRecords.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptySymbol,
                        description: Text(emptyDescription)
                    )
                } else {
                    List(model.visibleRecords) { record in
                        NavigationLink {
                            CaptureDetailView(model: model, record: record)
                        } label: {
                            CaptureRow(record: record)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if record.kind == .task || model.filter == .completed {
                                Button {
                                    Task { await model.toggleCompletion(record) }
                                } label: {
                                    Label(record.isCompleted ? "Reopen" : "Complete", systemImage: record.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if model.filter == .archive || model.filter == .trash {
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    Task { await model.restore(record) }
                                }
                                .tint(.blue)
                            } else {
                                Button("Archive", systemImage: "archivebox") {
                                    Task { await model.archive(record) }
                                }
                                .tint(.indigo)
                                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                                    Task { await model.trash(record) }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await model.synchronize() }
                }
            }
            .navigationTitle(model.filter.rawValue)
            .searchable(text: $model.searchText, prompt: "Search captures")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("View", selection: $model.filter) {
                            ForEach(MobileCaptureModel.Filter.allCases) { filter in
                                Label(filter.rawValue, systemImage: symbol(for: filter)).tag(filter)
                            }
                        }
                    } label: {
                        Label("Change view", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsComposer = true
                    } label: {
                        Label("New capture", systemImage: "square.and.pencil")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                syncStatus
            }
            .sheet(isPresented: $showsComposer) {
                CaptureComposer(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("iCloud Sync", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.synchronize() }
            }
        }
    }

    private var syncStatus: some View {
        HStack(spacing: 7) {
            if model.isSyncing {
                ProgressView().controlSize(.mini)
                Text("Syncing")
            } else if let syncIssue = model.syncIssue {
                Image(systemName: "exclamationmark.icloud")
                Text(syncIssue)
            } else {
                Image(systemName: "checkmark.icloud")
                Text(model.lastSyncedAt.map { "Synced \($0.formatted(date: .omitted, time: .shortened))" } ?? "Saved on this iPhone")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var emptyTitle: String { model.searchText.isEmpty ? "Nothing here" : "No matches" }
    private var emptySymbol: String { model.searchText.isEmpty ? symbol(for: model.filter) : "magnifyingglass" }
    private var emptyDescription: String { model.filter == .inbox ? "Capture a thought before it gets away." : "Captures in this view will appear here." }

    private func symbol(for filter: MobileCaptureModel.Filter) -> String {
        switch filter {
        case .inbox: "tray"
        case .tasks: "checklist"
        case .due: "calendar.badge.clock"
        case .completed: "checkmark.circle"
        case .archive: "archivebox"
        case .trash: "trash"
        }
    }
}

private struct CaptureRow: View {
    let record: CaptureRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.kind == .task ? (record.isCompleted ? "checkmark.circle.fill" : "circle") : "note.text")
                .foregroundStyle(record.isCompleted ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text(record.text)
                    .lineLimit(3)
                    .strikethrough(record.isCompleted, color: .secondary)
                    .foregroundStyle(record.isCompleted ? .secondary : .primary)
                HStack(spacing: 8) {
                    if record.isPinned { Label("Pinned", systemImage: "pin.fill") }
                    if let folder = record.folderName { Label(folder, systemImage: "folder") }
                    if let dueDate = record.dueDate { Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar") }
                    Text(record.updatedAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CaptureComposer: View {
    @Environment(\.dismiss) private var dismiss
    let model: MobileCaptureModel
    @State private var text = ""
    @State private var kind: CaptureKind = .note

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Kind", selection: $kind) {
                    Label("Note", systemImage: "note.text").tag(CaptureKind.note)
                    Label("Task", systemImage: "checkmark.circle").tag(CaptureKind.task)
                }
                .pickerStyle(.segmented)

                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("What’s on your mind?")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 17)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding()
            .navigationTitle("New Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.capture(text, as: kind) { dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct CaptureDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let model: MobileCaptureModel
    let record: CaptureRecord
    @State private var text: String
    @State private var kind: CaptureKind
    @State private var dueDate: Date?

    private var currentRecord: CaptureRecord {
        model.records.first(where: { $0.id == record.id }) ?? record
    }

    init(model: MobileCaptureModel, record: CaptureRecord) {
        self.model = model
        self.record = record
        _text = State(initialValue: record.text)
        _kind = State(initialValue: record.kind)
        _dueDate = State(initialValue: record.dueDate)
    }

    var body: some View {
        Form {
            Section {
                Picker("Kind", selection: $kind) {
                    Text("Note").tag(CaptureKind.note)
                    Text("Task").tag(CaptureKind.task)
                }
                TextEditor(text: $text)
                    .frame(minHeight: 180)
            }
            if kind == .task {
                Section("Schedule") {
                    Toggle("Due date", isOn: Binding(
                        get: { dueDate != nil },
                        set: { dueDate = $0 ? (dueDate ?? .now) : nil }
                    ))
                    if dueDate != nil {
                        DatePicker(
                            "Date",
                            selection: Binding(
                                get: { dueDate ?? .now },
                                set: { dueDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }
            }
            Section {
                Button(currentRecord.isPinned ? "Unpin" : "Pin", systemImage: currentRecord.isPinned ? "pin.slash" : "pin") {
                    Task { await model.togglePinned(currentRecord) }
                }
                if kind == .task {
                    Button(currentRecord.isCompleted ? "Reopen task" : "Complete task", systemImage: currentRecord.isCompleted ? "arrow.uturn.backward" : "checkmark.circle") {
                        Task { await model.toggleCompletion(currentRecord) }
                    }
                }
            }
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    Task {
                        await model.update(record, text: text, kind: kind, dueDate: dueDate)
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
