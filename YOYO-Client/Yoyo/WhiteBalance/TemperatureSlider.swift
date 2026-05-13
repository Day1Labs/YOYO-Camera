import SwiftUI

// MARK: - temperature slider view(horizontal)

struct TemperatureSlider: View {
    @ObservedObject var whiteBalanceManager: WhiteBalanceManager
    @Binding var temperature: Float
    let range: (min: Float, max: Float)

    @State private var localValue: Int = 5500
    @State private var isUserDragging: Bool = false

    private var stops: [Int] {
        Array(stride(from: Int(range.min), through: Int(range.max), by: 50))
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                whiteBalanceManager.enableAutoMode()
            }) {
                Text("A")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(whiteBalanceManager.isManualMode ? Color.white : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(whiteBalanceManager.isManualMode ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.3))
                    )
            }
            .padding(.trailing, 6)

            TickRuler(
                value: $localValue,
                stops: stops,
                isMajor: { $0 % 1000 == 0 },
                formatValue: { "\($0)K" },
                onSelectionChange: { newValue in
                    temperature = Float(newValue)
                    whiteBalanceManager.setWhiteBalance(temperature: Float(newValue))
                },
                onInteractionStart: {
                    isUserDragging = true
                    whiteBalanceManager.enableManualMode()
                },
                onInteractionEnd: {
                    isUserDragging = false
                    temperature = Float(localValue)
                    whiteBalanceManager.setWhiteBalance(temperature: Float(localValue))
                }
            )
        }
        .padding(.horizontal, 6)
        .onAppear {
            localValue = closestStop(for: Int(temperature))
        }
        .onChange(of: temperature) { _, newValue in
            if !isUserDragging {
                localValue = closestStop(for: Int(newValue))
            }
        }
        .onChange(of: whiteBalanceManager.currentTemperature) { _, newValue in
            if !whiteBalanceManager.isManualMode, !isUserDragging {
                localValue = closestStop(for: Int(newValue))
            }
        }
    }

    private func closestStop(for target: Int) -> Int {
        stops.min(by: { abs($0 - target) < abs($1 - target) }) ?? target
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack {
            TemperatureSlider(
                whiteBalanceManager: {
                    let manager = WhiteBalanceManager()
                    manager.setPreviewWhiteBalance(temperature: 5500)
                    return manager
                }(),
                temperature: .constant(5500.0),
                range: (min: 2000.0, max: 8000.0)
            )
            Image(systemName: "xmark")
                .font(.system(size: 12))
                .foregroundColor(Color.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
    }
}
