import SwiftData
import SwiftUI

// MARK: - Photo Gallery Button Design Constants

private enum PhotoGalleryButtonDesign {
    /// Threshold used to determine a small screen, aligned with `CameraControlDesign`
    static let smallScreenThreshold: CGFloat = 390

    /// Whether the current device is considered a small screen
    static var isSmallScreen: Bool {
        UIScreen.main.bounds.width < smallScreenThreshold
    }

    /// Visual size of the button
    static var buttonSize: CGFloat {
        isSmallScreen ? 40 : 48
    }

    /// Minimum touch target size (44pt recommended by Apple's HIG)
    static let minTouchSize: CGFloat = 44
}

/// Photo gallery button subview with performance optimizations
struct PhotoGalleryButton: View, Equatable {
    let latestPhoto: PhotoAsset?
    let rotation: Double
    var isCircular: Bool = false
    let onTap: () -> Void

    @State private var captureState: CaptureState = .idle

    private var buttonSize: CGFloat {
        PhotoGalleryButtonDesign.buttonSize
    }

    private var touchSize: CGFloat {
        max(buttonSize, PhotoGalleryButtonDesign.minTouchSize)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // 1. Background and content
                if let lastPhoto = latestPhoto {
                    AsyncThumbnailImage(
                        assetIdentifier: lastPhoto.assetIdentifier,
                        photoId: lastPhoto.id.uuidString
                    )
                    .scaledToFill()
                    .frame(width: buttonSize, height: buttonSize)
                    .mask {
                        if isCircular {
                            Circle()
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                        }
                    }
                    .rotationEffect(.degrees(rotation))
                } else {
                    // Empty-state background
                    Group {
                        if isCircular {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().fill(Color.white.opacity(0.1)))
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.1)))
                        }
                    }

                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: buttonSize * 0.4, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .rotationEffect(.degrees(rotation))
                }

                // 2. Unified border styling, matching `GlassButtonBackground`
                if isCircular {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                }

                // 3. Processing state: animated highlight border
                if captureState == .processing || captureState == .saving {
                    ProcessingBorder(isCircular: isCircular, color: UIColor.white.withAlphaComponent(0.75))
                }
            }
            // Use a softer, simpler shadow
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            .frame(width: buttonSize, height: buttonSize)
            .rotationEffect(.degrees(rotation))
            // Expand the touch target to Apple's recommended 44pt
            .frame(width: touchSize, height: touchSize)
            .contentShape(Rectangle())
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraCaptureStateChanged)) { notification in
            if let newState = notification.userInfo?[CameraNotificationKeys.captureState] as? CaptureState {
                withAnimation {
                    captureState = newState
                }
            }
        }
    }

    /// Performance optimization: more efficient equality comparison
    static func == (lhs: PhotoGalleryButton, rhs: PhotoGalleryButton) -> Bool {
        lhs.latestPhoto?.id == rhs.latestPhoto?.id &&
            lhs.latestPhoto?.assetIdentifier == rhs.latestPhoto?.assetIdentifier &&
            lhs.rotation == rhs.rotation &&
            lhs.isCircular == rhs.isCircular
    }
}

/// Internal Core Animation border view
private struct ProcessingBorder: UIViewRepresentable {
    let isCircular: Bool
    let color: UIColor

    func makeUIView(context _: Context) -> BorderView {
        BorderView()
    }

    func updateUIView(_ uiView: BorderView, context _: Context) {
        uiView.isCircular = isCircular
        uiView.strokeColor = color
    }

    final class BorderView: UIView {
        var isCircular: Bool = false {
            didSet {
                if oldValue != isCircular {
                    setNeedsLayout()
                }
            }
        }

        var strokeColor: UIColor = .white {
            didSet {
                ringLayer.strokeColor = strokeColor.cgColor
            }
        }

        private let ringLayer = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear

            ringLayer.fillColor = UIColor.clear.cgColor
            ringLayer.strokeColor = strokeColor.cgColor
            ringLayer.lineWidth = 1.5
            ringLayer.lineCap = .round
            layer.addSublayer(ringLayer)

            startAnimation()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError() }

        private func startAnimation() {
            let duration: CFTimeInterval = 2.0

            // Head animation: moves from 0 to 1
            let headAnimation = CABasicAnimation(keyPath: "strokeEnd")
            headAnimation.fromValue = 0
            headAnimation.toValue = 1
            headAnimation.duration = duration
            headAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)

            // Tail animation: moves from 0 to 1
            let tailAnimation = CABasicAnimation(keyPath: "strokeStart")
            tailAnimation.fromValue = 0
            tailAnimation.toValue = 1
            tailAnimation.duration = duration
            tailAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            // Delay the tail animation to create the meteor-like streak length
            tailAnimation.beginTime = 0.3

            let group = CAAnimationGroup()
            group.animations = [headAnimation, tailAnimation]
            group.duration = duration + 0.3
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            group.fillMode = .forwards

            ringLayer.add(group, forKey: "stroke")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            ringLayer.frame = bounds

            let path: UIBezierPath
            if isCircular {
                path = UIBezierPath(ovalIn: bounds)
            } else {
                path = UIBezierPath(roundedRect: bounds, cornerRadius: 8)
            }
            ringLayer.path = path.cgPath
        }
    }
}
