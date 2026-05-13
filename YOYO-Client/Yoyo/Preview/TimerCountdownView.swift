import AudioToolbox
import SwiftUI

struct TimerCountdownView: View {
    let countdownSeconds: Int
    let isActive: Bool
    let onCountdownFinished: () -> Void

    @State private var currentCount: Int
    @State private var timer: Timer?

    init(countdownSeconds: Int, isActive: Bool, onCountdownFinished: @escaping () -> Void) {
        self.countdownSeconds = countdownSeconds
        self.isActive = isActive
        self.onCountdownFinished = onCountdownFinished
        _currentCount = State(initialValue: countdownSeconds)
    }

    var body: some View {
        Text("\(currentCount)")
            .font(.system(size: 42, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 12)
            .padding(.top, 10)
            .onChange(of: isActive) { _, newValue in
                currentCount = countdownSeconds
                if newValue {
                    startCountdown()
                } else {
                    stopCountdown()
                }
            }
            .onChange(of: countdownSeconds) { _, newValue in
                currentCount = newValue
                if isActive {
                    stopCountdown()
                    startCountdown()
                }
            }
            .onAppear {
                if isActive {
                    startCountdown()
                }
            }
            .onDisappear {
                stopCountdown()
            }
    }

    private func startCountdown() {
        // create
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            // (systemcameracountdown)
            AudioServicesPlaySystemSound(1103) // System camera countdown beep

            currentCount -= 1

            if currentCount <= 0 {
                stopCountdown()
                onCountdownFinished()
            }
        }
    }

    private func stopCountdown() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    @Previewable @State var isActive = true

    TimerCountdownView(
        countdownSeconds: 3,
        isActive: isActive,
        onCountdownFinished: {
            print("Countdown finished")
            isActive = false
        }
    )
}
