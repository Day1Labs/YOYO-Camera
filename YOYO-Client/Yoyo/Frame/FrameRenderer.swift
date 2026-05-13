import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Simplified photo frame renderer.
final class FrameRenderer: ObservableObject {
    private let context = CIContext()

    // MARK: - Public Methods

    /// Render photo frame effects onto an image.
    func renderFrame(to image: UIImage, with template: FrameTemplate, infoOptions: FrameInfoOptions = .none, metadata: [String: Any]? = nil) -> UIImage? {
        let isTwoLine = calculateIsTwoLine(imageSize: image.size, infoOptions: infoOptions, metadata: metadata)
        let config = template.config

        switch config.type {
        case .none:
            return infoOptions.hasAnyInfo ? renderWithInfo(image: image, in: image.size, infoOptions: infoOptions, metadata: metadata, isTwoLine: isTwoLine) : image
        case .polaroid:
            return renderPolaroidFrame(to: image, with: config, infoOptions: infoOptions, metadata: metadata, isTwoLine: isTwoLine)
        case .blurred:
            return renderBlurredFrame(to: image, with: config, infoOptions: infoOptions, metadata: metadata, isTwoLine: isTwoLine)
        case .bottomOnly:
            return renderBottomOnlyFrame(to: image, with: config, infoOptions: infoOptions, metadata: metadata, isTwoLine: isTwoLine)
        }
    }

    // MARK: - Render Implementations

    private func renderWithInfo(image: UIImage, in canvasSize: CGSize, backgroundColor: Color = .clear, imageRect: CGRect? = nil, textColor: UIColor = .white, infoOptions: FrameInfoOptions, metadata: [String: Any]? = nil, isTwoLine: Bool) -> UIImage? {
        createRenderer(size: canvasSize, scale: image.scale).image { context in
            let cgContext = context.cgContext

            // Draw Background
            if backgroundColor != .clear {
                cgContext.setFillColor(UIColor(backgroundColor).cgColor)
                cgContext.fill(CGRect(origin: .zero, size: canvasSize))
            }

            // Draw Image
            let drawRect = imageRect ?? CGRect(origin: .zero, size: canvasSize)
            image.draw(in: drawRect)

            // Draw Info
            let infoRect = calculateEXIFRect(canvasSize: canvasSize, imageRect: drawRect, isTwoLine: isTwoLine)
            drawInfoText(in: infoRect, context: cgContext, image: image, photoRect: drawRect, textColor: textColor, infoOptions: infoOptions, metadata: metadata, isTwoLine: isTwoLine)
        }
    }

