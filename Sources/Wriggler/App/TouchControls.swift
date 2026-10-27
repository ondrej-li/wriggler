import SwiftUI

/// On-screen controls: a direction pad on the left, jump on the right.
///
/// Every control reports press/release so held directions keep running and the jump
/// edge can drive coyote-time logic inside the simulation.
struct TouchControls: View {
    let input: InputController

    private let padSize: CGFloat = 58

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                directionPad

                Spacer(minLength: 24)

                HoldButton(label: "JUMP", tint: .zxGreen, width: 92, height: 66, font: .zx(16, weight: .heavy)) {
                    pressed in
                    input.set(.jump, pressed: pressed)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 14)
        }
        .allowsHitTesting(true)
    }

    private var directionPad: some View {
        VStack(spacing: 8) {
            HoldButton(label: "▲", tint: .zxYellow, width: padSize, height: padSize, font: .zx(18, weight: .bold)) {
                pressed in
                input.set(.up, pressed: pressed)
            }

            HStack(spacing: 8) {
                HoldButton(label: "◀", tint: .zxYellow, width: padSize, height: padSize, font: .zx(18, weight: .bold)) {
                    pressed in
                    input.set(.left, pressed: pressed)
                }
                HoldButton(label: "▼", tint: .zxYellow, width: padSize, height: padSize, font: .zx(18, weight: .bold)) {
                    pressed in
                    input.set(.down, pressed: pressed)
                }
                HoldButton(label: "▶", tint: .zxYellow, width: padSize, height: padSize, font: .zx(18, weight: .bold)) {
                    pressed in
                    input.set(.right, pressed: pressed)
                }
            }
        }
    }
}

/// A button that reports press and release, including drags that leave its bounds.
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
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(isPressed ? 0.55 : 0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(tint.opacity(isPressed ? 0.95 : 0.4), lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
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
