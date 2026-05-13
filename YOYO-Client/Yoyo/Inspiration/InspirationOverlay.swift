import SwiftUI

// MARK: - Inspiration Entry Button

struct InspirationEntryButton: View {
    let isShowingInspiration: Bool
    let rotation: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isShowingInspiration ? .accentColor : .white)
                .frame(width: 48, height: 48) // Significantly increased click area to 48x48
                .contentShape(Rectangle())
                .background(
                    Circle()
                        .fill(.regularMaterial)
                        .environment(\.colorScheme, .dark)
                        .frame(width: 40, height: 40) // Visually the circle is slightly enlarged to 40x40
                )
                .rotationEffect(.degrees(rotation))
                .animation(.easeInOut(duration: 0.3), value: rotation)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inspiration Overlay

struct InspirationOverlay: View {
    @ObservedObject var inspirationManager: InspirationManager
    @ObservedObject var orientationManager: OrientationManager
    @ObservedObject var viewState: CameraViewState
    let onHideInspiration: () -> Void

    @State private var currentIndex: Int = 0
    @State private var position: CGPoint? // Absolute position
    @State private var dragOffset: CGSize = .zero
    @State private var showingHistory: Bool = false

    /// Configuration
    private let collapsedSize: CGFloat = 300
    // private let expandedSize: CGFloat = 360 // No longer used

    private func currentFrameSize(in parentSize: CGSize) -> CGSize {
        if viewState.isInspirationMaximized {
            // Maximize logic: Fit screen with margins
            let isLandscape = orientationManager.currentDeviceOrientation.isLandscape
            if isLandscape {
                // In landscape (rotated 90/270), Width becomes Height visually
                return CGSize(width: parentSize.height - 24, height: parentSize.width - 24)
            } else {
                // Portrait mode: Increase top and bottom margins to avoid blocking the top toolbar and bottom capture button
                // Width increased slightly to utilize more screen space
                return CGSize(width: parentSize.width - 24, height: parentSize.height - 24)
            }
        } else {
            return CGSize(width: collapsedSize, height: collapsedSize)
        }
    }

    private func contentHeight(in frameSize: CGSize) -> CGFloat {
        frameSize.height - 60 // Estimated height for drag handle and header
    }

