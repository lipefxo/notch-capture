import AppKit
import SwiftUI

struct LedgerCompletionLayerLifecycle: Equatable, Sendable {
    var progress: CGFloat
    var showsLayers: Bool

    init(isCompleted: Bool) {
        progress = isCompleted ? 1 : 0
        showsLayers = isCompleted
    }

    @discardableResult
    mutating func beginTransition(to isCompleted: Bool) -> Bool {
        if isCompleted {
            showsLayers = true
        }
        progress = isCompleted ? 1 : 0
        return !isCompleted && showsLayers
    }

    mutating func finishRetraction(ifItemIsCompleted isCompleted: Bool) {
        guard !isCompleted, progress == 0 else { return }
        showsLayers = false
    }

    static func cleanupDelay(reduceMotion: Bool) -> TimeInterval {
        reduceMotion
            ? NotchMotion.reducedMotionDuration
            : NotchMotion.completionRetractDuration
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

    /// How far the liquid front bulges beyond the reveal frame, as a fraction
    /// of row height.
    static let bulgeFactor: CGFloat = 0.35
    /// Length of the bright trail decaying behind the crest.
    static let trailLength: CGFloat = 96

    /// Zero during the circle phase and at rest; between, a parabola envelope
    /// blends the bulge in after the circle handoff, peaks it mid-sweep, and
    /// returns it to zero so the settled mask is exactly the full row.
    static func bulge(in rect: CGRect, progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        let extent = rect.width * clamped
        guard rect.width > rect.height, extent > rect.height else { return 0 }
        let stretch = (extent - rect.height) / (rect.width - rect.height)
        let envelope = 4 * stretch * (1 - stretch)
        let raw = bulgeFactor * rect.height * envelope
        let frame = revealFrame(in: rect, progress: clamped)
        return max(0, min(raw, rect.maxX - frame.maxX))
    }

    /// X of the crest apex — the forwardmost point of the liquid.
    static func frontApexX(in rect: CGRect, progress: CGFloat) -> CGFloat {
        let frame = revealFrame(in: rect, progress: progress)
        return frame.maxX + bulge(in: rect, progress: progress)
    }

    /// The liquid mask: today's rounded frame on the left, a convex meniscus
    /// bulging past the frame on the right while the sweep is in flight.
    static func meniscusPath(in rect: CGRect, progress: CGFloat) -> Path {
        let frame = revealFrame(in: rect, progress: progress)
        guard frame.width > 0, frame.height > 0 else { return Path() }
        let radius = cornerRadius(for: frame, progress: progress)
        let bulge = bulge(in: rect, progress: progress)
        guard bulge > 0.5 else {
            return RoundedRectangle(cornerRadius: radius, style: .continuous)
                .path(in: frame)
        }

        let height = frame.height
        let apex = CGPoint(x: frame.maxX + bulge, y: frame.midY)
        let capStart = frame.maxX - max(radius, height * 0.28)
        let ease: CGFloat = 0.55

        var path = Path()
        path.move(to: CGPoint(x: frame.minX + radius, y: frame.minY))
        path.addLine(to: CGPoint(x: capStart, y: frame.minY))
        path.addCurve(
            to: apex,
            control1: CGPoint(x: capStart + ease * (apex.x - capStart), y: frame.minY),
            control2: CGPoint(x: apex.x, y: frame.midY - ease * (height / 2))
        )
        path.addCurve(
            to: CGPoint(x: capStart, y: frame.maxY),
            control1: CGPoint(x: apex.x, y: frame.midY + ease * (height / 2)),
            control2: CGPoint(x: capStart + ease * (apex.x - capStart), y: frame.maxY)
        )
        path.addLine(to: CGPoint(x: frame.minX + radius, y: frame.maxY))
        path.addQuadCurve(
            to: CGPoint(x: frame.minX, y: frame.maxY - radius),
            control: CGPoint(x: frame.minX, y: frame.maxY)
        )
        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: frame.minX + radius, y: frame.minY),
            control: CGPoint(x: frame.minX, y: frame.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct LedgerCompletionRevealMask: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        LedgerCompletionRevealGeometry.meniscusPath(in: rect, progress: progress)
    }
}

/// Renders the liquid completion wash: base tint, a warm trail decaying behind
/// the crest, and a specular highlight riding the meniscus front. Animatable so
/// the gradient stops track the interpolated front each frame — a plain view
/// would snap its gradients to the target value when the transaction begins.
private struct LedgerCompletionLiquidWashModifier: ViewModifier, @preconcurrency Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let crestTrailingReach: CGFloat = 18
    private static let crestLeadingReach: CGFloat = 10
    private static let crestPeakInset: CGFloat = 6
    private static let crestBlur: CGFloat = 3

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                let rect = CGRect(origin: .zero, size: proxy.size)
                let apexX = LedgerCompletionRevealGeometry.frontApexX(
                    in: rect,
                    progress: progress
                )

