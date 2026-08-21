import SwiftUI

/// The mirror affordance in the expanded header. Compact pills keep capture
/// and now-playing chrome only; opening the camera is an expanded-session act.
struct MirrorToggleButton: View {
    @ObservedObject var viewModel: AppViewModel
    var glyphSize: CGFloat = 13
    var width: CGFloat = 28

    private var isOpen: Bool { viewModel.surfaceState == .mirror }

    private var label: String { isOpen ? "Close mirror" : "Open mirror" }

    var body: some View {
        Button(action: viewModel.toggleMirror) {
            // Open state is carried by colour and the selected trait rather
            // than by switching to a `.fill` weight.
            Image(systemName: "record.circle")
                .font(.system(size: glyphSize, weight: .regular))
        }
        .buttonStyle(PressableIconButtonStyle(
            idleForeground: isOpen ? NotchTheme.primaryText : NotchTheme.secondaryText,
            width: width
        ))
        .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint("Shows a live camera preview in the notch")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}
