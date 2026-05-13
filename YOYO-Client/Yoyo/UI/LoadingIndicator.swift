import SwiftUI

/// Loading indicator backed by Core Animation to avoid main-thread stutter.
struct LoadingIndicator: UIViewRepresentable, Equatable {
    func makeUIView(context _: Context) -> SpinnerView {
        SpinnerView()
    }

    func updateUIView(_: SpinnerView, context _: Context) {
        // No state-driven updates required, Core Animation loops on its own.
    }

    /// Always equal to avoid triggering unnecessary redraws.
    static func == (_: LoadingIndicator, _: LoadingIndicator) -> Bool {
        true
    }

    /// Private UIView subclass using CAShapeLayer and CABasicAnimation.
    final class SpinnerView: UIView {
        private let ringLayer = CAShapeLayer()
        private let lineWidth: CGFloat = 3
        private var didSetup = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            setup()
        }

        required init?(coder: NSCoder) { super.init(coder: coder); setup() }

        private func setup() {
            guard !didSetup else { return }
            didSetup = true
            ringLayer.fillColor = UIColor.clear.cgColor
            ringLayer.strokeColor = UIColor.white.cgColor
            ringLayer.lineWidth = lineWidth
            ringLayer.lineCap = .round
            layer.addSublayer(ringLayer)

            // Optimized animation: achieve a "snake" chasing effect on any path.
            // This animation does not depend on the path shape.
            let duration: CFTimeInterval = 1.5

            // Head animation: running from 0 to 1.
            let headAnimation = CABasicAnimation(keyPath: "strokeEnd")
            headAnimation.fromValue = 0
            headAnimation.toValue = 1
            headAnimation.duration = duration
            headAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)

            // Tail animation: running from 0 to 1.
            let tailAnimation = CABasicAnimation(keyPath: "strokeStart")
            tailAnimation.fromValue = 0
            tailAnimation.toValue = 1
            tailAnimation.duration = duration
            tailAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            // The tail starts slightly delayed, creating a change in length            tailAnimation.beginTime = 0.1

            let group = CAAnimationGroup()
            group.animations = [headAnimation, tailAnimation]
            group.duration = duration + 0.1
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            group.fillMode = .forwards

            ringLayer.add(group, forKey: "yoyo.loading.stroke")

            // Keep only the path flow animation. Rotating non-circular paths can wobble visually.
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            ringLayer.frame = bounds
            updatePath()
        }

        private func updatePath() {
            // Use a rounded rectangle / circular path.
            let path = UIBezierPath(roundedRect: bounds, cornerRadius: min(bounds.width, bounds.height) / 2)
            ringLayer.path = path.cgPath
        }
    }
}
