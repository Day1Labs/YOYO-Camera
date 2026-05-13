import Charts
import SwiftUI

struct FilterDetailView: View {
    let filter: FilterIdentifier
    @ObservedObject var filterManager: FilterManager = .shared
    @State private var lutStats: LutStats?
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(FilterConfigManager.getFilterDisplayName(for: filter))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if let tags = lutStats?.tags, !tags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    let isVideo = tag == "Video"
                                    let isPhoto = tag == "Photo"
                                    let isSpecial = isVideo || isPhoto

                                    Text(tag)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(isSpecial ? .white : .black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Group {
                                                if isVideo { Color.purple }
                                                else if isPhoto { Color.blue }
                                                else { Color.white }
                                            }
                                        )
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    Spacer()

                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                if let stats = lutStats {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Filter Personality / Attributes
                            AttributesView(attributes: stats.attributes)

                            // Curves Chart
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Tone Response Curves")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.bottom, 5)

                                Text("R/G/B response to neutral gray input")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                ZStack {
                                    Color(white: 0.05)
                                        .cornerRadius(8)

                                    // Grid lines
                                    VStack {
                                        ForEach(0 ..< 5) { _ in
                                            Divider().background(Color.white.opacity(0.1))
                                            Spacer()
                                        }
                                    }
                                    HStack {
                                        ForEach(0 ..< 5) { _ in
                                            Divider().background(Color.white.opacity(0.1))
                                            Spacer()
                                        }
                                    }

                                    // Curves
                                    CurveShape(points: stats.redCurve)
                                        .stroke(Color.red, lineWidth: 2)

                                    CurveShape(points: stats.greenCurve)
                                        .stroke(Color.green, lineWidth: 2)

                                    CurveShape(points: stats.blueCurve)
                                        .stroke(Color.blue, lineWidth: 2)
                                }
                                .frame(height: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding()
                            .background(Color(white: 0.1))
                            .cornerRadius(12)

                            // Skin Tone Samples
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Skin Tone Impact")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Text("Fitzpatrick Types (Original vs Result)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.bottom, 5)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), alignment: .top)], spacing: 15) {
                                    ForEach(stats.skinSamples, id: \.name) { sample in
                                        ColorSampleView(sample: sample)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(white: 0.1))
                            .cornerRadius(12)

                            // Color Samples (Macbeth)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Macbeth ColorChecker")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Text("Standard 24-patch reference")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.bottom, 5)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), alignment: .top)], spacing: 15) {
                                    ForEach(stats.colorSamples, id: \.name) { sample in
                                        ColorSampleView(sample: sample)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(white: 0.1))
                            .cornerRadius(12)

                            // HSL Analysis
                            VStack(alignment: .leading, spacing: 10) {
                                Text("HSL Shift Analysis")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 75), spacing: 12, alignment: .top)], spacing: 12) {
                                    ForEach(stats.hslShifts, id: \.name) { shift in
                                        HslShiftView(shift: shift)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .padding()
                            .background(Color(white: 0.1))
                            .cornerRadius(12)

                            // Saturation Curve
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Saturation Response")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Text("Input vs Output Saturation (multi-hue)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.bottom, 5)

                                ZStack {
                                    Color(white: 0.05).cornerRadius(6)

                                    // Diagonal Reference (Linear)
                                    GeometryReader { geo in
                                        Path { path in
                                            path.move(to: CGPoint(x: 0, y: geo.size.height))
                                            path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                                        }
                                        .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    }

                                    ForEach(stats.saturationCurves.sorted(by: { $0.key < $1.key }), id: \.key) { name, curve in
                                        CurveShape(points: curve)
                                            .stroke(colorForSaturationCurve(name: name), lineWidth: 2)
                                    }
                                }
                                .frame(height: 120)

                                HStack(spacing: 12) {
                                    ForEach(stats.saturationCurves.keys.sorted(), id: \.self) { name in
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(colorForSaturationCurve(name: name))
                                                .frame(width: 8, height: 8)
                                            Text(name)
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(white: 0.1))
                            .cornerRadius(12)

                            // Split Toning & Tonal Tint
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Tonal Tint")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Shadow to Highlight Gradient")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                // Ramp View
                                GeometryReader { _ in
                                    HStack(spacing: 0) {
                                        ForEach(0 ..< stats.grayscaleRamp.count, id: \.self) { i in
                                            Color(uiColor: stats.grayscaleRamp[i])
                                        }
                                    }
                                }
                                .frame(height: 36)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )

                                // Legends (Split Toning Points)
                                HStack {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color(uiColor: stats.splitTone.shadowTint))
                                            .frame(width: 12, height: 12)
                                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                        Text("Shadows")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                        .foregroundColor(.gray.opacity(0.5))

                                    Spacer()

                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color(uiColor: stats.splitTone.highlightTint))
                                            .frame(width: 12, height: 12)
                                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                        Text("Highlights")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(white: 0.1))
                            .cornerRadius(12)
                        }
                        .padding()
                    }
                } else if filterManager.isLutFilter(filter) {
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Analyzing LUT...")
                            .foregroundColor(.gray)
                            .padding(.top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                            .padding()
                        Text("Not a LUT based filter")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("This filter uses procedural adjustments.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                    .background(Color(white: 0.1))
                    .cornerRadius(12)
                    .padding()
                }
            }
        }
        .onAppear {
            analyzeFilter()
        }
    }

    private func analyzeFilter() {
        guard filterManager.isLutFilter(filter) else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            if let (data, size) = filterManager.getLutData(for: filter) {
                let stats = LutAnalyzer.analyze(lutData: data, size: size)
                DispatchQueue.main.async {
                    lutStats = stats
                }
            }
        }
    }

    private func colorForSaturationCurve(name: String) -> Color {
        switch name {
        case "Red": return .red
        case "Green": return .green
        case "Blue": return .blue
        case "Cyan": return .cyan
        default: return .white
        }
    }
}

