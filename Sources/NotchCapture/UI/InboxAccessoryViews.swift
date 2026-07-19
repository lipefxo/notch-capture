import AppKit
import SwiftUI

struct TonalTagLabel: View {
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

struct HiddenScrollIndicatorConfigurator: NSViewRepresentable {
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

struct FolderLedgerRow: View {
    let folder: AppViewModel.FolderSummary
    let itemCount: Int
    let isSelected: Bool
    let isDropTarget: Bool
    let reduceMotion: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var presentation: NotchPresentationCoordinator
    @State private var isHovered = false
    @State private var isMoreActionsHovered = false
    @State private var actionsAnchor: CGRect = .zero

    private var showsActions: Bool { isHovered || isSelected }

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

                Color.clear
                    .frame(width: 36, height: 38)
            }
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .frame(minHeight: 50)
            .background(
                isDropTarget
                    ? NotchTheme.mint.opacity(0.08)
                    : (isSelected
                        ? NotchTheme.selectedLedger
                        : (isHovered ? NotchTheme.hoveredLedger : Color.clear))
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
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchPressButtonStyle(pressedScale: 0.995, pressedOpacity: 0.86))
        .scaleEffect(isDropTarget && !reduceMotion ? 1.01 : 1)
        .overlay(alignment: .trailing) {
            Button {
                presentation.present(NotchMenu(title: folder.name, anchor: actionsAnchor, items: [
                    NotchMenuItem(title: "Open Folder", icon: "folder") { onOpen() },
                    NotchMenuItem(title: "Rename Folder", icon: "pencil") { onRename() },
                    NotchMenuItem(title: "Delete", icon: "xmark", role: .destructive) { onDelete() },
                ]))
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
            .padding(.trailing, 8)
            .help("More actions")
            .accessibilityLabel("More actions for \(folder.name)")
            .opacity(showsActions ? 1 : 0)
            // An opacity-0 view still hit-tests; don't let an invisible button
            // swallow clicks meant for the row.
            .allowsHitTesting(showsActions)
            .animation(reduceMotion ? nil : NotchMotion.hover, value: showsActions)
        }
        // Hover is tracked outside the actions overlay so the ellipsis sits
        // inside the tracked region — tracking it before the overlay lets the
        // button occlude the row's hover, which flips showsActions off, which
        // re-exposes the row to hover, which flips it back on: a flicker loop.
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : NotchMotion.hover, value: isHovered)
        .animation(reduceMotion ? nil : NotchMotion.filter, value: isDropTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Folder \(folder.name), \(itemCount) \(itemCount == 1 ? "item" : "items")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Opens this folder")
        .accessibilityAction(named: "Rename Folder", onRename)
        .accessibilityAction(named: "Delete Folder", onDelete)
    }
}

struct EmptyInboxView: View {
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
            ? "Write a thought or attach a file to start your inbox."
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

struct InlineErrorView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(NotchTheme.warning)
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
        .background(NotchTheme.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error: \(message)")
    }
}

struct DropTargetOverlay: View {
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
