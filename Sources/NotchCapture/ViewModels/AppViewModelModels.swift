import AppKit
import Foundation

extension Notification.Name {
    /// Posted by the panel when keyboard focus asks the selected ledger row to
    /// open its existing More Actions menu. Rows subscribe to this narrow
    /// event instead of observing every composer keystroke.
    static let notchLedgerRowActionsRequested = Notification.Name(
        "NotchCapture.ledgerRowActionsRequested"
    )
}

enum IdlePillVisibilityPolicy {
    static func shouldHide(
        autoHideExternalPill: Bool,
        pointerHasHardwareNotch: Bool?
    ) -> Bool {
        autoHideExternalPill && pointerHasHardwareNotch == false
    }
}

extension AppViewModel {
    enum SurfaceState: Equatable {
        case dormant
        case collapsed
        case collapsedActivity
        case volume
        case confirmation
        case notification
        case expanded
        case drop
        case onboarding
        case settings
        case mirror

        /// The AppKit panel state that hosts this surface. Window frames and
        /// SwiftUI chrome both size themselves from `panelState.nominalSize`.
        var panelState: PanelState {
            switch self {
            case .dormant: .dormant
            case .collapsed: .collapsed
            case .collapsedActivity: .collapsedActivity
            case .volume: .volume
            case .confirmation: .confirmation
            case .notification: .notification
            case .expanded: .expanded
            case .drop: .dropTarget
            case .onboarding: .onboarding
            case .settings: .settings
            case .mirror: .mirror
            }
        }
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

    enum OnboardingStep: Int, CaseIterable, Identifiable {
        case capture
        case organize
        case music

        var id: Self { self }

        var number: Int { rawValue + 1 }

        var isFirst: Bool { self == Self.allCases.first }

        var isFinal: Bool { self == Self.allCases.last }
    }

    enum TimeFormat: String, CaseIterable, Identifiable {
        case twelveHour = "12h"
        case twentyFourHour = "24h"

        var id: Self { self }

        static func fromStoredValue(_ value: String?) -> Self {
            switch value {
            case "12-hour": .twelveHour
            case "24-hour": .twentyFourHour
            default: Self(rawValue: value ?? "") ?? .twelveHour
            }
        }
    }

    enum KeyboardFocus: Equatable {
        case composer
        case selectedRow
        case itemEditor
        case none
    }

    /// The small portion of an item that archive/trash operations own. Keeping
    /// this separate from `LedgerItem` prevents Undo from replacing a row and
    /// accidentally erasing edits made after the action.
    struct LedgerStatusSnapshot: Equatable, Hashable, Sendable {
        let id: UUID
        let isArchived: Bool
        let isTrashed: Bool
        let resultingIsArchived: Bool
        let resultingIsTrashed: Bool

        init(
            id: UUID,
            isArchived: Bool,
            isTrashed: Bool,
            resultingIsArchived: Bool? = nil,
            resultingIsTrashed: Bool? = nil
        ) {
            self.id = id
            self.isArchived = isArchived
            self.isTrashed = isTrashed
            self.resultingIsArchived = resultingIsArchived ?? isArchived
            self.resultingIsTrashed = resultingIsTrashed ?? isTrashed
        }
    }

    /// One most-recent reversible ledger action. The snapshots carry only
    /// status fields and the post-action guard needed to avoid undoing a later
    /// archive/trash decision for the same item.
    enum LedgerUndoAction: Equatable, Sendable {
        case archive(LedgerStatusSnapshot)
        case trash(LedgerStatusSnapshot)
        case clear([LedgerStatusSnapshot])

        var itemIDs: Set<UUID> {
            switch self {
            case let .archive(snapshot), let .trash(snapshot):
                return [snapshot.id]
            case let .clear(snapshots):
                return Set(snapshots.map(\.id))
            }
        }

        var title: String {
            switch self {
            case .archive: "Undo archive"
            case .trash: "Undo move to Trash"
            case .clear: "Undo clear completed tasks"
            }
        }
    }

    enum CollapsedActivityContent: Equatable {
        case musicOnly(NowPlayingSnapshot)
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
        var faviconURL: URL?

        init(
            id: UUID = UUID(),
            kind: Kind,
            name: String,
            subtitle: String? = nil,
            previewURL: URL? = nil,
            faviconURL: URL? = nil
        ) {
            self.id = id
            self.kind = kind
            self.name = name
            self.subtitle = subtitle
            self.previewURL = previewURL
            self.faviconURL = faviconURL
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
            // Link-only captures render like ordinary text rows, so they skip
            // the note prefix. Keep it for notes that also carry a file/link.
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !attachments.isEmpty
                && !hasImageAttachments
        }

