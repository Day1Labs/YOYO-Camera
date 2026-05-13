import AVFoundation
import CoreImage
import SwiftUI
import Vision

// MARK: - supporting types and structs

/// Composition analysis result
struct CompositionAnalysis {
    let faceCount: Int
    let faces: [FaceInfo]
    let hasMainSubject: Bool
    let mainSubjectPosition: CGPoint?
    let mainSubjectSize: Float?
    let mainSubjectType: SubjectType?
    let focusPointSuggestion: CGPoint?
    let backgroundComplexity: BackgroundComplexity
    let ruleOfThirds: RuleOfThirdsAnalysis
    let symmetry: SymmetryAnalysis
    let leadingLines: LeadingLinesAnalysis
    let depthOfField: DepthOfFieldAnalysis
    let visualBalance: VisualBalanceAnalysis

    enum BackgroundComplexity {
        case simple
        case moderate
        case complex
    }

    /// Empty composition analysis result (used when composition analysis is not required)
    static func empty() -> CompositionAnalysis {
        CompositionAnalysis(
            faceCount: 0,
            faces: [],
            hasMainSubject: false,
            mainSubjectPosition: nil,
            mainSubjectSize: nil,
            mainSubjectType: nil,
            focusPointSuggestion: nil,
            backgroundComplexity: .moderate,
            ruleOfThirds: RuleOfThirdsAnalysis.default(),
            symmetry: SymmetryAnalysis.default(),
            leadingLines: LeadingLinesAnalysis.default(),
            depthOfField: DepthOfFieldAnalysis.default(),
            visualBalance: VisualBalanceAnalysis.default()
        )
    }

    /// Get a brief description of the composition analysis
    func getDescription() -> String {
        // utility functions: safe normalization and threshold checks
        let clamp01: (Float) -> Float = { v in
            guard v.isFinite else { return 0 }
            return min(max(v, 0), 1)
        }

        var sentences: [String] = []

        // 1) subject and people
        if hasMainSubject {
            var clause: [String] = []
            var posPhrase: String?
            if let pos = mainSubjectPosition {
                let thirds: [CGPoint] = [
                    CGPoint(x: CGFloat(1) / 3.0, y: CGFloat(1) / 3.0), CGPoint(x: CGFloat(2) / 3.0, y: CGFloat(1) / 3.0),
                    CGPoint(x: CGFloat(1) / 3.0, y: CGFloat(2) / 3.0), CGPoint(x: CGFloat(2) / 3.0, y: CGFloat(2) / 3.0),
                ]
                let dx = pos.x - CGFloat(0.5)
                let dy = pos.y - CGFloat(0.5)
                let r2 = CGFloat(0.12 * 0.12)
                let isCenter = (dx * dx + dy * dy) < r2
                let nearThirds = thirds.contains { p in
                    let tx = p.x - pos.x
                    let ty = p.y - pos.y
                    return (tx * tx + ty * ty) < r2
                }
                if nearThirds { posPhrase = "靠近三分交点" }
                else if isCenter { posPhrase = "居中" }
                else {
                    var dirX: String? = nil
                    var dirY: String? = nil
                    if pos.x > CGFloat(0.6) { dirX = "右" } else if pos.x < CGFloat(0.4) { dirX = "左" }
                    if pos.y > CGFloat(0.6) { dirY = "上" } else if pos.y < CGFloat(0.4) { dirY = "下" }
                    let dir = [dirX, dirY].compactMap { $0 }.joined()
                    if !dir.isEmpty { posPhrase = "偏" + dir }
                }
            }
            var sizePhrase: String?
            if let s = mainSubjectSize {
                let size = clamp01(s)
                sizePhrase = size < 0.18 ? "偏小" : (size < 0.38 ? "大小适中" : "偏大")
            }
            var subjectSentence = "主体"
            if let p = posPhrase { subjectSentence += p }
            if let s = sizePhrase { subjectSentence += (posPhrase == nil ? "" : "，") + s }
            if subjectSentence == "主体" { subjectSentence = "主体清晰" }
            clause.append(subjectSentence)
            if faceCount > 0 { clause.append("含\(faceCount)人") }
            sentences.append(clause.joined(separator: "，") + "。")
        } else {
            let humanPart = faceCount > 0 ? "，含\(faceCount)人" : ""
            sentences.append("主体不明显\(humanPart)。")
        }

        // 2) image features
        var features: [String] = []
        let thirdsScore = clamp01(ruleOfThirds.alignmentScore)
        if thirdsScore > 0.65 { features.append("三分对齐良好") }
        else if thirdsScore < 0.35 { features.append("三分对齐较弱") }

        let sym = clamp01(symmetry.overallSymmetryScore)
        if sym > 0.7 { features.append("对称性强") }
        else if sym < 0.3 { features.append("非对称") }

        if (leadingLines.leadingLineStrength.isFinite && leadingLines.leadingLineStrength > 0.35)
            || !leadingLines.convergingLines.isEmpty
            || !leadingLines.diagonalLines.isEmpty
        {
            features.append("有引导线")
        }

        let depthSep = clamp01(depthOfField.depthSeparation)
        if depthSep > 0.6 { features.append("景深分离度高") }
        else if depthSep < 0.3 { features.append("景深分离度低") }
        else if depthOfField.hasShallowDepth { features.append("浅景深") }

        let bal = clamp01(visualBalance.overallBalance)
        if bal > 0.65 { features.append("画面平衡") }
        else if bal < 0.35 { features.append("画面偏重") }

        switch backgroundComplexity {
        case .simple: features.append("背景简洁")
        case .complex: features.append("背景复杂")
        default: break
        }

        if !features.isEmpty { sentences.append(features.joined(separator: "、") + "。") }

        return sentences.joined()
    }
}

