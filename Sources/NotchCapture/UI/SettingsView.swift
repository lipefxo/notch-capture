import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ownershipSection
                    shortcutsSection
                    listsSection
                    permissionSection
                    behaviorSection
                    dataSection
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)
            .background(NotchTheme.graphite)
        }
        .frame(width: NotchTheme.width, height: NotchTheme.maxHeight)
        .background(NotchSurfaceBackground())
        .clipShape(NotchHugShape(bottomRadius: 24))
        .onExitCommand { viewModel.openExpanded() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch Capture settings")
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.openExpanded()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(PressableIconButtonStyle())
            .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Back to inbox")

            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("LOCAL · PRIVATE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(NotchTheme.mint.opacity(0.72))
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(NotchTheme.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private var ownershipSection: some View {
        SettingsSection(title: "Notch ownership", caption: viewModel.ownership.explanation) {
            Picker("Notch ownership", selection: $viewModel.ownership) {
                ForEach(AppViewModel.NotchOwnership.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Notch ownership")

            if viewModel.ownership == .primary {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Primary mode can overlap NotchFlow. Use Automatic for seamless coexistence.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityElement(children: .combine)
            }

            if viewModel.isNotchFlowRunning {
                Label("NotchFlow detected — idle surface is being shared", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.mint)
            }
        }
    }

    private var shortcutsSection: some View {
        SettingsSection(title: "Shortcuts", caption: "Available from every app.") {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    Button {
                        viewModel.hooks.onOpenShortcutRecorder(shortcut.action)
                    } label: {
                        HStack {
                            Text(shortcut.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                            Spacer()
                            ShortcutKeycap(value: shortcut.displayValue)
                        }
                        .padding(.vertical, 8)
                        .notchHitTarget(Rectangle())
                    }
                    .buttonStyle(NotchPressButtonStyle(pressedScale: 0.995, pressedOpacity: 0.82))
                    .notchHitTarget(Rectangle())
                    .accessibilityLabel("\(shortcut.title), \(shortcut.displayValue)")
                    .accessibilityHint("Change this shortcut")

                    if index < viewModel.shortcuts.count - 1 {
                        Rectangle().fill(NotchTheme.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    private var permissionSection: some View {
        SettingsSection(title: "Permissions", caption: "Requested only when a feature needs them.") {
            PermissionRow(
                title: "Accessibility",
                detail: "Read the current text selection",
                systemImage: "cursorarrow.rays",
                isGranted: viewModel.accessibilityGranted,
                request: viewModel.hooks.onRequestAccessibility
            )
            PermissionRow(
                title: "Screen Recording",
                detail: "Capture a selected screen region",
                systemImage: "rectangle.dashed.badge.record",
                isGranted: viewModel.screenRecordingGranted,
                request: viewModel.hooks.onRequestScreenRecording
            )
        }
    }

    private var listsSection: some View {
        SettingsSection(title: "Lists", caption: "Each item can belong to one list.") {
            if !viewModel.lists.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.lists, id: \.self) { list in
                        Label(list, systemImage: "folder")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .frame(height: 25)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("New list", text: $viewModel.newListName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit { viewModel.createList() }
                Button("Add") { viewModel.createList() }
                    .buttonStyle(MintButtonStyle())
                    .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .padding(.leading, 9)
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var behaviorSection: some View {
        SettingsSection(title: "Behavior", caption: nil) {
            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
            Toggle("Auto-hide pill on external displays", isOn: $viewModel.autoHideExternalPill)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
        }
    }

    private var dataSection: some View {
        SettingsSection(title: "Your data", caption: "Stored only on this Mac.") {
            HStack(spacing: 8) {
                Button("Import…", action: viewModel.hooks.onImport)
                    .buttonStyle(SettingsButtonStyle())
                    .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Button("Export…", action: viewModel.hooks.onExport)
                    .buttonStyle(SettingsButtonStyle())
                    .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Spacer()
                Button("Quit", action: viewModel.hooks.onQuit)
                    .buttonStyle(CompactTextButtonStyle())
                    .notchHitTarget(Rectangle())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.78))
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder let content: Content

    init(title: String, caption: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(NotchTheme.tertiaryText)

            VStack(alignment: .leading, spacing: 9) {
                content
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.035))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(NotchTheme.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let caption {
                Text(caption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .padding(.horizontal, 2)
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let isGranted: Bool
    let request: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isGranted ? NotchTheme.mint : NotchTheme.secondaryText)
                .frame(width: 25, height: 25)
                .background(Color.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            Spacer()
            if isGranted {
                Label("Allowed", systemImage: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NotchTheme.mint)
            } else {
                Button("Allow", action: request)
                    .buttonStyle(MintButtonStyle())
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(isGranted ? "allowed" : "not allowed")")
    }
}

private struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? NotchTheme.mint : Color.white.opacity(0.7))
            .padding(.horizontal, 10)
            .frame(height: 27)
            .background(Color.white.opacity(configuration.isPressed ? 0.09 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: configuration.isPressed)
    }
}
