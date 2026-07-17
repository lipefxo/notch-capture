import SwiftUI

/// A single owner for app-owned transient presentation. Keeping this above the
/// individual screens prevents a menu and a modal from competing for focus.
@MainActor
final class NotchPresentationCoordinator: ObservableObject {
    @Published private(set) var modal: NotchModal?
    @Published private(set) var menu: NotchMenu?

    var hasActivePresentation: Bool { modal != nil || menu != nil }
    var hasModal: Bool { modal != nil }

    func present(_ modal: NotchModal) {
        menu = nil
        self.modal = modal
    }

    func present(_ menu: NotchMenu) {
        guard modal == nil else { return }
        self.menu = menu
    }

    func dismissMenu() { menu = nil }
    func dismissModal() { modal = nil }
    func updateModalValidation(_ message: String?) { modal?.validationMessage = message }
    func dismissAll() { menu = nil; modal = nil }
}

struct NotchMenuItem: Identifiable {
    enum Role { case normal, destructive }

    let id = UUID()
    let title: String
    let icon: String?
    var role: Role = .normal
    var isEnabled = true
    var isChecked = false
    var action: () -> Void
}

struct NotchMenu {
    let title: String?
    let anchor: CGPoint
    let items: [NotchMenuItem]
}

struct NotchModal {
    enum Kind { case standard, destructive, shortcut }

    let kind: Kind
    let title: String
    let message: String?
    let textFieldLabel: String?
    var draft: String
    let primaryTitle: String
    let cancelTitle: String
    var validationMessage: String?
    let onSubmit: (String) -> String?
    let onCancel: () -> Void
    var onKeyRecording: ((Result<ShortcutRecording, ShortcutRecordingFailure>) -> String?)?
}

enum NotchPopoverPlacement {
    static func frame(
        anchor: CGRect,
        menuSize: CGSize,
        in bounds: CGRect,
        margin: CGFloat = 12
    ) -> CGRect {
        let horizontal = min(max(anchor.midX - menuSize.width / 2, bounds.minX + margin), bounds.maxX - margin - menuSize.width)
        let below = anchor.maxY + 6
        let above = anchor.minY - 6 - menuSize.height
        let vertical = below + menuSize.height <= bounds.maxY - margin ? below : max(bounds.minY + margin, above)
        return CGRect(origin: CGPoint(x: horizontal, y: vertical), size: menuSize)
    }
}

struct NotchPresentationLayer: View {
    @EnvironmentObject private var coordinator: NotchPresentationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedModal: Bool

    var body: some View {
        ZStack {
            if coordinator.hasModal {
                Color.black.opacity(0.50)
                    .accessibilityHidden(true)
            }
            if let menu = coordinator.menu {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.dismissMenu() }
                NotchPopoverMenu(menu: menu)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
            if let modal = coordinator.modal {
                NotchModalCard(modal: modal)
                    .focused($focusedModal)
                    .onAppear { focusedModal = true }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.content, value: coordinator.hasActivePresentation)
        .clipped()
        .onExitCommand {
            if let modal = coordinator.modal {
                modal.onCancel()
                coordinator.dismissModal()
            } else {
                coordinator.dismissMenu()
            }
        }
    }
}

private struct NotchPopoverMenu: View {
    @EnvironmentObject private var coordinator: NotchPresentationCoordinator
    let menu: NotchMenu