/// Face information
struct FaceInfo {
    let boundingBox: CGRect
    let center: CGPoint
    let size: Float
    let confidence: Float
    let direction: FaceDirection
}

/// Face orientation
enum FaceDirection {
    case front, left, right, up, down
}

/// Subject type (used for automation hints)
enum SubjectType: String, Codable, Hashable {
    case face
    case salient
}

/// Saliency information
struct SaliencyInfo {
    let mostSalientPoint: CGPoint
    let salientRegions: [SalientRegion]
    let overallSaliency: Float

    static func `default`() -> SaliencyInfo {
        SaliencyInfo(
            mostSalientPoint: CGPoint(x: 0.5, y: 0.5),
            salientRegions: [],
            overallSaliency: 0.3
        )
    }
}

/// Salient region
struct SalientRegion {
    let boundingBox: CGRect
    let confidence: Float
}

/// Rule-of-thirds analysis
struct RuleOfThirdsAnalysis {
    let intersectionPoints: [CGPoint]
    let alignmentScore: Float
    let interestPoints: [CGPoint]

    static func `default`() -> RuleOfThirdsAnalysis {
        RuleOfThirdsAnalysis(
            intersectionPoints: [],
            alignmentScore: 0.3,
            interestPoints: []
        )
    }
}

/// Symmetry analysis
struct SymmetryAnalysis {
    let verticalSymmetryScore: Float
    let horizontalSymmetryScore: Float
    let radialSymmetryScore: Float
    let overallSymmetryScore: Float

    static func `default`() -> SymmetryAnalysis {
        SymmetryAnalysis(
            verticalSymmetryScore: 0.3,
            horizontalSymmetryScore: 0.3,
            radialSymmetryScore: 0.3,
            overallSymmetryScore: 0.3
        )
    }
}

/// Leading line analysis
struct LeadingLinesAnalysis {
    let detectedLines: [DetectedLine]
    let convergingLines: [DetectedLine]
    let diagonalLines: [DetectedLine]
    let leadingLineStrength: Float

    static func `default`() -> LeadingLinesAnalysis {
        LeadingLinesAnalysis(
            detectedLines: [],
            convergingLines: [],
            diagonalLines: [],
            leadingLineStrength: 0.2
        )
    }
}

