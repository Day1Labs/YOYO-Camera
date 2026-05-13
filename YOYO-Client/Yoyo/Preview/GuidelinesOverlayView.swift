import SwiftUI

// MARK: - Composition Overlay View

final class GuidelinesOverlayView: UIView {
    var type: CameraSettingsState.GuidelinesType = .off {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = UIColor.clear
    }

    override func draw(_ rect: CGRect) {
        guard type != .off else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [])

        let width = rect.width
        let height = rect.height

        switch type {
        case .off:
            break

        case .ruleOfThirds:
            drawRuleOfThirds(context: context, width: width, height: height)

        case .ruleOfThirdsWithDiagonal:
            drawRuleOfThirdsWithDiagonal(context: context, width: width, height: height)

        case .goldenRatio:
            drawGoldenRatio(context: context, width: width, height: height)

        case .grid6x4:
            drawGrid6x4(context: context, width: width, height: height)
        }

        context.strokePath()
    }

    // MARK: - Drawing Methods

    private func drawRuleOfThirds(context: CGContext, width: CGFloat, height: CGFloat) {
        // vertical(rule of thirds)
        let verticalLineSpacing = width / 3
        for i in 1 ... 2 {
            let x = CGFloat(i) * verticalLineSpacing
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: height))
        }

        // horizontal(rule of thirds)
        let horizontalLineSpacing = height / 3
        for i in 1 ... 2 {
            let y = CGFloat(i) * horizontalLineSpacing
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: width, y: y))
        }
    }

    private func drawGoldenRatio(context: CGContext, width: CGFloat, height: CGFloat) {
        // Golden ratio ≈ 0.618
        let goldenRatio: CGFloat = 0.618

        // verticalgolden-section line
        let x1 = width * goldenRatio
        let x2 = width * (1 - goldenRatio)
        context.move(to: CGPoint(x: x1, y: 0))
        context.addLine(to: CGPoint(x: x1, y: height))
        context.move(to: CGPoint(x: x2, y: 0))
        context.addLine(to: CGPoint(x: x2, y: height))

        // horizontalgolden-section line
        let y1 = height * goldenRatio
        let y2 = height * (1 - goldenRatio)
        context.move(to: CGPoint(x: 0, y: y1))
        context.addLine(to: CGPoint(x: width, y: y1))
        context.move(to: CGPoint(x: 0, y: y2))
        context.addLine(to: CGPoint(x: width, y: y2))
    }

    private func drawGrid6x4(context: CGContext, width: CGFloat, height: CGFloat) {
        // 6x4 grid (5 vertical lines, 3 horizontal lines)
        let verticalSpacing = width / 6
        for i in 1 ... 5 {
            let x = CGFloat(i) * verticalSpacing
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: height))
        }

        let horizontalSpacing = height / 4
        for i in 1 ... 3 {
            let y = CGFloat(i) * horizontalSpacing
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: width, y: y))
        }
    }

    private func drawRuleOfThirdsWithDiagonal(context: CGContext, width: CGFloat, height: CGFloat) {
        // Draw the rule of thirds
        drawRuleOfThirds(context: context, width: width, height: height)

        // diagonal
        context.move(to: CGPoint(x: 0, y: 0))
        context.addLine(to: CGPoint(x: width, y: height))
        context.move(to: CGPoint(x: width, y: 0))
        context.addLine(to: CGPoint(x: 0, y: height))
    }
}
