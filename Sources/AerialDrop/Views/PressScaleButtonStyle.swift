import SwiftUI

/// Scales a button down while pressed for tactile feedback. Hover and
/// outer-card scaling stay on the caller so both can compose.
struct PressScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.985

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(duration: 0.25, bounce: 0.2), value: configuration.isPressed)
    }
}
