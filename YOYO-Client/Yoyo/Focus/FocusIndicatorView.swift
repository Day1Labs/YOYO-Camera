import SwiftUI

// MARK: - focus indicator view

struct FocusIndicatorView: View {
    let focusState: FocusState
    let focusMode: FocusMode
    let position: CGPoint
    let isLocked: Bool

    var body: some View {
        ZStack {
            // Simplified single-turn design
            Circle()
                .stroke(focusColor, lineWidth: 1)
                .frame(width: 44, height: 44)

            // center indicator
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(focusColor)
            } else {
                Circle()
                    .fill(focusColor)
                    .frame(width: 2, height: 2)
            }
        }
        .opacity(0.8)
        .position(position)
    }

    private var focusColor: Color {
        if isLocked {
            return .accentColor
        }

        switch focusState {
        case .idle:
            return .white.opacity(0.6)
        case .focusing:
            return .white
        case .locked:
            return .accentColor
        case .failed:
            return .red
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()

        VStack {
            Spacer()

            // Analog focus indicator
            FocusIndicatorView(
                focusState: .focusing,
                focusMode: .tap,
                position: CGPoint(x: 200, y: 300),
                isLocked: true
            )
        }
    }
}
