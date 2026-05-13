import SwiftUI

// MARK: - ISO view(horizontal)

struct ISOSlider: View {
    @ObservedObject var exposureManager: ExposureManager
    @Binding var iso: Float
    let range: (min: Float, max: Float)

    @State private var localValue: Int = 0
    @State private var isUserDragging: Bool = false

    private var stops: [Int] {
        Array(stride(from: Int(range.min), through: Int(range.max), by: 25))
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                if exposureManager.isManualISOMode {
                    exposureManager.enableAutoISO()
                }
            }) {
                Text("A")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(exposureManager.isManualISOMode ? Color.white : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(exposureManager.isManualISOMode ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.3))
                    )
            }
            .padding(.trailing, 6)

            TickRuler(
                value: $localValue,
                stops: stops,
                isMajor: { $0 % 400 == 0 || $0 == Int(range.min) },
                formatValue: { "\($0)" },
                onSelectionChange: { newValue in
                    iso = Float(newValue)
                },
                onInteractionStart: {
                    isUserDragging = true
                    if !exposureManager.isManualISOMode {
                        exposureManager.enableManualISO()
                    }
                },
                onInteractionEnd: {
                    isUserDragging = false
                    iso = Float(localValue)
                }
            )
        }
        .padding(.horizontal, 6)
        .onAppear {
            localValue = closestStop(for: Int(iso))
        }
        .onChange(of: iso) { _, newValue in
            if !isUserDragging {
                localValue = closestStop(for: Int(newValue))
            }
        }
        .onChange(of: exposureManager.currentISO) { _, newValue in
            if !exposureManager.isManualISOMode, !isUserDragging {
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
            ISOSlider(
                exposureManager: ExposureManager.shared,
                iso: .constant(400.0),
                range: (min: 50.0, max: 3200.0)
            )
            Image(systemName: "xmark")
                .font(.system(size: 12))
                .foregroundColor(Color.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
    }
}