    private func renderPolaroidFrame(to image: UIImage, with config: FrameConfig, infoOptions: FrameInfoOptions, metadata: [String: Any]?, isTwoLine: Bool) -> UIImage? {
        let frameInfo = calculateFrameSize(imageSize: image.size, config: config, isTwoLine: isTwoLine)

        if infoOptions.hasAnyInfo {
            return renderWithInfo(image: image, in: frameInfo.canvasSize, backgroundColor: config.backgroundColor, imageRect: frameInfo.imageRect, textColor: .black, infoOptions: infoOptions, metadata: metadata, isTwoLine: isTwoLine)
        }

        return createRenderer(size: frameInfo.canvasSize, scale: image.scale).image { context in
            context.cgContext.setFillColor(UIColor(config.backgroundColor).cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: frameInfo.canvasSize))

            let cornerRadius = image.size.width * config.cornerRadius
            if cornerRadius > 0 {
                let path = UIBezierPath(roundedRect: frameInfo.imageRect, cornerRadius: cornerRadius)
                context.cgContext.addPath(path.cgPath)
                context.cgContext.clip()
            }
            image.draw(in: frameInfo.imageRect)
        }
    }

    private func renderBottomOnlyFrame(to image: UIImage, with config: FrameConfig, infoOptions: FrameInfoOptions, metadata: [String: Any]?, isTwoLine: Bool) -> UIImage? {
        let frameInfo = calculateFrameSize(imageSize: image.size, config: config, isTwoLine: isTwoLine)

        return createRenderer(size: frameInfo.canvasSize, scale: image.scale).image { context in
            context.cgContext.setFillColor(UIColor(config.backgroundColor).cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: frameInfo.canvasSize))
            image.draw(in: frameInfo.imageRect)

            if infoOptions.hasAnyInfo {
                let infoRect = CGRect(x: 0, y: frameInfo.imageRect.maxY, width: frameInfo.canvasSize.width, height: frameInfo.borderWidth)
                drawInfoText(in: infoRect, context: context.cgContext, image: image, photoRect: frameInfo.imageRect, textColor: .black, infoOptions: infoOptions, metadata: metadata, isTwoLine: isTwoLine)
            }
        }
    }

    private func renderBlurredFrame(to image: UIImage, with config: FrameConfig, infoOptions: FrameInfoOptions, metadata: [String: Any]?, isTwoLine: Bool) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return image }
        let frameInfo = calculateFrameSize(imageSize: image.size, config: config, isTwoLine: isTwoLine)

        // Background
        guard let blurredBackground = createBlurredBackground(from: ciImage, canvasSize: frameInfo.canvasSize) else { return image }

        // Composite
        let translationY = frameInfo.canvasSize.height - frameInfo.imageRect.maxY
        let transformedImage = ciImage.transformed(by: CGAffineTransform(translationX: frameInfo.imageRect.origin.x, y: translationY))
        let maskedImage = applyCornerMask(to: transformedImage, config: config, imageRect: frameInfo.imageRect, canvasSize: frameInfo.canvasSize, originalImage: image)

        let compositeFilter = CIFilter.sourceOverCompositing()
        compositeFilter.inputImage = maskedImage
        compositeFilter.backgroundImage = blurredBackground

        guard let finalImage = compositeFilter.outputImage,
              let cgImage = context.createCGImage(finalImage, from: CGRect(origin: .zero, size: frameInfo.canvasSize)) else { return image }

        let resultImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)

        if infoOptions.hasAnyInfo {
            // Re-render to add text
            return createRenderer(size: frameInfo.canvasSize, scale: image.scale).image { ctx in
                resultImage.draw(in: CGRect(origin: .zero, size: frameInfo.canvasSize))
                let infoRect = CGRect(x: 0, y: frameInfo.imageRect.maxY, width: frameInfo.canvasSize.width, height: frameInfo.canvasSize.height - frameInfo.imageRect.maxY)
                drawInfoText(in: infoRect, context: ctx.cgContext, image: image, photoRect: frameInfo.imageRect, textColor: .white, infoOptions: infoOptions, metadata: metadata, isTwoLine: isTwoLine)
            }
        }
        return resultImage
    }

    // MARK: - Helpers

    private func createRenderer(size: CGSize, scale: CGFloat) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private func calculateFrameSize(imageSize: CGSize, config: FrameConfig, isTwoLine: Bool) -> (canvasSize: CGSize, borderWidth: CGFloat, imageRect: CGRect) {
        let baseBorderWidth = imageSize.width * config.borderWidth

        switch config.type {
        case .polaroid, .blurred:
            let bottomMultiplier: CGFloat = 3.5
            let bottomBorder = baseBorderWidth * bottomMultiplier
            let canvasSize = CGSize(width: ceil(imageSize.width + baseBorderWidth * 2), height: ceil(imageSize.height + baseBorderWidth + bottomBorder))
            let imageRect = CGRect(x: baseBorderWidth, y: baseBorderWidth, width: imageSize.width, height: imageSize.height)
            return (canvasSize, baseBorderWidth, imageRect)

        case .bottomOnly:
            let bottomHeight = baseBorderWidth * (isTwoLine ? 1.1 : 1.0)
            let canvasSize = CGSize(width: ceil(imageSize.width), height: ceil(imageSize.height + bottomHeight))
            let imageRect = CGRect(origin: .zero, size: imageSize)
            return (canvasSize, bottomHeight, imageRect)

        case .none:
            let finalBorderWidth = isTwoLine ? baseBorderWidth * 1.2 : baseBorderWidth
            let canvasSize = CGSize(width: ceil(imageSize.width + finalBorderWidth * 2), height: ceil(imageSize.height + finalBorderWidth * 2))
            let imageRect = CGRect(x: finalBorderWidth, y: finalBorderWidth, width: imageSize.width, height: imageSize.height)
            return (canvasSize, finalBorderWidth, imageRect)
        }
    }

    private func calculateIsTwoLine(imageSize: CGSize, infoOptions: FrameInfoOptions, metadata: [String: Any]?) -> Bool {
        guard infoOptions.hasAnyInfo else { return false }
        let scaleFactor = imageSize.width / 1000.0
        let titleFontSize = max(28, 34 * scaleFactor)

        let helper = MetadataHelper(metadata: metadata)
        var components: [String] = []
        if infoOptions.showDeviceModel { components.append(CameraSpecs.getCurrentDeviceSpec().deviceName) }
        if infoOptions.showEXIF { components.append(helper.exifText) }
        if infoOptions.showDate { components.append(helper.dateText) }
        if infoOptions.showTime { components.append(helper.timeText) }
        if infoOptions.showLocation { components.append(helper.locationText) }
        if infoOptions.showCopyright, !infoOptions.copyrightText.isEmpty { components.append("© " + infoOptions.copyrightText) }

        let fullText = components.filter { !$0.isEmpty }.joined(separator: " | ")
        let font = UIFont(name: "AvenirNext-Medium", size: titleFontSize) ?? UIFont.systemFont(ofSize: titleFontSize, weight: .medium)

        var totalWidth = (fullText as NSString).size(withAttributes: [.font: font]).width
        if infoOptions.showAppleIcon { totalWidth += titleFontSize * 1.2 }

        return totalWidth > imageSize.width * 0.82
    }

    private func calculateEXIFRect(canvasSize: CGSize, imageRect: CGRect, isTwoLine: Bool) -> CGRect {
        if imageRect.origin == .zero { // No border
            let scaleFactor = canvasSize.width / 800.0
            let margin = max(22, 44.0 * scaleFactor)
            let heightMultiplier: CGFloat = isTwoLine ? 1.7 : 1.0
            let height = max(50 * heightMultiplier, 70.0 * scaleFactor * heightMultiplier)

            let aspectRatio = canvasSize.width / canvasSize.height
            let bottomOffset = max(40, aspectRatio > 1.2 ? canvasSize.height * 0.06 : canvasSize.width * (aspectRatio < 0.8 ? 0.08 : 0.07))

            return CGRect(x: margin, y: canvasSize.height - bottomOffset - height, width: canvasSize.width - (margin * 2), height: height)
        } else {
            let scaleFactor = imageRect.width / 800.0
            let topPadding = max(4, 8.0 * scaleFactor)
            return CGRect(x: imageRect.minX, y: imageRect.maxY + topPadding, width: imageRect.width, height: canvasSize.height - imageRect.maxY - topPadding - max(8, 16.0 * scaleFactor))
        }
    }

    // MARK: - Blur Helpers

    private func createBlurredBackground(from ciImage: CIImage, canvasSize: CGSize) -> CIImage? {
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = ciImage.clampedToExtent()
        blurFilter.radius = 50
        guard let blurred = blurFilter.outputImage else { return nil }

        let scale = max(canvasSize.width / ciImage.extent.width, canvasSize.height / ciImage.extent.height)
        return blurred.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: CGRect(origin: .zero, size: canvasSize))
    }

    private func applyCornerMask(to image: CIImage, config: FrameConfig, imageRect: CGRect, canvasSize: CGSize, originalImage: UIImage) -> CIImage {
        guard config.cornerRadius > 0 else { return image }
        let cornerRadius = originalImage.size.width * config.cornerRadius

        let maskImage = createRenderer(size: canvasSize, scale: originalImage.scale).image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))
            UIColor.white.setFill()
            UIBezierPath(roundedRect: imageRect, cornerRadius: cornerRadius).fill()
        }

        guard let maskCI = CIImage(image: maskImage) else { return image }
        let maskFilter = CIFilter.sourceInCompositing()
        maskFilter.inputImage = image
        maskFilter.backgroundImage = maskCI
        return maskFilter.outputImage ?? image
    }

    // MARK: - Text Drawing

    private func drawInfoText(in rect: CGRect, context _: CGContext, image: UIImage, photoRect _: CGRect, textColor: UIColor, infoOptions: FrameInfoOptions, metadata: [String: Any]?, isTwoLine: Bool) {
        let scaleFactor = image.size.width / 1000.0
        let sizes = (
            title: max(28, 34 * scaleFactor),
            detail: max(22, 28 * scaleFactor),
            icon: max(26, 32 * scaleFactor)
        )

        let helper = MetadataHelper(metadata: metadata)
        let deviceName = CameraSpecs.getCurrentDeviceSpec().deviceName

        // Brand String (Apple Logo + Device Name)
        let brandString = NSMutableAttributedString()
        if infoOptions.showAppleIcon, let icon = createAppleIconAttachment(size: sizes.icon, titleSize: sizes.title, color: textColor) {
            brandString.append(NSAttributedString(attachment: icon))
        }
        if infoOptions.showDeviceModel {
            if brandString.length > 0 { brandString.append(NSAttributedString(string: "  ", attributes: [.font: UIFont.systemFont(ofSize: sizes.title)])) }
            brandString.append(NSAttributedString(string: deviceName, attributes: [
                .font: UIFont(name: "AvenirNext-Medium", size: sizes.title) ?? UIFont.systemFont(ofSize: sizes.title, weight: .medium),
                .foregroundColor: textColor,
                .kern: 1,
            ]))
        }

        // Metadata String
        let metaString = createMetadataString(helper: helper, infoOptions: infoOptions, sizes: sizes, color: textColor, initialSeparator: !isTwoLine && brandString.length > 0)

        // Layout
        let watermark = infoOptions.showFestivalWatermark ? UIImage(named: "festival_watermark") : nil

        if isTwoLine {
            drawTwoLineLayout(rect: rect, brand: brandString, meta: metaString, watermark: watermark, sizes: sizes)
        } else {
            drawSingleLineLayout(rect: rect, brand: brandString, meta: metaString, watermark: watermark, sizes: sizes)
        }
    }

    private func drawSingleLineLayout(rect: CGRect, brand: NSAttributedString, meta: NSAttributedString, watermark: UIImage?, sizes: (title: CGFloat, detail: CGFloat, icon: CGFloat)) {
        let finalString = NSMutableAttributedString(attributedString: brand)
        finalString.append(meta)

        let hasContent = finalString.length > 0
        let textSize = finalString.size()
        let textHeight = hasContent ? textSize.height : 0

        var watermarkSize = CGSize.zero
        if let wm = watermark {
            // Keep the watermark compact in single-line layouts.
            let h = hasContent ? sizes.title * 2.2 : min(sizes.title * 4.5, rect.height * 0.8)
            watermarkSize = CGSize(width: h * (wm.size.width / wm.size.height), height: h)
        }

        if let wm = watermark, hasContent { // Split Layout
            let padding = rect.minX == 0 ? rect.width * 0.05 : 0
            let maxTextWidth = rect.width - (padding * 2) - watermarkSize.width - (rect.width * 0.02)

            finalString.draw(in: CGRect(x: rect.minX + padding, y: rect.midY - textHeight / 2, width: min(textSize.width, maxTextWidth), height: textSize.height))
            wm.draw(in: CGRect(x: rect.maxX - padding - watermarkSize.width, y: rect.midY - watermarkSize.height / 2, width: watermarkSize.width, height: watermarkSize.height))
        } else { // Centered Stack
            var totalHeight = textHeight
            if watermark != nil { totalHeight += watermarkSize.height + (hasContent ? sizes.title * 0.05 : 0) }

            let visualOffset = (totalHeight / rect.height < 0.4) ? totalHeight * 0.05 : totalHeight * 0.12
            var currentY = rect.midY - totalHeight / 2 - (hasContent ? visualOffset : 0)

            if let wm = watermark {
                wm.draw(in: CGRect(x: rect.midX - watermarkSize.width / 2, y: currentY, width: watermarkSize.width, height: watermarkSize.height))
                currentY += watermarkSize.height + (hasContent ? sizes.title * 0.05 : 0)
            }
            finalString.draw(in: CGRect(x: rect.midX - textSize.width / 2, y: currentY, width: textSize.width, height: textSize.height))
        }
    }

    private func drawTwoLineLayout(rect: CGRect, brand: NSAttributedString, meta: NSAttributedString, watermark: UIImage?, sizes: (title: CGFloat, detail: CGFloat, icon: CGFloat)) {
        let textSpacing = max(4, sizes.title * 0.25) // Estimate from old code logic: 8 * (width/1000) approx 0.25 * 34
        let totalTextHeight = brand.size().height + textSpacing + meta.size().height
        let hasContent = brand.length > 0 || meta.length > 0

        var watermarkSize = CGSize.zero
        if let wm = watermark {
            // Allow a larger watermark in two-line layouts.
            let h = sizes.title * 3.0
            watermarkSize = CGSize(width: h * (wm.size.width / wm.size.height), height: h)
        }

        if let wm = watermark, hasContent { // Split Layout
            let padding = rect.minX == 0 ? rect.width * 0.05 : 0
            let maxTextWidth = rect.width - (padding * 2) - watermarkSize.width - (rect.width * 0.02)
            let textStartY = rect.midY - totalTextHeight / 2

            brand.draw(in: CGRect(x: rect.minX + padding, y: textStartY, width: min(brand.size().width, maxTextWidth), height: brand.size().height))
            meta.draw(in: CGRect(x: rect.minX + padding, y: textStartY + brand.size().height + textSpacing, width: min(meta.size().width, maxTextWidth), height: meta.size().height))

            wm.draw(in: CGRect(x: rect.maxX - padding - watermarkSize.width, y: rect.midY - watermarkSize.height / 2, width: watermarkSize.width, height: watermarkSize.height))
        } else { // Stacked
            var totalHeight = totalTextHeight
            if watermark != nil { totalHeight += watermarkSize.height + sizes.title * 0.05 }

            let startY = rect.midY - totalHeight / 2 - (totalHeight * 0.02)
            var currentY = startY

            if let wm = watermark {
                wm.draw(in: CGRect(x: rect.midX - watermarkSize.width / 2, y: currentY, width: watermarkSize.width, height: watermarkSize.height))
                currentY += watermarkSize.height + sizes.title * 0.05
            }

            brand.draw(in: CGRect(x: rect.midX - brand.size().width / 2, y: currentY, width: brand.size().width, height: brand.size().height))
            meta.draw(in: CGRect(x: rect.midX - meta.size().width / 2, y: currentY + brand.size().height + textSpacing, width: meta.size().width, height: meta.size().height))
        }
    }

    private func createMetadataString(helper: MetadataHelper, infoOptions: FrameInfoOptions, sizes: (title: CGFloat, detail: CGFloat, icon: CGFloat), color: UIColor, initialSeparator: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var needSeparator = initialSeparator

        let items: [(Bool, String)] = [
            (infoOptions.showEXIF, helper.exifText),
            (infoOptions.showDate, helper.dateText),
            (infoOptions.showTime, helper.timeText),
            (infoOptions.showLocation, helper.locationText),
            (infoOptions.showCopyright && !infoOptions.copyrightText.isEmpty, "© " + infoOptions.copyrightText),
        ]

        let separatorAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "AvenirNext-UltraLight", size: sizes.detail) ?? UIFont.systemFont(ofSize: sizes.detail, weight: .ultraLight),
            .foregroundColor: color.withAlphaComponent(0.4),
            .baselineOffset: sizes.title * 0.02,
        ]
        let detailAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "AvenirNext-Regular", size: sizes.detail) ?? UIFont.systemFont(ofSize: sizes.detail, weight: .regular),
            .foregroundColor: color.withAlphaComponent(0.85),
            .kern: 0.8,
        ]

        for (show, text) in items where show && !text.isEmpty {
            if needSeparator {
                result.append(NSAttributedString(string: " | ", attributes: separatorAttr))
            }
            result.append(NSAttributedString(string: text, attributes: detailAttr))
            needSeparator = true
        }
        return result
    }

    private func createAppleIconAttachment(size: CGFloat, titleSize: CGFloat, color: UIColor) -> NSTextAttachment? {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
        guard let image = UIImage(systemName: "apple.logo", withConfiguration: config)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -titleSize * 0.08, width: size * (image.size.width / image.size.height), height: size)
        return attachment
    }
}

