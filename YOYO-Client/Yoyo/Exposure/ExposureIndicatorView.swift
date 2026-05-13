
import SwiftUI

// MARK: - Exposure indicator view

struct ExposureIndicatorView: View {
    let position: CGPoint
    let exposureCompensation: Float
    let isLocked: Bool
    let isExposureOnlyLocked: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)

            if abs(exposureCompensation) > 0.01 {
                Text(String(format: "%.1f", exposureCompensation))
                    .font(.caption2)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 2)
        .position(position)
    }
}

// MARK: - preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        ExposureIndicatorView(
            position: CGPoint(x: 200, y: 300),
            exposureCompensation: 0.5,
            isLocked: true,
            isExposureOnlyLocked: false
        )
    }
}