                ZStack {
                    NotchTheme.completedLedger

                    LinearGradient(
                        stops: trailStops(apexX: apexX, width: rect.width),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .opacity(Double(1 - progress))

                    LinearGradient(
                        stops: crestStops(apexX: apexX, width: rect.width),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .blur(radius: Self.crestBlur)
                    .opacity(crestVisibility)
                }
                .mask {
                    LedgerCompletionRevealGeometry.meniscusPath(
                        in: rect,
                        progress: progress
                    )
                    .fill(.white)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Ramps in as the sweep leaves the checkbox, dissolves as the liquid
    /// settles — the crest exists only while the wave is in flight.
    private var crestVisibility: Double {
        Double(min(1, 6 * progress) * min(1, 4 * (1 - progress)))
    }

    private func trailStops(apexX: CGFloat, width: CGFloat) -> [Gradient.Stop] {
        let clear = NotchTheme.completionTrail.opacity(0)
        let tail = unitX(apexX - LedgerCompletionRevealGeometry.trailLength, width)
        let head = unitX(apexX, width)
        return [
            .init(color: clear, location: 0),
            .init(color: clear, location: tail),
            .init(color: NotchTheme.completionTrail, location: head),
            .init(color: NotchTheme.completionTrail, location: 1)
        ]
    }

    private func crestStops(apexX: CGFloat, width: CGFloat) -> [Gradient.Stop] {
        let clear = NotchTheme.completionCrest.opacity(0)
        let peak = apexX - Self.crestPeakInset
        return [
            .init(color: clear, location: 0),
            .init(color: clear, location: unitX(peak - Self.crestTrailingReach, width)),
            .init(color: NotchTheme.completionCrest, location: unitX(peak, width)),
            .init(color: clear, location: unitX(peak + Self.crestLeadingReach, width)),
            .init(color: clear, location: 1)
        ]
    }

    private func unitX(_ x: CGFloat, _ width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(max(x / width, 0), 1)
    }
}

/// Exit visual for rows leaving the ledger. Completed rows retract their mint
/// wash back toward the checkbox as a bookend to the completion sweep; every
/// other removal (trash, archive, move, restore) dissolves in place — a slight
/// sink, shrink, and blur while the list closes the gap underneath.
struct LedgerRowExitModifier: ViewModifier {
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
                .scaleEffect(1 - (0.03 * progress))
                .offset(y: 3 * progress)
                .blur(radius: 2 * progress)
                .opacity(1 - pow(progress, 2))
        }
    }
}

struct LedgerRowView: View, Equatable {
    let item: AppViewModel.LedgerItem
    let isSelected: Bool
    let isEditing: Bool
    let timeFormat: AppViewModel.TimeFormat
    let showsSearchLocation: Bool
    /// Event-time access only (actions, menus, the editing session). This is
    /// deliberately NOT @ObservedObject: every visible row re-rendering on
    /// every published change (each composer keystroke) is the app's hottest
    /// render path. Anything the row must re-render for is a stored input
    /// above and part of ==.
    let viewModel: AppViewModel

    @EnvironmentObject private var presentation: NotchPresentationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isEditorFocused: Bool
    @State private var isHovered = false
    @State private var isMoreActionsHovered = false
    @State private var actionsAnchor: CGRect = .zero
    @State private var completionLayerLifecycle: LedgerCompletionLayerLifecycle
    @State private var completionLayerCleanupTask: Task<Void, Never>?

    private var showsActions: Bool { isHovered || isSelected }

    nonisolated static func == (lhs: LedgerRowView, rhs: LedgerRowView) -> Bool {
        lhs.item == rhs.item
            && lhs.isSelected == rhs.isSelected
            && lhs.isEditing == rhs.isEditing
            && lhs.timeFormat == rhs.timeFormat
            && lhs.showsSearchLocation == rhs.showsSearchLocation
    }
    private var isSingleAttachmentOnly: Bool {
        item.text.isEmpty && item.attachments.count == 1 && item.tags.isEmpty
    }

    private var isLinkOnlyItem: Bool {
        isSingleAttachmentOnly && item.attachments.first?.kind == .link
    }