        var linkSourceSubtitle: String? {
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  attachments.count == 1,
                  let attachment = attachments.first,
                  attachment.kind == .link,
                  let subtitle = attachment.subtitle,
                  !subtitle.isEmpty else {
                return nil
            }
            return subtitle
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
            case openComposer
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
        /// Returns a user-facing error when the just-captured item cannot be
        /// moved to Trash. The confirmation remains available so the user can
        /// retry instead of losing the recovery action.
        var onUndoCapture: (UUID?) -> String? = { _ in nil }
        var onConfirmationPauseChanged: (Bool, TimeInterval) -> Void = { _, _ in }
        var onToggleComplete: (UUID) -> Void = { _ in }
        var onUpdateText: (UUID, String) -> String? = { _, _ in nil }
        var onOpenLink: (URL) -> Void = { _ in }
        var onTogglePin: (UUID) -> Void = { _ in }
        var onReorder: ([ItemOrderAssignment]) -> Void = { _ in }
        var onReorderFolders: ([FolderOrderAssignment]) -> Void = { _ in }
        var onArchive: (UUID) -> Void = { _ in }
        var onSetDueDate: (UUID, Date?) -> Void = { _, _ in }
        var onMove: (UUID, UUID?) -> Void = { _, _ in }
        var onCreateFolder: (String) -> UUID? = { _ in nil }
        var onRenameFolder: (UUID, String) -> Void = { _, _ in }
        var onDeleteFolder: (UUID) -> Void = { _ in }
        var onCreateTag: (String) -> Void = { _ in }
        var onRenameTag: (UUID, String) -> Void = { _, _ in }
        var onDeleteTag: (UUID) -> Void = { _ in }
        var onTrash: (UUID) -> Void = { _ in }
        var onRestore: (UUID) -> Void = { _ in }
        var onDeletePermanently: (UUID) -> Void = { _ in }
        var onEmptyTrash: () -> Void = {}
        var onClearCompletedTasks: () -> Void = {}
        /// Returns a user-facing error when persistence cannot apply the
        /// operation. The view model keeps the action available in that case
        /// so a transient failure cannot silently lose the undo path.
        var onUndoLedgerAction: (LedgerUndoAction) -> String? = { _ in nil }
        var onDroppedProviders: ([NSItemProvider]) -> Void = { _ in }
        var onCompleteOnboarding: () -> Void = {}
        var onSetLaunchAtLogin: (Bool) -> Void = { _ in }
        var onSetTimeFormat: (TimeFormat) -> Void = { _ in }
        var onSetCompactPresentationSize: (CompactPresentationSize) -> Void = { _ in }
        var onMusicPlayPause: () -> Void = {}
        var onMusicNext: () -> Void = {}
        var onMusicPrevious: () -> Void = {}
        var onMusicSeek: (TimeInterval) -> Void = { _ in }
        var onReconnectMedia: (NowPlayingSource) -> Void = { _ in }
        var onOpenMediaAutomationSettings: () -> Void = {}
        var onRefreshAudioOutputs: () -> Void = {}
        var onSelectAudioOutput: (AudioOutputTarget) -> Void = { _ in }
        var onSetOutputVolume: (Double) -> Void = { _ in }
        var onSetOutputMuted: (Bool) -> Void = { _ in }
        var onStartStudioLightPairing: () -> Void = {}
        var onCancelStudioLightPairing: () -> Void = {}
        var onPairStudioLight: (UUID) -> Void = { _ in }
        var onRetryStudioLight: () -> Void = {}
        var onForgetStudioLight: () -> Void = {}
        var onRefreshStudioLight: () -> Void = {}
        var onRefreshModelUsage: () -> Void = {}
        var onSetStudioLightPower: (Bool) -> Void = { _ in }
        var onSetStudioLightBrightness: (Double, Bool) -> Void = { _, _ in }
        var onSetStudioLightColorTemperature: (Int, Bool) -> Void = { _, _ in }
        var onOpenBluetoothSettings: () -> Void = {}
        var onOpenCameraSettings: () -> Void = {}
        var onSetCameraZoom: (Double) -> Void = { _ in }
        var onRecenterCamera: () -> Void = {}
        var onMoveCamera: (Double, Double) -> Void = { _, _ in }
        var onSaveCameraPreset: (CameraPresetSlot, CameraPreset) -> Void = { _, _ in }
        var onSelectCameraPreset: (CameraPresetSlot) -> Void = { _ in }
        var onOpenShortcutRecorder: (Shortcut.Action) -> Void = { _ in }
        var onCommitShortcutRecording: (Shortcut.Action, ShortcutRecording) -> String? = { _, _ in nil }
        var onCancelShortcutRecording: () -> Void = {}
        var onImport: () -> Void = {}
        var onExport: () -> Void = {}
        var onCheckForUpdates: () -> Void = {}
        var onNotificationAction: (String, String) -> Void = { _, _ in }
        var onQuit: () -> Void = {}
    }
}
