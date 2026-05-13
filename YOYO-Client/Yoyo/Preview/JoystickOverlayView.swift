import UIKit

final class JoystickOverlayView: UIView {
    private let rulerContainer = UIView()
    private let knobView = UIView()
    private var knobCenterYConstraint: NSLayoutConstraint?

    // Ruler configuration
    private let tickCount = 21 // Total ticks (must be odd to have a center tick)
    private let tickSpacing: CGFloat = 12
    private let minTickWidth: CGFloat = 8
    private let maxTickWidth: CGFloat = 36

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Ruler Container
        rulerContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rulerContainer)

        // Generate Ticks
        let centerIndex = tickCount / 2
        for i in 0 ..< tickCount {
            let tick = UIView()
            tick.translatesAutoresizingMaskIntoConstraints = false
            tick.backgroundColor = UIColor.white.withAlphaComponent(0.5)
            tick.layer.cornerRadius = 1
            rulerContainer.addSubview(tick)

            // Calculate width based on distance from center
            let distFromCenter = abs(i - centerIndex)
            let progress = CGFloat(distFromCenter) / CGFloat(centerIndex)
            let width = minTickWidth + (maxTickWidth - minTickWidth) * progress

            NSLayoutConstraint.activate([
                tick.centerXAnchor.constraint(equalTo: rulerContainer.centerXAnchor),
                tick.widthAnchor.constraint(equalToConstant: width),
                tick.heightAnchor.constraint(equalToConstant: 2),
                tick.centerYAnchor.constraint(equalTo: rulerContainer.centerYAnchor, constant: CGFloat(i - centerIndex) * tickSpacing),
            ])
        }

        // Knob (Indicator)
        knobView.translatesAutoresizingMaskIntoConstraints = false
        knobView.backgroundColor = .white
        knobView.layer.cornerRadius = 2
        // Shadow for better visibility
        knobView.layer.shadowColor = UIColor.black.cgColor
        knobView.layer.shadowOpacity = 0.5
        knobView.layer.shadowOffset = CGSize(width: 0, height: 1)
        knobView.layer.shadowRadius = 2
        addSubview(knobView)

        NSLayoutConstraint.activate([
            // Container alignment
            rulerContainer.topAnchor.constraint(equalTo: topAnchor),
            rulerContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            rulerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            rulerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Knob alignment (center aligned with ruler)
            knobView.centerXAnchor.constraint(equalTo: centerXAnchor),
            knobView.heightAnchor.constraint(equalToConstant: 4),
            // Initial width (will be updated)
            knobView.widthAnchor.constraint(equalToConstant: minTickWidth),
        ])

        // Dynamic knob position (initially centered)
        knobCenterYConstraint = knobView.centerYAnchor.constraint(equalTo: centerYAnchor)
        knobCenterYConstraint?.isActive = true
    }

    func updateKnobOffset(_ offset: CGFloat) {
        knobCenterYConstraint?.constant = offset

        // Update Knob Width based on position to match the ruler style
        // Calculate effective progress (0 at center, 1 at ends)
        let totalHeight = CGFloat(tickCount - 1) * tickSpacing
        let progress = min(1.0, abs(offset) / (totalHeight / 2.0))
        let width = minTickWidth + (maxTickWidth - minTickWidth) * progress

        // Update width constraint
        if let widthConstraint = knobView.constraints.first(where: { $0.firstAttribute == .width }) {
            widthConstraint.constant = width
        }
    }
}
