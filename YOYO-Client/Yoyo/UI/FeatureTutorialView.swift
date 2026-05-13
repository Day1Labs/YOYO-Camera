import SwiftUI

// MARK: - Tutorial Manager

final class TutorialManager: ObservableObject {
    static let shared = TutorialManager()

    private let filterGalleryTutorialKey = "hasShownFilterGalleryTutorial"
    private let cameraGestureTutorialKey = "hasShownCameraGestureTutorial"

    @Published var hasShownFilterGalleryTutorial: Bool {
        didSet {
            UserDefaults.standard.set(hasShownFilterGalleryTutorial, forKey: filterGalleryTutorialKey)
        }
    }

    @Published var hasShownCameraGestureTutorial: Bool {
        didSet {
            UserDefaults.standard.set(hasShownCameraGestureTutorial, forKey: cameraGestureTutorialKey)
        }
    }

    private init() {
        hasShownFilterGalleryTutorial = UserDefaults.standard.bool(forKey: filterGalleryTutorialKey)
        hasShownCameraGestureTutorial = UserDefaults.standard.bool(forKey: cameraGestureTutorialKey)
    }

    func resetAllTutorials() {
        hasShownFilterGalleryTutorial = false
        hasShownCameraGestureTutorial = false
    }
}

// MARK: - Tutorial Step Model

struct TutorialStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let gesture: TutorialGesture?
}

enum TutorialGesture {
    case longPress
    case swipeHorizontal
    case swipeVerticalLeft
    case swipeVerticalCenter
    case swipeVerticalRight
}

// MARK: - Filter Gallery Tutorial View

struct FilterGalleryTutorialView: View {
    @Binding var isPresented: Bool
    @State private var isPressing = false

    /// Consistent with `CameraLayoutConfig.bottomControlHeight`.
    private let tutorialHeight: CGFloat = 210

    var body: some View {
        VStack {
            Spacer()

            ZStack {
                // Translucent mask.
                Color.black.opacity(0.7)

                VStack(spacing: 16) {
                    // Long press gesture indicator.
                    LongPressIndicator(isPressing: isPressing)

                    // Prompt copy.
                    Text(String.tutorialFilterFavoriteDesc.localized)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))

                    // Close button.
                    Button {
                        dismissTutorial()
                    } label: {
                        Text(String.tutorialGotIt.localized)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white))
                    }
                }
                .padding(.bottom, 16)
            }
            .frame(height: tutorialHeight)
        }
        .ignoresSafeArea()
        .onAppear {
            isPressing = true
        }
    }

    private func dismissTutorial() {
        TutorialManager.shared.hasShownFilterGalleryTutorial = true
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

/// Long press gesture indicator animation component.
private struct LongPressIndicator: View {
    let isPressing: Bool

    var body: some View {
        ZStack {
            // Long press ripple effect.
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                .frame(width: isPressing ? 48 : 24, height: isPressing ? 48 : 24)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPressing)

            // Pressure point.
            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 8, height: 8)

            // Finger icon.
            Image(systemName: "hand.point.down.fill")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.85))
                .offset(y: -26)
        }
        .frame(height: 60)
    }
}

// MARK: - Camera Gesture Tutorial View