    var body: some View {
        GeometryReader { parentGeometry in
            let frameSize = currentFrameSize(in: parentGeometry.size)

            ZStack(alignment: .center) { // Center alignment for rotation consistency
                // Card Content
                VStack(spacing: 2) {
                    if !viewState.isInspirationMaximized {
                        dragHandle
                    } else {
                        Color.clear.frame(height: 12) // Spacing
                    }

                    headerView

                    if inspirationManager.isLoading {
                        loadingView
                    } else if let error = inspirationManager.errorMessage {
                        errorView(error)
                    } else if !inspirationManager.inspirations.isEmpty {
                        contentTabView(height: contentHeight(in: frameSize))
                    } else {
                        // Empty state placeholder
                        Color.clear.frame(height: 100)
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: frameSize.width, height: frameSize.height, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.65))
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                )
                // Apply rotation to the entire content container
                .rotationEffect(Angle(degrees: OrientationManager.rotationAngle(orientationManager.currentDeviceOrientation)))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: orientationManager.currentDeviceOrientation)
                // Position logic
                .position(viewState.isInspirationMaximized ? CGPoint(x: parentGeometry.size.width / 2, y: parentGeometry.size.height / 2) : effectivePosition(in: parentGeometry.size))
                .gesture(
                    viewState.isInspirationMaximized ? nil : DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            let currentPos = effectivePosition(in: parentGeometry.size)
                            let basePos = position ?? defaultPosition(in: parentGeometry.size)
                            let finalX = basePos.x + value.translation.width
                            let finalY = basePos.y + value.translation.height

                            // Boundary checks
                            let halfSize = collapsedSize / 2

                            let minX = halfSize
                            let maxX = parentGeometry.size.width - halfSize
                            let minY = halfSize
                            let maxY = parentGeometry.size.height - halfSize

                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                position = CGPoint(
                                    x: min(max(finalX, minX), maxX),
                                    y: min(max(finalY, minY), maxY)
                                )
                                dragOffset = .zero
                            }
                        }
                )
            }
            .onAppear {
                if position == nil {
                    position = defaultPosition(in: parentGeometry.size)
                }
            }
        }
        .onChange(of: currentIndex) { newIndex in
            Task {
                await inspirationManager.generateImage(for: newIndex)
            }
        }
    }

    // MARK: - Position Helpers

    private func defaultPosition(in size: CGSize) -> CGPoint {
        // Default: Bottom-Right, above the bottom bar
        // Assuming bottom bar is ~100-120pt
        let x = size.width - collapsedSize / 2 - 16
        let y = size.height - collapsedSize / 2 - 140
        return CGPoint(x: x, y: y)
    }

    private func effectivePosition(in size: CGSize) -> CGPoint {
        let basePos = position ?? defaultPosition(in: size)
        return CGPoint(
            x: basePos.x + dragOffset.width,
            y: basePos.y + dragOffset.height
        )
    }

    // MARK: - Subviews

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 4)
            .padding(.top, 8)
    }

    private var headerView: some View {
        HStack {
            // Credits
            HStack(spacing: 4) {
                Image(systemName: "star.circle")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                Text("\(inspirationManager.credits)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)

            Spacer()

            // History Button
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingHistory = true
            }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44) // Increase click area
                    .contentShape(Rectangle())
            }
            .sheet(isPresented: $showingHistory) {
                HistoryInspirationView(inspirationManager: inspirationManager, isPresented: $showingHistory)
            }

            // Expand/Collapse Toggle
            Button(action: {
                withAnimation(.spring()) {
                    viewState.isInspirationMaximized.toggle()
                }
            }) {
                Image(systemName: viewState.isInspirationMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44) // Increase click area
                    .contentShape(Rectangle())
            }

            // Close Button
            Button(action: {
                if viewState.isInspirationMaximized {
                    viewState.isInspirationMaximized = false
                }
                onHideInspiration()
            }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44) // Increase click area
                    .contentShape(Rectangle())
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 28, height: 28) // Maintain visual size
                    )
            }
        }
        .padding(.horizontal, 10)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                .scaleEffect(1.2)
            Text(String.aiInspirationLoading.localized)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundColor(.yellow)
            Text(error)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private func contentTabView(height: CGFloat) -> some View {
        TabView(selection: $currentIndex) {
            ForEach(inspirationManager.inspirations.indices, id: \.self) { index in
                inspirationCard(inspiration: inspirationManager.inspirations[index])
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: height)
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
    }

    private func inspirationCard(inspiration: AIInspiration) -> some View {
        VStack(spacing: 8) {
            // Image
            if let image = inspiration.image {
                Image(uiImage: image)
                    .resizable()
                    // Priority will be given to displaying the complete 1024x1024 inspiration image
                    .aspectRatio(contentMode: .fit)
                    .frame(height: viewState.isInspirationMaximized ? nil : 150)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: viewState.isInspirationMaximized ? .infinity : 150)
                    .layoutPriority(1) // When maximizing, prioritize the image to occupy as much space as possible
                    .onTapGesture {
                        withAnimation(.spring()) {
                            viewState.isInspirationMaximized.toggle()
                        }
                    }
            } else {
                // Placeholder / Loading
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))

                    if inspiration.imageGenPrompt.isEmpty {
                        EmptyView()
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
                .frame(height: viewState.isInspirationMaximized ? nil : 150)
                .frame(maxHeight: viewState.isInspirationMaximized ? .infinity : 150)
                .layoutPriority(1)
                .onTapGesture {
                    withAnimation(.spring()) {
                        viewState.isInspirationMaximized.toggle()
                    }
                }
            }

            // Text Info
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(inspiration.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        Spacer()

                        if !inspiration.style.isEmpty {
                            Text(inspiration.style)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentColor)
                                .cornerRadius(4)
                        }
                    }

                    Text(inspiration.description)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: viewState.isInspirationMaximized ? 120 : nil) // Limit the height of the text area when maximizing to prevent the image from being squeezed

            if !viewState.isInspirationMaximized {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 0)
        .padding(.bottom, 8) // Room for TabView dots
    }
}

#Preview {
    InspirationOverlay(
        inspirationManager: InspirationManager.shared,
        orientationManager: OrientationManager.shared,
        viewState: CameraViewState.shared,
        onHideInspiration: {}
    )
}