struct CurveShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }

        let width = rect.width
        let height = rect.height

        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x * width, y: height - first.y * height))

        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * width, y: height - point.y * height))
        }

        return path
    }
}

struct ColorSampleView: View {
    let sample: LutStats.ColorSample

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                // Left: Input Color (Original)
                Color(uiColor: sample.inputColor)
                // Right: Output Color (Result)
                Color(uiColor: sample.outputColor)
            }
            .frame(height: 40)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            Text(sample.name)
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28, alignment: .top)
                .minimumScaleFactor(0.8)
        }
    }
}

struct AttributesView: View {
    let attributes: LutStats.Attributes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter Personality")
                .font(.headline)
                .foregroundColor(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                AttributeBadge(icon: "thermometer", title: "Temp", value: attributes.temperature.rawValue, color: tempColor)
                AttributeBadge(icon: "circle.lefthalf.filled", title: "Contrast", value: attributes.contrast.rawValue, color: .gray)
                AttributeBadge(icon: "drop.fill", title: "Saturation", value: attributes.saturation.rawValue, color: .blue)
                AttributeBadge(icon: "face.smiling", title: "Skin Tone", value: attributes.skinTone.rawValue, color: attributes.skinTone == .natural ? .green : .orange)
            }

            // Dynamic Range Analysis (Fade/Matte)
            if attributes.blackLevel > 0.005 || attributes.whiteLevel < 0.995 {
                VStack(spacing: 12) {
                    Divider().background(Color.white.opacity(0.1))
                        .padding(.vertical, 4)

                    if attributes.blackLevel > 0.005 {
                        FadeLevelRow(
                            icon: "arrow.up.left.and.arrow.down.right",
                            title: "Vintage Fade",
                            percentage: attributes.blackLevel,
                            description: "Lifted blacks for film look"
                        )
                    }

                    if attributes.whiteLevel < 0.995 {
                        FadeLevelRow(
                            icon: "sun.max.fill",
                            title: "Matte Highlights",
                            percentage: 1.0 - attributes.whiteLevel,
                            description: "Softened whites"
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(white: 0.1))
        .cornerRadius(12)
    }

    var tempColor: Color {
        switch attributes.temperature {
        case .warm: return .orange
        case .cool: return .cyan
        case .neutral: return .gray
        }
    }
}

struct FadeLevelRow: View {
    let icon: String
    let title: String
    let percentage: Float
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Spacer()

                Text(String(format: "%.1f%%", percentage * 100))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
            }

            // Visual Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    Capsule()
                        .fill(Color.black.opacity(0.3))
                        .frame(height: 4)

                    // Fill
                    // We normalize the visual scale: 0-25% is the common range for filters.
                    // If fade is 100% (pure white image), it fills bar.
                    // But to make small fades visible, we might want non-linear or just linear.
                    // Let's use linear 0-50% range mapping to full width, as >50% fade is rare/unusable.
                    let barWidth = min(CGFloat(percentage) * 2.0 * geo.size.width, geo.size.width)

                    Capsule()
                        .fill(LinearGradient(gradient: Gradient(colors: [.gray.opacity(0.7), .white]), startPoint: .leading, endPoint: .trailing))
                        .frame(width: barWidth, height: 4)
                }
            }
            .frame(height: 4)

            Text(description)
                .font(.system(size: 10))
                .foregroundColor(.gray.opacity(0.7))
        }
    }
}

struct AttributeBadge: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(white: 0.15))
        .cornerRadius(8)
    }
}

struct HslShiftView: View {
    let shift: LutStats.HslShift

    var body: some View {
        VStack(spacing: 8) {
            // Color Circle
            ZStack {
                Circle()
                    .fill(Color(uiColor: shift.inputColor))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))

                // Small indicator for output
                Circle()
                    .fill(Color(uiColor: shift.outputColor))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
                    .offset(x: 12, y: 12)
            }

            VStack(spacing: 2) {
                Text(shift.name)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Stats
                HStack(spacing: 4) {
                    if abs(shift.hueShift) > 5 {
                        Text(String(format: "%+.0f°", shift.hueShift))
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                    }

                    if abs(shift.satChange - 1.0) > 0.1 {
                        Text(shift.satChange > 1 ? "S+" : "S-")
                            .font(.system(size: 9))
                            .foregroundColor(shift.satChange > 1 ? .green : .red)
                    }
                }
            }
        }
        .frame(width: 60)
        .padding(8)
        .background(Color(white: 0.15))
        .cornerRadius(8)
    }
}