struct CameraGestureTutorialView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var isAnimating = false

    private let steps: [TutorialStep] = [
        TutorialStep(
            icon: "camera.filters",
            title: .tutorialSwipeFilterTitle.localized,
            description: .tutorialSwipeFilterDesc.localized,
            gesture: .swipeHorizontal
        ),
        TutorialStep(
            icon: "slider.horizontal.3",
            title: .tutorialFilterIntensityTitle.localized,
            description: .tutorialFilterIntensityDesc.localized,
            gesture: .swipeVerticalLeft
        ),
        TutorialStep(
            icon: "sun.max",
            title: .tutorialExposureTitle.localized,
            description: .tutorialExposureDesc.localized,
            gesture: .swipeVerticalCenter
        ),
        TutorialStep(
            icon: "magnifyingglass",
            title: .tutorialZoomTitle.localized,
            description: .tutorialZoomDesc.localized,
            gesture: .swipeVerticalRight
        ),
    ]

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button {
                        dismissTutorial()
                    } label: {
                        Text(String.tutorialSkip.localized)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 8)

                Spacer()

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        TutorialPageView(step: step, isAnimating: isAnimating)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 340)

                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0 ..< steps.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }
                .padding(.top, 16)

                Spacer()

                // Navigation buttons
                HStack(spacing: 16) {
                    if currentPage > 0 {
                        Button {
                            withAnimation {
                                currentPage -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Circle().fill(.white.opacity(0.15)))
                        }
                    }

                    Button {
                        if currentPage < steps.count - 1 {
                            withAnimation {
                                currentPage += 1
                            }
                        } else {
                            dismissTutorial()
                        }
                    } label: {
                        Text(currentPage < steps.count - 1 ? String.tutorialNext.localized : String.tutorialStartUsing.localized)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.white))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                isAnimating = true
            }
        }
        .onChange(of: currentPage) { _, _ in
            // Reset animation for new page
            isAnimating = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isAnimating = true
                }
            }
        }
    }

    private func dismissTutorial() {
        TutorialManager.shared.hasShownCameraGestureTutorial = true
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

// MARK: - Tutorial Page View

private struct TutorialPageView: View {
    let step: TutorialStep
    let isAnimating: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Gesture illustration
            gestureIllustration
                .frame(width: 160, height: 160)

            // Content
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: step.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.accentColor)

                    Text(step.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(step.description)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private var gestureIllustration: some View {
        switch step.gesture {
        case .longPress:
            LongPressGestureIllustration(isAnimating: isAnimating)
        case .swipeHorizontal:
            SwipeHorizontalGestureIllustration(isAnimating: isAnimating)
        case .swipeVerticalLeft:
            SwipeVerticalGestureIllustration(isAnimating: isAnimating, position: .left)
        case .swipeVerticalCenter:
            SwipeVerticalGestureIllustration(isAnimating: isAnimating, position: .center)
        case .swipeVerticalRight:
            SwipeVerticalGestureIllustration(isAnimating: isAnimating, position: .right)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Gesture Illustrations

private struct LongPressGestureIllustration: View {
    let isAnimating: Bool
    @State private var isPressing = false

    var body: some View {
        ZStack {
            // Filter card placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .frame(width: 80, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            // Finger indicator
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.9))
                .offset(y: 50)
                .scaleEffect(isPressing ? 0.9 : 1.0)

            // Press ripple effect
            Circle()
                .stroke(Color.red.opacity(isPressing ? 0.6 : 0), lineWidth: 2)
                .frame(width: isPressing ? 60 : 30, height: isPressing ? 60 : 30)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPressing)

            // Heart icon appearing
            Image(systemName: "heart.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)
                .offset(x: 30, y: -20)
                .opacity(isPressing ? 1 : 0)
                .scaleEffect(isPressing ? 1 : 0.5)
        }
        .onAppear {
            if isAnimating {
                startAnimation()
            }
        }
        .onChange(of: isAnimating) { _, newValue in
            if newValue {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            isPressing = true
        }
    }
}

private struct SwipeHorizontalGestureIllustration: View {
    let isAnimating: Bool
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack {
            // Viewfinder frame
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                .frame(width: 120, height: 90)

            // Filter cards
            HStack(spacing: 8) {
                ForEach(0 ..< 3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(filterColor(for: index))
                        .frame(width: 30, height: 40)
                        .opacity(index == 1 ? 1 : 0.5)
                }
            }
            .offset(x: offset)

            // Swipe arrow
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Image(systemName: "hand.point.up.left.fill")
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 20))
            .foregroundColor(.white.opacity(0.8))
            .offset(y: 60)
        }
        .onAppear {
            if isAnimating {
                startAnimation()
            }
        }
        .onChange(of: isAnimating) { _, newValue in
            if newValue {
                startAnimation()
            }
        }
    }

    private func filterColor(for index: Int) -> Color {
        switch index {
        case 0: return .orange.opacity(0.6)
        case 1: return .blue.opacity(0.6)
        default: return .purple.opacity(0.6)
        }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            offset = 20
        }
    }
}

enum VerticalGesturePosition {
    case left, center, right
}

private struct SwipeVerticalGestureIllustration: View {
    let isAnimating: Bool
    let position: VerticalGesturePosition
    @State private var offset: CGFloat = 0

    private var positionOffset: CGFloat {
        switch position {
        case .left: return -40
        case .center: return 0
        case .right: return 40
        }
    }

    private var indicatorColor: Color {
        switch position {
        case .left: return .blue
        case .center: return .yellow
        case .right: return .green
        }
    }

    private var areaLabel: String {
        switch position {
        case .left: return .tutorialAreaLeft.localized
        case .center: return .tutorialAreaCenter.localized
        case .right: return .tutorialAreaRight.localized
        }
    }

    var body: some View {
        ZStack {
            // Viewfinder frame with zones
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 120, height: 90)

                // Zone dividers
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(position == .left ? indicatorColor.opacity(0.2) : Color.clear)
                        .frame(width: 40)
                    Rectangle()
                        .fill(position == .center ? indicatorColor.opacity(0.2) : Color.clear)
                        .frame(width: 40)
                    Rectangle()
                        .fill(position == .right ? indicatorColor.opacity(0.2) : Color.clear)
                        .frame(width: 40)
                }
                .frame(width: 120, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Vertical dashed lines
                HStack(spacing: 38) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 70)
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 70)
                }
            }

            // Finger with vertical movement
            VStack(spacing: 2) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "hand.point.up.fill")
                    .font(.system(size: 28))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(indicatorColor)
            .offset(x: positionOffset, y: offset)

            // Area label
            Text(areaLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .offset(x: positionOffset, y: 60)
        }
        .onAppear {
            if isAnimating {
                startAnimation()
            }
        }
        .onChange(of: isAnimating) { _, newValue in
            if newValue {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            offset = -15
        }
    }
}

// MARK: - Preview

#Preview("Filter Gallery Tutorial") {
    FilterGalleryTutorialView(isPresented: .constant(true))
}

#Preview("Camera Gesture Tutorial") {
    CameraGestureTutorialView(isPresented: .constant(true))
}