/// Detected lines
struct DetectedLine: Hashable {
    let start: CGPoint
    let end: CGPoint
    let strength: Float
}

/// Depth-of-field analysis
struct DepthOfFieldAnalysis {
    let hasShallowDepth: Bool
    let focusRegions: [FocusRegion]
    let averageBlurLevel: Float
    let depthSeparation: Float

    static func `default`() -> DepthOfFieldAnalysis {
        DepthOfFieldAnalysis(
            hasShallowDepth: false,
            focusRegions: [],
            averageBlurLevel: 0.3,
            depthSeparation: 0.4
        )
    }
}

/// Focus region
struct FocusRegion {
    let center: CGPoint
    let size: Float
    let sharpness: Float
}

/// Visual balance analysis
struct VisualBalanceAnalysis {
    let quadrantWeights: [Float]
    let horizontalBalance: Float
    let verticalBalance: Float
    let overallBalance: Float

    static func `default`() -> VisualBalanceAnalysis {
        VisualBalanceAnalysis(
            quadrantWeights: [0.25, 0.25, 0.25, 0.25],
            horizontalBalance: 0.5,
            verticalBalance: 0.5,
            overallBalance: 0.5
        )
    }
}

/// Composition analyzer - professional photography composition analysis
enum CompositionAnalyzer {
    // MARK: - state (used for temporal stability)

    private struct State {
        var lastSubjectPosition: CGPoint?
        var lastSubjectSize: Float?
        var stableFrameCount: Int = 0
    }

    private static var state = State()

    // MARK: - main analysis methods

    /// Full composition analysis
    static func analyzeComposition(from sampleBuffer: CMSampleBuffer) async -> CompositionAnalysis {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let orientation = getImageOrientation(from: sampleBuffer)

        // run multiple analyses concurrently
        async let faceAnalysis = detectFaces(from: sampleBuffer, orientation: orientation)
        async let saliencyAnalysis = detectSaliency(from: sampleBuffer, orientation: orientation)
        async let symmetryAnalysis = analyzeSymmetry(ciImage: ciImage)
        async let leadingLinesAnalysis = detectLeadingLines(ciImage: ciImage)
        async let depthAnalysis = analyzeDepthOfField(ciImage: ciImage)
        async let balanceAnalysis = analyzeVisualBalance(ciImage: ciImage)

        let faces = await faceAnalysis
        let saliency = await saliencyAnalysis
        // Rule-of-thirds analysis depends on saliency points, so run it after saliency analysis
        let ruleOfThirds = await analyzeRuleOfThirds(ciImage: ciImage, saliency: saliency)
        let symmetry = await symmetryAnalysis
        let leadingLines = await leadingLinesAnalysis
        let depth = await depthAnalysis
        let balance = await balanceAnalysis

        // combined analysis result
        var mainSubject = determineMainSubject(faces: faces, saliency: saliency)
        // apply temporal smoothing, reduce jitter
        mainSubject = applyTemporalSmoothing(to: mainSubject)
        let backgroundComplexity = calculateBackgroundComplexity(ciImage: ciImage)

        return CompositionAnalysis(
            faceCount: faces.count,
            faces: faces,
            hasMainSubject: mainSubject.hasSubject,
            mainSubjectPosition: mainSubject.position,
            mainSubjectSize: mainSubject.size,
            mainSubjectType: mainSubject.type,
            focusPointSuggestion: mainSubject.position,
            backgroundComplexity: backgroundComplexity,
            ruleOfThirds: ruleOfThirds,
            symmetry: symmetry,
            leadingLines: leadingLines,
            depthOfField: depth,
            visualBalance: balance
        )
    }

    // MARK: - face detection

    private static func detectFaces(from sampleBuffer: CMSampleBuffer) async -> [FaceInfo] {
        await detectFaces(from: sampleBuffer, orientation: getImageOrientation(from: sampleBuffer))
    }

