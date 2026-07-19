import SwiftUI

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

struct FolderReorderSession: Equatable {
    let draggedFolderID: UUID
    var targetID: UUID?
    var placement: AppViewModel.ReorderPlacement = .before

    func previewing(_ folders: [AppViewModel.FolderSummary]) -> [AppViewModel.FolderSummary] {
        guard let targetID,
              targetID != draggedFolderID,
              let sourceIndex = folders.firstIndex(where: { $0.id == draggedFolderID }),
              let originalTargetIndex = folders.firstIndex(where: { $0.id == targetID }) else { return folders }
        var preview = folders
        let dragged = preview.remove(at: sourceIndex)
        let targetIndex = originalTargetIndex > sourceIndex ? originalTargetIndex - 1 : originalTargetIndex
        preview.insert(dragged, at: targetIndex + (placement == .after ? 1 : 0))
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

struct LedgerInsertionIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let placement: AppViewModel.ReorderPlacement?

    var body: some View {
        GeometryReader { proxy in
            if let placement {
                Rectangle()
                    .fill(NotchTheme.primaryAccent)
                    .frame(height: 2)
                    .shadow(color: NotchTheme.primaryAccent.opacity(0.45), radius: 3)
                    .offset(y: placement == .after ? max(0, proxy.size.height - 2) : 0)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : NotchMotion.insertion, value: placement)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LedgerDragPreview: View {
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

struct LedgerDragRegionPreferenceKey: PreferenceKey {
    static let defaultValue: [LedgerDragRegion: CGRect] = [:]

    static func reduce(
        value: inout [LedgerDragRegion: CGRect],
        nextValue: () -> [LedgerDragRegion: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
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
