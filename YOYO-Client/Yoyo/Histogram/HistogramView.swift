import Accelerate
import AVFoundation
import UIKit

/// Histogram display view
final class HistogramView: UIView {
    private enum Style {
        static let cornerRadius: CGFloat = 6
        static let horizontalPadding: CGFloat = 2
        static let verticalPadding: CGFloat = 2
        static let backgroundColor = UIColor.black.withAlphaComponent(0.5)
        static let monoStroke = UIColor.white.withAlphaComponent(0.9)
        static let monoFill = UIColor.white.withAlphaComponent(0.4)
        static let redStroke = UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 0.9)
        static let greenStroke = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.9)
        static let blueStroke = UIColor(red: 0.25, green: 0.5, blue: 1.0, alpha: 0.9)
        static let redFill = UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 0.28)
        static let greenFill = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.28)
        static let blueFill = UIColor(red: 0.25, green: 0.5, blue: 1.0, alpha: 0.28)
    }

    private enum DisplayMode { case luma, rgb }

    // MARK: - Properties

    /// Histogram data (256 bins in the range 0-255)
    private var histogramData: [Int] = Array(repeating: 0, count: 256)

    /// Is there valid data?
    private var hasData: Bool = false

    /// RGB histogram data
    private var rgbHistogramData: (r: [Int], g: [Int], b: [Int]) = (
        Array(repeating: 0, count: 256),
        Array(repeating: 0, count: 256),
        Array(repeating: 0, count: 256)
    )

    /// Is there valid RGB data?
    private var hasRGBData: Bool = false

    /// Display mode (click to switch)
    private var displayMode: DisplayMode = .luma

    /// Minimum time interval between refresh and calculation (speed limit, reduce CPU)
    private let minInterval: CFTimeInterval = 0.05 // 20fps
    private var lastDrawTime: CFTimeInterval = 0
    private var lastProcessTime: CFTimeInterval = 0

    /// Unified adaptive sampling step configuration (common to RGB/Luma)
    private var sampleStride: Int = 4
    private let sampleStrideMin: Int = 1
    private let sampleStrideMax: Int = 8
    private let sampleStrideInitial: Int = 4
    private var lastProcessDuration: CFTimeInterval = 0

    /// Time domain smoothing coefficient (exponential moving average)
    private let smoothingAlpha: CGFloat = 0.3

    // Sampling step size (used for RGB/Luma calculation downsampling, reducing CPU)
    // Unified to sampleStride variadic parameters

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        displayMode = (displayMode == .luma) ? .rgb : .luma
        // When switching modes, reset the throttling timer to avoid frequent refreshes in a short period of time
        lastDrawTime = 0
        lastProcessTime = 0
        // Set a unified initial sampling step after switching
        sampleStride = sampleStrideInitial
        setNeedsDisplay()
    }

    // MARK: - Public Methods

    /// Update histogram data
    /// - Parameter sampleBuffer: camera frame data
    func updateHistogram(from sampleBuffer: CMSampleBuffer) {
        // Calculation throttling: If the distance from the last calculation is less than the threshold, skip this frame directly
        let nowProcess = CACurrentMediaTime()
        if nowProcess - lastProcessTime < minInterval { return }

        let t0 = CACurrentMediaTime()

        // Calculate using ImageStatisticsCalculator
        guard let stats = ImageStatisticsCalculator.analyze(
            from: sampleBuffer,
            stride: sampleStride,
            includeRGB: displayMode == .rgb
        ) else { return }

        // Mark this calculation as done
        lastProcessTime = nowProcess
        lastProcessDuration = CACurrentMediaTime() - t0

        // Adaptively adjust the sampling step size according to the calculation time (control CPU usage)
        if lastProcessDuration > 0.012, sampleStride < sampleStrideMax {
            sampleStride = min(sampleStrideMax, max(sampleStrideMin, sampleStride * 2))
        } else if lastProcessDuration < 0.004, sampleStride > sampleStrideMin {
            sampleStride = max(sampleStrideMin, sampleStride / 2)
        }

        // Update data and trigger redraw (rate limited)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if self.displayMode == .luma {
                let newHistogram = stats.lumaHistogram
                if self.hasData {
                    var blended = self.histogramData
                    let alpha = self.smoothingAlpha
                    let invAlpha = 1.0 - alpha

                    for i in 0 ..< 256 {
                        let n = CGFloat(newHistogram[i])
                        let o = CGFloat(blended[i])
                        let val = alpha * n + invAlpha * o
                        blended[i] = Int(round(val))
                    }
                    self.histogramData = blended
                } else {
                    self.histogramData = newHistogram
                }
                self.hasData = true
            } else {
                // RGB Mode
                if let rgb = stats.rgbHistogram {
                    if self.hasRGBData {
                        var r = self.rgbHistogramData.r
                        var g = self.rgbHistogramData.g
                        var b = self.rgbHistogramData.b
                        let alpha = self.smoothingAlpha
                        let invAlpha = 1.0 - alpha

                        for i in 0 ..< 256 {
                            r[i] = Int(round(alpha * CGFloat(rgb.r[i]) + invAlpha * CGFloat(r[i])))
                            g[i] = Int(round(alpha * CGFloat(rgb.g[i]) + invAlpha * CGFloat(g[i])))
                            b[i] = Int(round(alpha * CGFloat(rgb.b[i]) + invAlpha * CGFloat(b[i])))
                        }
                        self.rgbHistogramData = (r, g, b)
                    } else {
                        self.rgbHistogramData = rgb
                    }
                    self.hasRGBData = true
                }
            }

            let now = CACurrentMediaTime()
            if now - self.lastDrawTime >= self.minInterval {
                self.lastDrawTime = now
                self.setNeedsDisplay()
            }
        }
    }

    /// Clear histogram data
    func clearHistogram() {
        histogramData = Array(repeating: 0, count: 256)
        hasData = false
        rgbHistogramData = (
            Array(repeating: 0, count: 256),
            Array(repeating: 0, count: 256),
            Array(repeating: 0, count: 256)
        )
        hasRGBData = false
        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let roundedRectPath = UIBezierPath(roundedRect: rect, cornerRadius: Style.cornerRadius)
        context.saveGState()
        roundedRectPath.addClip()

        // background
        context.setFillColor(Style.backgroundColor.cgColor)
        context.fill(rect)

        let contentRect = rect.inset(by: UIEdgeInsets(top: Style.verticalPadding,
                                                      left: Style.horizontalPadding,
                                                      bottom: Style.verticalPadding,
                                                      right: Style.horizontalPadding))

        let binWidth = contentRect.width / 255.0

        switch displayMode {
        case .luma:
            guard hasData else { break }
            let maxVal = CGFloat(histogramData.max() ?? 1)
            let heightScale = contentRect.height / max(1, maxVal)

            let path = UIBezierPath()
            if histogramData.count >= 256 {
                let startPoint = CGPoint(x: contentRect.minX, y: contentRect.maxY - CGFloat(histogramData[0]) * heightScale)
                path.move(to: startPoint)
                for i in 1 ..< 256 {
                    let x = contentRect.minX + CGFloat(i) * binWidth
                    let y = contentRect.maxY - CGFloat(histogramData[i]) * heightScale
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            let fillPath = path.copy() as! UIBezierPath
            fillPath.addLine(to: CGPoint(x: contentRect.maxX, y: contentRect.maxY))
            fillPath.addLine(to: CGPoint(x: contentRect.minX, y: contentRect.maxY))
            fillPath.close()

            context.addPath(fillPath.cgPath)
            context.setFillColor(Style.monoFill.cgColor)
            context.fillPath()

            context.addPath(path.cgPath)
            context.setStrokeColor(Style.monoStroke.cgColor)
            context.setLineWidth(1.0)
            context.strokePath()

        case .rgb:
            guard hasRGBData else { break }
            let maxVal = CGFloat(max(rgbHistogramData.r.max() ?? 1,
                                     max(rgbHistogramData.g.max() ?? 1,
                                         rgbHistogramData.b.max() ?? 1)))
            let heightScale = contentRect.height / max(1, maxVal)

            func drawChannel(_ data: [Int], stroke: UIColor, fill: UIColor) {
                let path = UIBezierPath()
                if data.count >= 256 {
                    let startPoint = CGPoint(x: contentRect.minX, y: contentRect.maxY - CGFloat(data[0]) * heightScale)
                    path.move(to: startPoint)
                    for i in 1 ..< 256 {
                        let x = contentRect.minX + CGFloat(i) * binWidth
                        let y = contentRect.maxY - CGFloat(data[i]) * heightScale
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                let fillPath = path.copy() as! UIBezierPath
                fillPath.addLine(to: CGPoint(x: contentRect.maxX, y: contentRect.maxY))
                fillPath.addLine(to: CGPoint(x: contentRect.minX, y: contentRect.maxY))
                fillPath.close()

                context.addPath(fillPath.cgPath)
                context.setFillColor(fill.cgColor)
                context.fillPath()

                context.addPath(path.cgPath)
                context.setStrokeColor(stroke.cgColor)
                context.setLineWidth(1.0)
                context.strokePath()
            }

            drawChannel(rgbHistogramData.r, stroke: Style.redStroke, fill: Style.redFill)
            drawChannel(rgbHistogramData.g, stroke: Style.greenStroke, fill: Style.greenFill)
            drawChannel(rgbHistogramData.b, stroke: Style.blueStroke, fill: Style.blueFill)
        }

        context.restoreGState()
    }
}