    private static func detectFaces(from sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) async -> [FaceInfo] {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { request, _ in
                guard let results = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let faces = results.compactMap { face -> FaceInfo? in
                    let bbox = face.boundingBox
                    let center = CGPoint(x: bbox.midX, y: bbox.midY)
                    let size = max(bbox.width, bbox.height)

                    // Analyze face orientation
                    var faceDirection: FaceDirection = .front
                    if let landmarks = face.landmarks {
                        faceDirection = analyzeFaceDirection(landmarks: landmarks)
                    }

                    return FaceInfo(
                        boundingBox: bbox,
                        center: center,
                        size: Float(size),
                        confidence: face.confidence,
                        direction: faceDirection
                    )
                }

                continuation.resume(returning: faces)
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: orientation, options: [:])
            try? handler.perform([request])
        }
    }

    /// Analyze face orientation
    private static func analyzeFaceDirection(landmarks: VNFaceLandmarks2D) -> FaceDirection {
        // Simplified implementation: infer orientation from the nose and face contour
        if let nose = landmarks.nose?.pointsInImage(imageSize: CGSize(width: 1, height: 1)).first,
           let faceContour = landmarks.faceContour?.pointsInImage(imageSize: CGSize(width: 1, height: 1))
        {
            let faceCenter = faceContour.reduce(CGPoint.zero) { result, point in
                CGPoint(x: result.x + point.x, y: result.y + point.y)
            }
            let avgCenter = CGPoint(x: faceCenter.x / CGFloat(faceContour.count),
                                    y: faceCenter.y / CGFloat(faceContour.count))

            let horizontalOffset = nose.x - avgCenter.x

            if abs(horizontalOffset) < 0.05 {
                return .front
            } else if horizontalOffset > 0 {
                return .right
            } else {
                return .left
            }
        }

        return .front
    }

    // MARK: - saliency detection

    private static func detectSaliency(from sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) async -> SaliencyInfo {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return SaliencyInfo.default()
        }

        if #available(iOS 13.0, *) {
            return await withCheckedContinuation { continuation in
                let request = VNGenerateAttentionBasedSaliencyImageRequest { request, _ in
                    guard let result = request.results?.first as? VNSaliencyImageObservation else {
                        continuation.resume(returning: SaliencyInfo.default())
                        return
                    }

                    var salientRegions: [SalientRegion] = []
                    if let objects = result.salientObjects {
                        salientRegions = objects.map { obj in
                            SalientRegion(
                                boundingBox: obj.boundingBox,
                                confidence: obj.confidence
                            )
                        }
                    }

                    // find the most salient region
                    let mostSalient = salientRegions.max { $0.confidence < $1.confidence }
                    let focusPoint = mostSalient?.boundingBox.center ?? CGPoint(x: 0.5, y: 0.5)

                    continuation.resume(returning: SaliencyInfo(
                        mostSalientPoint: focusPoint,
                        salientRegions: salientRegions,
                        overallSaliency: salientRegions.map(\.confidence).reduce(0, +) / Float(max(1, salientRegions.count))
                    ))
                }

                let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: orientation, options: [:])
                try? handler.perform([request])
            }
        } else {
            return SaliencyInfo.default()
        }
    }

    // MARK: - Rule-of-thirds analysis

    private static func analyzeRuleOfThirds(ciImage: CIImage, saliency: SaliencyInfo) async -> RuleOfThirdsAnalysis {
        let extent = ciImage.extent
        let width = extent.width
        let height = extent.height

        // calculate rule-of-thirds line positions
        let verticalLines = [width / 3, width * 2 / 3]
        let horizontalLines = [height / 3, height * 2 / 3]

        // calculate the four intersections
        var intersectionPoints: [CGPoint] = []
        for vLine in verticalLines {
            for hLine in horizontalLines {
                intersectionPoints.append(CGPoint(x: vLine, y: hLine))
            }
        }

        // analyze the distribution of image interest points: use salient-region center points(normalized coordinates->pixel coordinates)
        let interestPoints: [CGPoint] = saliency.salientRegions.map { region in
            let cx = region.boundingBox.midX * width
            let cy = region.boundingBox.midY * height
            return CGPoint(x: cx, y: cy)
        }

        // calculate the distance between interest points and rule-of-thirds intersections
        var alignmentScore: Float = 0
        let threshold: CGFloat = min(width, height) * 0.1 // 10% tolerance

        for interestPoint in interestPoints {
            let minDistance = intersectionPoints.map { point in
                sqrt(pow(point.x - interestPoint.x, 2) + pow(point.y - interestPoint.y, 2))
            }.min() ?? CGFloat.greatestFiniteMagnitude

            if minDistance < threshold {
                alignmentScore += 1.0 - Float(minDistance / threshold)
            }
        }

        // normalized score
        if interestPoints.isEmpty {
            alignmentScore = 0
        } else {
            let normalized = alignmentScore / Float(interestPoints.count)
            alignmentScore = min(max(normalized, 0.0), 1.0)
        }

        return RuleOfThirdsAnalysis(
            intersectionPoints: intersectionPoints,
            alignmentScore: alignmentScore,
            interestPoints: interestPoints
        )
    }

    // No longer use unstable CIDetector corner/rectangle detection as interest points

    // MARK: - Symmetry analysis

    private static func analyzeSymmetry(ciImage: CIImage) async -> SymmetryAnalysis {
        let extent = ciImage.extent
        let centerX = extent.width / 2
        let centerY = extent.height / 2

        // vertical symmetry analysis
        let verticalSymmetry = await calculateVerticalSymmetry(ciImage: ciImage, centerX: centerX)

        // horizontal symmetry analysis
        let horizontalSymmetry = await calculateHorizontalSymmetry(ciImage: ciImage, centerY: centerY)

        // radial symmetry analysis
        let radialSymmetry = await calculateRadialSymmetry(ciImage: ciImage)

        return SymmetryAnalysis(
            verticalSymmetryScore: verticalSymmetry,
            horizontalSymmetryScore: horizontalSymmetry,
            radialSymmetryScore: radialSymmetry,
            overallSymmetryScore: (verticalSymmetry + horizontalSymmetry + radialSymmetry) / 3
        )
    }

    /// Calculate vertical symmetry
    private static func calculateVerticalSymmetry(ciImage: CIImage, centerX: CGFloat) async -> Float {
        let extent = ciImage.extent
        let leftHalf = ciImage.cropped(to: CGRect(x: extent.minX, y: extent.minY, width: centerX, height: extent.height))

        // create a mirrored copy of the right half
        let rightHalf = ciImage.cropped(to: CGRect(x: centerX, y: extent.minY, width: centerX, height: extent.height))

        // flip the right half horizontally
        let transform = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -centerX, y: 0)
        let flippedRightHalf = rightHalf.transformed(by: transform)

        // compare the similarity of the two halves
        return await compareImageSimilarity(leftHalf, flippedRightHalf)
    }

    /// Calculate horizontal symmetry
    private static func calculateHorizontalSymmetry(ciImage: CIImage, centerY: CGFloat) async -> Float {
        let extent = ciImage.extent
        let topHalf = ciImage.cropped(to: CGRect(x: extent.minX, y: centerY, width: extent.width, height: centerY))

        let bottomHalf = ciImage.cropped(to: CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: centerY))

        // flip the bottom vertically
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -centerY)
        let flippedBottomHalf = bottomHalf.transformed(by: transform)

        return await compareImageSimilarity(topHalf, flippedBottomHalf)
    }

    /// Calculate radial symmetry
    private static func calculateRadialSymmetry(ciImage: CIImage) async -> Float {
        // Simplified implementation: inspect feature distribution near the image center
        let extent = ciImage.extent
        let center = CGPoint(x: extent.width / 2, y: extent.height / 2)
        let radius = min(extent.width, extent.height) / 4

        // sample within a circular region to check symmetry
        let sampleCount = 8
        var symmetryScore: Float = 0

        for i in 0 ..< sampleCount {
            let angle1 = Float(i) * Float.pi * 2 / Float(sampleCount)
            let angle2 = angle1 + Float.pi // opposite angle

            let point1 = CGPoint(
                x: center.x + CGFloat(cos(angle1)) * radius,
                y: center.y + CGFloat(sin(angle1)) * radius
            )

            let point2 = CGPoint(
                x: center.x + CGFloat(cos(angle2)) * radius,
                y: center.y + CGFloat(sin(angle2)) * radius
            )

            // compare the pixel-value similarity of two points(simplified calculation)
            symmetryScore += 0.5 // Simplified to a constant value; in practice pixel values should be compared
        }

        return symmetryScore / Float(sampleCount)
    }

    /// Compare the similarity of two images
    private static func compareImageSimilarity(_ image1: CIImage, _ image2: CIImage) async -> Float {
        // Simplified implementation: compare average brightness differences
        let b1 = BrightnessCalculator.calculateAverageBrightness(ciImage: image1)
        let b2 = BrightnessCalculator.calculateAverageBrightness(ciImage: image2)
        let safe: (Float) -> Float = { v in v.isFinite ? min(max(v, 0.0), 1.0) : 0.0 }
        let difference = abs(safe(b1) - safe(b2))
        let similarity = 1.0 - difference
        return min(max(similarity, 0.0), 1.0) // The smaller the difference, the higher the similarity
    }

    // MARK: - leading line detection

    private static func detectLeadingLines(ciImage: CIImage) async -> LeadingLinesAnalysis {
        // use edge detection to estimate leading-line strength(stable implementation)
        guard let edgeFilter = CIFilter(name: "CIEdges") else {
            return LeadingLinesAnalysis.default()
        }
        edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgeFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        guard let edgeImage = edgeFilter.outputImage else {
            return LeadingLinesAnalysis.default()
        }
        // approximate leading-line strength with edge intensity(0-1)
        let edgeStrength = BrightnessCalculator.calculateContrast(ciImage: edgeImage)
        return LeadingLinesAnalysis(
            detectedLines: [],
            convergingLines: [],
            diagonalLines: [],
            leadingLineStrength: min(max(edgeStrength, 0.0), 1.0)
        )
    }

    // MARK: - Depth-of-field analysis

    private static func analyzeDepthOfField(ciImage: CIImage) async -> DepthOfFieldAnalysis {
        // analyze the sharpness distribution to infer depth of field
        let blurMap = await generateBlurMap(ciImage: ciImage)
        let focusRegions = identifyFocusRegions(blurMap: blurMap)

        return DepthOfFieldAnalysis(
            hasShallowDepth: focusRegions.count < 3,
            focusRegions: focusRegions,
            averageBlurLevel: calculateAverageBlur(blurMap: blurMap),
            depthSeparation: calculateDepthSeparation(blurMap: blurMap)
        )
    }

    /// Generate a blur map
    private static func generateBlurMap(ciImage: CIImage) async -> [[Float]] {
        // grid-based blur map based on edge intensity: strong edges -> sharp, weak edges -> blurred
        let extent = ciImage.extent
        let gridX = max(8, Int(extent.width / 80))
        let gridY = max(8, Int(extent.height / 80))
        guard let edgeFilter = CIFilter(name: "CIEdges") else {
            return Array(repeating: Array(repeating: 0.5, count: gridX), count: gridY)
        }
        edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgeFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        guard let edgeImage = edgeFilter.outputImage else {
            return Array(repeating: Array(repeating: 0.5, count: gridX), count: gridY)
        }
        var blurMap = Array(repeating: Array(repeating: Float(0.5), count: gridX), count: gridY)
        let cellW = extent.width / CGFloat(gridX)
        let cellH = extent.height / CGFloat(gridY)
        for gy in 0 ..< gridY {
            for gx in 0 ..< gridX {
                let rect = CGRect(x: extent.minX + CGFloat(gx) * cellW,
                                  y: extent.minY + CGFloat(gy) * cellH,
                                  width: cellW,
                                  height: cellH)
                let cellImage = edgeImage.cropped(to: rect)
                let edgeContrast = BrightnessCalculator.calculateContrast(ciImage: cellImage)
                // blur amount = 1 - edge contrast(normalized)
                let blur = 1.0 - min(max(edgeContrast, 0.0), 1.0)
                blurMap[gy][gx] = blur
            }
        }
        return blurMap
    }

    /// Identify focus regions
    private static func identifyFocusRegions(blurMap _: [[Float]]) -> [FocusRegion] {
        // simplified implementation
        [FocusRegion(center: CGPoint(x: 0.5, y: 0.5), size: 0.3, sharpness: 0.8)]
    }

    /// Calculate average blur
    private static func calculateAverageBlur(blurMap: [[Float]]) -> Float {
        guard !blurMap.isEmpty, !blurMap[0].isEmpty else { return 0.5 }
        let totalBlur = blurMap.flatMap { $0 }.reduce(0, +)
        let pixelCount = blurMap.count * blurMap[0].count
        guard pixelCount > 0 else { return 0.5 }
        let avg = totalBlur / Float(pixelCount)
        return min(max(avg.isFinite ? avg : 0.5, 0.0), 1.0)
    }

    /// Calculate depth-of-field separation
    private static func calculateDepthSeparation(blurMap: [[Float]]) -> Float {
        let values = blurMap.flatMap { $0 }
        guard !values.isEmpty else { return 0.0 }
        let sortedValues = values.sorted()
        guard sortedValues.count >= 4 else { return 0.0 }
        let q1 = sortedValues[sortedValues.count / 4]
        let q3 = sortedValues[sortedValues.count * 3 / 4]
        let iqr = q3 - q1 // use interquartile range as the separation metric
        let sep = min(max(iqr, 0.0), 1.0)
        return sep.isFinite ? sep : 0.0
    }

    // MARK: - Visual balance analysis

    private static func analyzeVisualBalance(ciImage: CIImage) async -> VisualBalanceAnalysis {
        let extent = ciImage.extent
        let regions = divideImageIntoQuadrants(extent: extent)

        // calculate the visual weight of each quadrant
        var quadrantWeights: [Float] = []
        for region in regions {
            let regionImage = ciImage.cropped(to: region)
            let weight = await calculateVisualWeight(ciImage: regionImage)
            quadrantWeights.append(min(max(weight.isFinite ? weight : 0.0, 0.0), 1.0))
        }

        // analyze balance
        let horizontalBalance = abs(quadrantWeights[0] + quadrantWeights[2] - quadrantWeights[1] - quadrantWeights[3])
        let verticalBalance = abs(quadrantWeights[0] + quadrantWeights[1] - quadrantWeights[2] - quadrantWeights[3])

        return VisualBalanceAnalysis(
            quadrantWeights: quadrantWeights,
            horizontalBalance: 1.0 - horizontalBalance / 2.0, // normalize to 0-1
            verticalBalance: 1.0 - verticalBalance / 2.0,
            overallBalance: (1.0 - horizontalBalance / 2.0 + 1.0 - verticalBalance / 2.0) / 2.0
        )
    }

    /// Divide the image into four quadrants
    private static func divideImageIntoQuadrants(extent: CGRect) -> [CGRect] {
        let midX = extent.midX
        let midY = extent.midY

        return [
            CGRect(x: extent.minX, y: midY, width: midX - extent.minX, height: extent.maxY - midY), // top-left
            CGRect(x: midX, y: midY, width: extent.maxX - midX, height: extent.maxY - midY), // top-right
            CGRect(x: extent.minX, y: extent.minY, width: midX - extent.minX, height: midY - extent.minY), // bottom-left
            CGRect(x: midX, y: extent.minY, width: extent.maxX - midX, height: midY - extent.minY), // bottom-right
        ]
    }

    /// Calculate the visual weight of a region
    private static func calculateVisualWeight(ciImage: CIImage) async -> Float {
        // visual weight = brightness + contrast + color saturation
        let brightness = BrightnessCalculator.calculateAverageBrightness(ciImage: ciImage)
        let contrast = BrightnessCalculator.calculateContrast(ciImage: ciImage)
        let saturation = await calculateRegionSaturation(ciImage: ciImage)
        let safe: (Float) -> Float = { v in v.isFinite ? min(max(v, 0.0), 1.0) : 0.0 }
        let weight = (safe(brightness) + safe(contrast) + safe(saturation)) / 3.0
        return safe(weight)
    }

    /// Calculate region saturation
    private static func calculateRegionSaturation(ciImage _: CIImage) async -> Float {
        // simplified implementation
        0.5
    }

    // MARK: - Helper methods

    /// Determine the primary subject
    private static func determineMainSubject(faces: [FaceInfo], saliency: SaliencyInfo) -> (hasSubject: Bool, position: CGPoint?, size: Float?, type: SubjectType?) {
        // prioritize faces
        if let largestFace = faces.max(by: { $0.size < $1.size }) {
            return (true, largestFace.center, largestFace.size, .face)
        }

        // then consider salient regions
        if let mostSalient = saliency.salientRegions.max(by: { $0.confidence < $1.confidence }) {
            let size = max(mostSalient.boundingBox.width, mostSalient.boundingBox.height)
            return (true, mostSalient.boundingBox.center, Float(size), .salient)
        }

        return (false, nil, nil, nil)
    }

    /// Apply temporal smoothing (exponential smoothing) to reduce subject position/size jitter
    private static func applyTemporalSmoothing(to subject: (hasSubject: Bool, position: CGPoint?, size: Float?, type: SubjectType?)) -> (hasSubject: Bool, position: CGPoint?, size: Float?, type: SubjectType?) {
        // if there is no subject, gradually clear the state
        guard subject.hasSubject, let pos = subject.position, let size = subject.size else {
            // decrease the stability count
            state.stableFrameCount = max(0, state.stableFrameCount - 1)
            if state.stableFrameCount <= 0 {
                state.lastSubjectPosition = nil
                state.lastSubjectSize = nil
            }
            return subject
        }
        // smoothing factor(closer to 1 means relying more on the current frame)
        let alphaPos: CGFloat = 0.7
        let alphaSize: Float = 0.7
        let blendedPos: CGPoint
        let blendedSize: Float
        if let lastPos = state.lastSubjectPosition {
            blendedPos = CGPoint(x: alphaPos * pos.x + (1 - alphaPos) * lastPos.x,
                                 y: alphaPos * pos.y + (1 - alphaPos) * lastPos.y)
        } else {
            blendedPos = pos
        }
        if let lastSize = state.lastSubjectSize {
            blendedSize = alphaSize * size + (1 - alphaSize) * lastSize
        } else {
            blendedSize = size
        }
        // update state
        state.lastSubjectPosition = blendedPos
        state.lastSubjectSize = blendedSize
        state.stableFrameCount += 1
        return (true, blendedPos, blendedSize, subject.type)
    }

    /// Calculate background complexity
    private static func calculateBackgroundComplexity(ciImage: CIImage) -> CompositionAnalysis.BackgroundComplexity {
        // use available edge filters to estimate complexity
        guard let edgeFilter = CIFilter(name: "CIEdges") else {
            return .moderate
        }
        edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgeFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        guard let edgeImage = edgeFilter.outputImage else {
            return .moderate
        }
        let edgeIntensity = BrightnessCalculator.calculateAverageBrightness(ciImage: edgeImage)

        if edgeIntensity < 0.2 {
            return .simple
        } else if edgeIntensity > 0.6 {
            return .complex
        } else {
            return .moderate
        }
    }
}

// MARK: - extension methods

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

// MARK: - Image orientation helpers

private extension CompositionAnalyzer {
    static func getImageOrientation(from sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        // Get EXIF orientation from attachments, defaulting to.up when unavailable
        if let attachments = CMCopyDictionaryOfAttachments(allocator: kCFAllocatorDefault,
                                                           target: sampleBuffer,
                                                           attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [String: Any],
            let exifOrientation = attachments[kCGImagePropertyOrientation as String] as? UInt32,
            let ori = CGImagePropertyOrientation(rawValue: exifOrientation)
        {
            return ori
        }
        return .up
    }
}
