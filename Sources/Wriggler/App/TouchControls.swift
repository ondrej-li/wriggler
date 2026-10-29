import SwiftUI

/// On-screen controls: an eight-way pad on the left, the action button on the right.
///
/// Diagonals come from pressing two directions at once, which is why the pad is a
/// cross rather than a joystick: it matches how the original plays.
struct TouchControls: View {
    let input: InputController

    private let pad: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                directionPad
                Spacer(minLength: 20)
                HoldButton(label: "USE", tint: .zxGreen, width: 80, height: 58, font: .zx(14, weight: .heavy)) {
                    pressed in
                    input.set(.action, pressed: pressed)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .allowsHitTesting(true)
    }

    private var directionPad: some View {
        VStack(spacing: 3) {
            HoldButton(label: "▲", tint: .zxYellow, width: pad, height: pad, font: .zx(13, weight: .bold)) { pressed in
                input.set(.up, pressed: pressed)
            }
            HStack(spacing: 3) {
                HoldButton(label: "◀", tint: .zxYellow, width: pad, height: pad, font: .zx(13, weight: .bold)) {
                    pressed in
                    input.set(.left, pressed: pressed)
                }
                HoldButton(label: "▼", tint: .zxYellow, width: pad, height: pad, font: .zx(13, weight: .bold)) {
                    pressed in
                    input.set(.down, pressed: pressed)
                }
                HoldButton(label: "▶", tint: .zxYellow, width: pad, height: pad, font: .zx(13, weight: .bold)) {
                    pressed in
                    input.set(.right, pressed: pressed)
                }
            }
        }
    }
}

private struct HoldButton: View {
    let label: String
    let tint: Color
    let width: CGFloat
    let height: CGFloat
    let font: Font
    let onPress: (Bool) -> Void

    @State private var isPressed = false

    var body: some View {
        Text(label)
            .font(font)
            .foregroundStyle(tint.opacity(isPressed ? 1 : 0.85))
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.black.opacity(isPressed ? 0.6 : 0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(tint.opacity(isPressed ? 0.95 : 0.4), lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .scaleEffect(isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onPress(true)
                    }
                    .onEnded { _ in
                        isPressed = false
                        onPress(false)
                    }
            )
    }
}
