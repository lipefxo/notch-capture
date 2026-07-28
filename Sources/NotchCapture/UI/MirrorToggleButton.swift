import SwiftUI

/// The single mirror affordance, shared by the expanded header and both
/// compact pills so the glyph, hit target and press feel are identical
/// wherever the toggle appears.
struct MirrorToggleButton: View {
    @ObservedObject var viewModel: AppViewModel
    var glyphSize: CGFloat = 13
    var width: CGFloat = 28

    private var isOpen: Bool { viewModel.surfaceState == .mirror }

    private var label: String { isOpen ? "Close mirror" : "Open mirror" }

    var body: some View {
        Button(action: viewModel.toggleMirror) {
            // No `.fill` variant exists for this symbol, so the open state is
            // carried by colour and the selected trait rather than by weight.
            Image(systemName: "camera.aperture")
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