    init(
        item: AppViewModel.LedgerItem,
        isSelected: Bool,
        isEditing: Bool,
        timeFormat: AppViewModel.TimeFormat,
        showsSearchLocation: Bool,
        viewModel: AppViewModel
    ) {
        self.item = item
        self.isSelected = isSelected
        self.isEditing = isEditing
        self.timeFormat = timeFormat
        self.showsSearchLocation = showsSearchLocation
        self.viewModel = viewModel
        _completionLayerLifecycle = State(
            initialValue: LedgerCompletionLayerLifecycle(isCompleted: item.isCompleted)
        )
        _completionLayerCleanupTask = State(initialValue: nil)
    }

    var body: some View {
        ZStack {
            if completionLayerLifecycle.showsLayers {
                completionBackgroundLayer
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            interactionBackgroundLayer

            rowContent(
                completedPresentation: isEditing && item.isCompleted,
                isInteractive: true
            )

            if !isEditing, completionLayerLifecycle.showsLayers {
                completedContentLayer
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onChange(of: item.isCompleted) { _, isCompleted in
            completionLayerCleanupTask?.cancel()
            completionLayerCleanupTask = nil
            if isCompleted {
                completionLayerLifecycle.showsLayers = true
            }
            // The wash launches a beat after the check pops; retracting is
            // immediate so undo feels instant.
            let animation = reduceMotion
                ? NotchMotion.reducedMotion
                : (isCompleted
                    ? NotchMotion.completionReveal.delay(NotchMotion.completionWashDelay)
                    : NotchMotion.completionRetract)
            _ = withAnimation(animation) {
                completionLayerLifecycle.beginTransition(to: isCompleted)
            }
            guard !isCompleted else { return }
            let cleanupDelay = LedgerCompletionLayerLifecycle.cleanupDelay(
                reduceMotion: reduceMotion
            )
            completionLayerCleanupTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(cleanupDelay))
                guard !Task.isCancelled else { return }
                completionLayerLifecycle.finishRetraction(
                    ifItemIsCompleted: item.isCompleted
                )
                completionLayerCleanupTask = nil
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
        .onDisappear {
            completionLayerCleanupTask?.cancel()
            completionLayerCleanupTask = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kind == .task ? "Task" : "Note"): \(item.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            if !item.text.isEmpty || !item.attachments.isEmpty {
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
        } else if isSingleAttachmentOnly,
                  let attachment = item.attachments.first,
                  attachment.kind != .link {
            // Link-only captures share the default text-row layout (title +
            // trailing timestamp). File/screenshot singles keep the richer
            // attachment chrome below.
            AttachmentLedgerRow(
                item: item,
                attachment: attachment,
                timeFormat: timeFormat,
                searchLocation: showsSearchLocation
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
                    timeFormat: timeFormat,
                    searchLocation: showsSearchLocation
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
                .opacity(Double(completionLayerLifecycle.progress))
        } else {
            Color.clear
                .modifier(
                    LedgerCompletionLiquidWashModifier(progress: completionLayerLifecycle.progress)
                )
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
                .opacity(Double(completionLayerLifecycle.progress))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            rowContent(completedPresentation: true, isInteractive: false)
                .mask {
                    LedgerCompletionRevealMask(progress: completionLayerLifecycle.progress)
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
            } else if isLinkOnlyItem, let url = item.attachments.first?.previewURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    selectionContentLayout(
                        completedPresentation: completedPresentation,
                        isInteractive: true
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .notchHitTarget(Rectangle())
                .help("Open link")
                .accessibilityLabel("Open link: \(item.title)")
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
            .foregroundStyle(completedPresentation ? NotchTheme.completedPrimaryText : NotchTheme.primaryText)
            .underline(isLinkOnlyItem, color: completedPresentation ? NotchTheme.completedPrimaryText : NotchTheme.primaryText)
            .strikethrough(completedPresentation, color: NotchTheme.completedPrimaryText)
            .lineLimit(2)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(
                        completedPresentation
                            ? NotchTheme.completedSecondaryText
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
        return item.isCompleted ? NotchMotion.completionCheck : NotchMotion.completionReopen
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
            Text(CaptureTimestampFormatter.string(from: item.createdAt, timeFormat: timeFormat))
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
        } else if isLinkOnlyItem {
            linkLeadingControl(
                completedPresentation: completedPresentation,
                isInteractive: isInteractive
            )
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

    @ViewBuilder
    private func linkLeadingControl(completedPresentation: Bool, isInteractive: Bool) -> some View {
        if isInteractive, let url = item.attachments.first?.previewURL {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                linkLeadingIcon(completedPresentation: completedPresentation)
            }
            .buttonStyle(NotchPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.82))
            .notchHitTarget(Rectangle())
            .help("Open link")
            .accessibilityLabel("Open link")
        } else {
            linkLeadingIcon(completedPresentation: completedPresentation)
                .accessibilityHidden(true)
        }
    }

    private func linkLeadingIcon(completedPresentation: Bool) -> some View {
        Group {
            if let faviconURL = item.attachments.first?.faviconURL,
               let favicon = NSImage(contentsOf: faviconURL) {
                Image(nsImage: favicon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(
                        completedPresentation ? NotchTheme.tertiaryText : NotchTheme.secondaryText
                    )
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 20, height: 28)
    }

    private func completionControlVisual(completedPresentation: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(NotchTheme.secondaryText, lineWidth: 1.25)
                .frame(width: 13, height: 13)
                .opacity(completedPresentation ? 0 : 1)
                .scaleEffect(symbolScale(isVisible: !item.isCompleted))

            ZStack {
                Circle()
                    .fill(NotchTheme.completionAccent)

                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(NotchTheme.ink)
            }
            .frame(width: 14, height: 14)
            .opacity(completedPresentation ? 1 : 0)
            .scaleEffect(symbolScale(isVisible: item.isCompleted))
        }
        .frame(width: 20, height: 28)
        .notchHitTarget(Rectangle())
        .animation(completionStateAnimation, value: item.isCompleted)
    }

    private func symbolScale(isVisible: Bool) -> CGFloat {
        guard !reduceMotion else { return 1 }
        return isVisible ? 1 : 0.78
    }

    private var subtitle: String? {
        if showsSearchLocation {
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
            presentation.present(NotchMenu(title: item.title, anchor: actionsAnchor, items: appMenuItems))
        } label: {
            // "ellipsis.vertical" is not a real SF Symbol; rotate the real one.
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(90))
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
        .menuAnchor($actionsAnchor)
        .help("More actions")
        .accessibilityLabel("More actions for \(item.title)")
    }

    private var appMenuItems: [NotchMenuItem] {
        var items: [NotchMenuItem] = [
            NotchMenuItem(title: "Edit", icon: "pencil", isEnabled: !item.text.isEmpty || !item.attachments.isEmpty) { viewModel.beginEditing(item) },
            NotchMenuItem(title: item.isCompleted ? "Mark incomplete" : "Complete", icon: item.isCompleted ? "arrow.uturn.backward" : "checkmark") { viewModel.toggleComplete(item) },
            NotchMenuItem(title: item.isPinned ? "Unpin" : "Pin", icon: item.isPinned ? "pin.slash" : "pin") { viewModel.togglePin(item) },
        ]
        if !viewModel.folders.isEmpty || item.folderID != nil {
            let moveItems = moveMenuItems
            items.append(NotchMenuItem(title: "Move to…", icon: "folder") { [presentation, actionsAnchor] in
                presentation.present(NotchMenu(title: "Move to", anchor: actionsAnchor, items: moveItems))
            })
        }
        if item.isTrashed {
            items.append(NotchMenuItem(title: "Restore", icon: "arrow.uturn.backward") { viewModel.restore(item) })
            items.append(NotchMenuItem(title: "Delete permanently", icon: "trash.slash", role: .destructive) { viewModel.deletePermanently(item) })
        } else {
            items.append(NotchMenuItem(title: item.isArchived ? "Restore to Inbox" : "Archive", icon: item.isArchived ? "arrow.uturn.backward" : "archivebox") {
                item.isArchived ? viewModel.restore(item) : viewModel.archive(item)
            })
            items.append(NotchMenuItem(title: "Delete", icon: "xmark", role: .destructive) { viewModel.trash(item) })
        }
        return items
    }

    private var moveMenuItems: [NotchMenuItem] {
        var items: [NotchMenuItem] = [
            NotchMenuItem(title: "Inbox", icon: "tray", isEnabled: item.folderID != nil, isChecked: item.folderID == nil) { viewModel.move(item, to: nil) }
        ]
        for folder in viewModel.folders.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            items.append(NotchMenuItem(title: folder.name, icon: "folder", isEnabled: item.folderID != folder.id, isChecked: item.folderID == folder.id) { viewModel.move(item, to: folder.id) })
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
                        completedPresentation ? NotchTheme.completedPrimaryText : NotchTheme.primaryText
                    )
                    .strikethrough(completedPresentation, color: NotchTheme.completedPrimaryText)
                    .lineLimit(1)
                if let detail = attachment.subtitle {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(
                            completedPresentation
                                ? NotchTheme.completedSecondaryText
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
            let request = ThumbnailRequest(
                fileURL: url,
                size: CGSize(width: size.width * 2, height: size.height * 2),
                scale: NSScreen.main?.backingScaleFactor ?? 2
            )
            if let generated = await ThumbnailLoader.shared.thumbnail(for: request),
               !Task.isCancelled {
                thumbnail = generated
            }
        }
    }
}
