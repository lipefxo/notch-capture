import NotchCaptureSync
import SwiftUI

struct WatchRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: WatchCaptureModel
    @State private var showsCapture = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showsCapture = true
                } label: {
                    Label("Capture", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                }
                .tint(.accentColor)

                if let message = model.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if model.recent.isEmpty {
                    Text("Your latest notes and tasks will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Section("Recent") {
                        ForEach(model.recent) { record in
                            if record.kind == .task {
                                Button {
                                    Task { await model.toggleCompletion(record) }
                                } label: {
                                    WatchCaptureLabel(record: record)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Complete \(record.text)")
                            } else {
                                WatchCaptureLabel(record: record)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Notch Capture")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isSyncing { ProgressView() }
                }
            }
            .refreshable { await model.synchronize() }
            .sheet(isPresented: $showsCapture) {
                WatchComposer(model: model)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.synchronize() }
            }
        }
    }
}

private struct WatchCaptureLabel: View {
    let record: CaptureRecord

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: record.kind == .task ? "circle" : "note.text")
                .foregroundStyle(.secondary)
            Text(record.text)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
    }
}

private struct WatchComposer: View {
    @Environment(\.dismiss) private var dismiss
    let model: WatchCaptureModel
    @State private var text = ""
    @State private var kind: CaptureKind = .note

    var body: some View {
        NavigationStack {
            Form {
                TextField("Speak or scribble", text: $text, axis: .vertical)
                Picker("Kind", selection: $kind) {
                    Text("Note").tag(CaptureKind.note)
                    Text("Task").tag(CaptureKind.task)
                }
                Button("Save") {
                    Task {
                        if await model.capture(text, kind: kind) { dismiss() }
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("New Capture")
        }
    }
}