    var body: some View {
        GeometryReader { proxy in
            let height = min(CGFloat(menu.items.count * 31 + (menu.title == nil ? 8 : 34)), 278)
            let frame = NotchPopoverPlacement.frame(
                anchor: CGRect(origin: menu.anchor, size: .zero),
                menuSize: CGSize(width: 230, height: height),
                in: proxy.frame(in: .local)
            )
            VStack(alignment: .leading, spacing: 2) {
                if let title = menu.title {
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(menu.items) { item in
                            Button {
                                guard item.isEnabled else { return }
                                coordinator.dismissMenu()
                                item.action()
                            } label: {
                                HStack(spacing: 8) {
                                    if let icon = item.icon { Image(systemName: icon).frame(width: 14) }
                                    Text(item.title).lineLimit(1)
                                    Spacer()
                                    if item.isChecked { Image(systemName: "checkmark").foregroundStyle(NotchTheme.mint) }
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(item.role == .destructive ? Color.red.opacity(item.isEnabled ? 0.9 : 0.35) : (item.isEnabled ? NotchTheme.primaryText : NotchTheme.tertiaryText))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!item.isEnabled)
                            .accessibilityLabel(item.title)
                            .accessibilityAddTraits(item.isChecked ? .isSelected : [])
                        }
                    }
                }
                .frame(maxHeight: 270)
            }
            .frame(width: 230)
            .padding(4)
            .background(NotchTheme.raisedGraphite)
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NotchTheme.controlStroke) }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
            .position(x: frame.midX, y: frame.midY)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(menu.title ?? "Actions")
        }
    }
}

private struct NotchModalCard: View {
    @EnvironmentObject private var coordinator: NotchPresentationCoordinator
    @State private var draft: String
    @FocusState private var textFocused: Bool
    let modal: NotchModal

    init(modal: NotchModal) {
        self.modal = modal
        _draft = State(initialValue: modal.draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(modal.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(NotchTheme.primaryText)
            if let message = modal.message {
                Text(message).font(.system(size: 10.5)).foregroundStyle(NotchTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            if let textFieldLabel = modal.textFieldLabel {
                VStack(alignment: .leading, spacing: 5) {
                    Text(textFieldLabel.uppercased()).font(.system(size: 8.5, weight: .bold)).tracking(0.7).foregroundStyle(NotchTheme.tertiaryText)
                    TextField(textFieldLabel, text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(NotchTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(NotchTheme.controlStroke) }
                        .focused($textFocused)
                        .onSubmit { submit() }
                }
            }
            if let onKeyRecording = modal.onKeyRecording {
                ShortcutCaptureField(currentValue: draft) { result in
                    switch result {
                    case let .success(recording):
                        draft = recording.displayValue
                        if let error = onKeyRecording(.success(recording)) {
                            coordinator.updateModalValidation(error)
                        } else {
                            coordinator.dismissModal()
                        }
                    case let .failure(error):
                        coordinator.updateModalValidation(onKeyRecording(.failure(error)) ?? error.message)
                    }
                } onCancel: { cancel() }
                .frame(height: 38)
            }
            if let validation = modal.validationMessage {
                Text(validation).font(.system(size: 9.5)).foregroundStyle(.red.opacity(0.88))
            }
            HStack {
                Button(modal.cancelTitle) { cancel() }.buttonStyle(CompactTextButtonStyle())
                Spacer()
                if modal.kind == .destructive {
                    Button(modal.primaryTitle) { submit() }.buttonStyle(DestructiveButtonStyle())
                } else {
                    Button(modal.primaryTitle) { submit() }.buttonStyle(MintButtonStyle())
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(NotchTheme.graphite)
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NotchTheme.controlStroke) }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 24, y: 14)
        .onAppear { textFocused = modal.textFieldLabel != nil }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(modal.title)
        .accessibilityAddTraits(.isModal)
    }

    private func submit() {
        if let error = modal.onSubmit(draft) {
            coordinator.updateModalValidation(error)
            return
        }
        coordinator.dismissModal()
    }

    private func cancel() {
        modal.onCancel()
        coordinator.dismissModal()
    }
}

struct NotchSegmentedControl<Option: Hashable & Identifiable & RawRepresentable>: View where Option.RawValue == String {
    let options: [Option]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.id) { option in
                Button(option.rawValue) { selection = option }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selection == option ? Color.black.opacity(0.8) : NotchTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(selection == option ? NotchTheme.mint : NotchTheme.control)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(NotchTheme.field)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct NotchToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(NotchTheme.primaryText)
                Spacer()
                Capsule().fill(isOn ? NotchTheme.mint : NotchTheme.control).frame(width: 34, height: 20)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(Color.white.opacity(0.92)).frame(width: 16, height: 16).padding(2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.red.opacity(configuration.isPressed ? 0.65 : 0.82))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