// MARK: - Metadata Helper

private struct MetadataHelper {
    let metadata: [String: Any]?

    var exifText: String {
        guard let metadata, let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] else { return "" }
        let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue
        let aperture = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue
        let shutter = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue

        // Focal Length logic
        var focal: Double?
        if let f35 = (exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? NSNumber)?.doubleValue, f35 > 0 {
            focal = f35
        } else if let f = (exif[kCGImagePropertyExifFocalLength as String] as? NSNumber)?.doubleValue, f > 0 {
            if let px = exif[kCGImagePropertyExifPixelXDimension as String] as? NSNumber,
               let py = exif[kCGImagePropertyExifPixelYDimension as String] as? NSNumber
            {
                // Sensor crop factor approx
                _ = px; _ = py // suppress usage warning if needed or use for calc
                focal = f * (36.0 / 5.76) // Simplified iPhone crop factor
            } else {
                // Map based on CameraSpecs/Range
                focal = mapFocalToEquivalent(f)
            }
        }

        return CameraParameterFormatter.combineEXIFText(iso: iso, aperture: aperture, shutterSpeed: shutter, focalLength: focal)
    }

    var dateText: String { date.map { Self.dateFormatter.string(from: $0) } ?? "" }
    var timeText: String { date.map { Self.timeFormatter.string(from: $0) } ?? "" }

    var locationText: String {
        guard let metadata else { return "" }
        if let name = metadata["locationName"] as? String { return name }
        if let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
           let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
           let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String
        {
            return String(format: "%.4f°%@, %.4f°%@", lat, latRef, lon, lonRef)
        }
        return ""
    }

    private var date: Date? {
        guard let metadata else { return nil }
        if let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let s = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String { return Self.exifFormatter.date(from: s) }
        if let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
           let s = tiff[kCGImagePropertyTIFFDateTime as String] as? String { return Self.exifFormatter.date(from: s) }
        if let ts = metadata["timestamp"] as? TimeInterval { return Date(timeIntervalSince1970: ts) }
        return nil
    }

    private func mapFocalToEquivalent(_ f: Double) -> Double {
        let spec = CameraSpecs.getCurrentDeviceSpec()
        if f >= 1.5, f <= 2.5 { return spec.ultraWideFocalLength ?? 13.0 }
        if f >= 4.0, f <= 6.0 { return spec.wideFocalLength }
        if f >= 6.5, f <= 15.0 { return spec.telephotoFocalLength ?? spec.wideFocalLength * 3.0 }
        return f * 6.0
    }

    private static let exifFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}
