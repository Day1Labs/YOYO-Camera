import SwiftUI

struct RecordingTimerView: View {
    let startTime: Date

    var body: some View {
        TimelineView(.periodic(from: startTime, by: 1.0)) { context in
            RecordingTimerContent(duration: context.date.timeIntervalSince(startTime))
        }
    }
}

private struct RecordingTimerContent: View {
    let duration: TimeInterval

    private var timeString: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Text(timeString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.98))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
    }
}

#Preview {
    ZStack {
        Color.gray
        VStack(spacing: 20) {
            RecordingTimerView(startTime: Date())
            RecordingTimerView(startTime: Date().addingTimeInterval(-65))
            RecordingTimerView(startTime: Date().addingTimeInterval(-3665))
        }
    }
}
