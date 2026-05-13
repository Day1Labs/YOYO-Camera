import SwiftUI

// MARK: - exposure compensation slider view(horizontal)

struct ExposureCompensationSlider: View {
    @Binding var exposureCompensation: Float
    let range: (min: Float, max: Float)

    @State private var localValue: Double = 0.0

    private var stops: [Double] {
        Array(stride(from: Double(range.min), through: Double(range.max), by: 0.1))
            .map { ($0 * 10).rounded() / 10 } // fix floating-point precision
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                exposureCompensation = 0.0
                localValue = 0.0
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .padding(.trailing, 6)

            TickRuler(
                value: $localValue,
                stops: stops,
                isMajor: { abs($0.truncatingRemainder(dividingBy: 1.0)) < 0.01 },
                formatValue: { CameraParameterFormatter.formatExposureCompensation(Float($0)) },
                onSelectionChange: { newValue in
                    exposureCompensation = Float(newValue)
                },
                onInteractionEnd: {
                    exposureCompensation = Float(localValue)
                }
            )
        }
        .padding(.horizontal, 6)
        .onAppear {
            localValue = closestStop(for: Double(exposureCompensation))
        }
        .onChange(of: exposureCompensation) { _, newValue in
            let closest = closestStop(for: Double(newValue))
            if localValue != closest {
                localValue = closest
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
            ExposureCompensationSlider(
                exposureCompensation: .constant(0.0),
                range: (min: -2.0, max: 2.0)
            )
            Image(systemName: "xmark")
                .font(.system(size: 12))
                .foregroundColor(Color.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
    }
}
