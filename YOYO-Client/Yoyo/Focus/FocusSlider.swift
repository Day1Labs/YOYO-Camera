import SwiftUI

// MARK: - focus slider view (horizontal)

struct FocusSlider: View {
    @ObservedObject var focusManager: FocusManager
    @Binding var position: Float
    let range: (min: Float, max: Float)

    @State private var localValue: Double = 0.0
    @State private var isUserDragging: Bool = false

    private var stops: [Double] {
        Array(stride(from: Double(range.min), through: Double(range.max), by: 0.01))
            .map { ($0 * 100).rounded() / 100 } // Corrected floating point precision
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                if focusManager.isManualFocusMode {
                    focusManager.enableAutoFocusMode()
                }
            }) {
                Text("A")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(focusManager.isManualFocusMode ? Color.white : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(focusManager.isManualFocusMode ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.3))
                    )
            }
            .padding(.trailing, 6)

            TickRuler(
                value: $localValue,
                stops: stops,
                isMajor: { abs($0.truncatingRemainder(dividingBy: 0.1)) < 0.001 },
                formatValue: { String(format: "%.2f", $0) },
                onSelectionChange: { newValue in
                    position = Float(newValue)
                },
                onInteractionStart: {
                    isUserDragging = true
                    if !focusManager.isManualFocusMode {
                        focusManager.enableManualFocus()
                    }
                },
                onInteractionEnd: {
                    isUserDragging = false
                    position = Float(localValue)
                }
            )
        }
        .padding(.horizontal, 6)
        .onAppear {
            localValue = closestStop(for: Double(position))
        }
        .onChange(of: position) { _, newValue in
            if !isUserDragging {
                localValue = closestStop(for: Double(newValue))
            }
        }
        .onChange(of: focusManager.currentLensPosition) { _, newValue in
            if !focusManager.isManualFocusMode, !isUserDragging {
                localValue = closestStop(for: Double(newValue))
            }
        }
    }

    private func closestStop(for target: Double) -> Double {
        stops.min(by: { abs($0 - target) < abs($1 - target) }) ?? target
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack {
            FocusSlider(
                focusManager: FocusManager.shared,
                position: .constant(0.5),
                range: (min: 0.0, max: 1.0)
            )
            Image(systemName: "xmark")
                .font(.system(size: 12))
                .foregroundColor(Color.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
    }
}
