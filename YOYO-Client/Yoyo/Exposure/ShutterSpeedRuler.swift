import SwiftUI

// MARK: - shutter speed ruler(Ruler)

struct ShutterSpeedRuler: View {
    @Binding var value: Double
    let stops: [Double]
    var onSelectionChange: ((Double) -> Void)?
    var onInteractionStart: (() -> Void)?
    var onInteractionEnd: (() -> Void)?

    /// ()
    private let majorStops: Set<Double> = [
        1.0 / 8000, 1.0 / 2000, 1.0 / 1000, 1.0 / 500, 1.0 / 250, 1.0 / 125,
        1.0 / 60, 1.0 / 30, 1.0 / 15, 1.0 / 8, 1.0 / 4, 1.0 / 2,
        1.0, 2.0, 4.0, 8.0, 15.0, 30.0,
    ]

    @State private var internalValue: Double = 0

    var body: some View {
        TickRuler(
            value: $internalValue,
            stops: stops,
            isMajor: { stop in
                majorStops.contains { abs($0 - stop) < 0.000001 }
            },
            formatValue: { CameraParameterFormatter.formatShutterSpeed($0) },
            onSelectionChange: onSelectionChange,
            onInteractionStart: onInteractionStart,
            onInteractionEnd: onInteractionEnd
        )
        .onAppear {
            internalValue = closestStop(for: value)
        }
        .onChange(of: value) { _, newValue in
            let closest = closestStop(for: newValue)
            if internalValue != closest {
                internalValue = closest
            }
        }
        .onChange(of: internalValue) { _, newValue in
            if value != newValue {
                value = newValue
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
        ShutterSpeedRuler(
            value: .constant(1.0 / 60),
            stops: CameraParameterFormatter.standardShutterSpeedStops
        )
    }
}
