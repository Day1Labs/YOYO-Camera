import SwiftUI
import UIKit

// MARK: - View Modifiers

enum StatusType {
    case success
    case error

    var iconName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .success:
            return .white
        case .error:
            return .red
        }
    }
}

struct StatusViewModifier: ViewModifier {
    @Binding var isShowing: Bool
    let statusType: StatusType
    let message: String
    let duration: TimeInterval

    init(
        isShowing: Binding<Bool>,
        statusType: StatusType,
        message: String,
        duration: TimeInterval = 2.0
    ) {
        _isShowing = isShowing
        self.statusType = statusType
        self.message = message
        self.duration = duration
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isShowing {
                        VStack {
                            Spacer()

                            HStack {
                                Image(systemName: statusType.iconName)
                                    .foregroundColor(statusType.iconColor)
                                    .font(.system(size: 18))

                                Text(message)
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color(white: 0.1).opacity(0.8))
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            )
                            .transition(
                                .opacity.combined(with: .move(edge: .bottom))
                            )

                            Spacer()
                                .frame(height: 100)
                        }
                    }
                }
            )
            .onChange(of: isShowing) { _, newValue in
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        withAnimation {
                            isShowing = false
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isShowing)
    }
}
