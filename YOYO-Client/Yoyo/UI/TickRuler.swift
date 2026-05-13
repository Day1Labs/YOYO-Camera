import SwiftUI

// MARK: - Universal scale ruler component
struct TickRuler<Value: Hashable>: View {
    @Binding var value: Value
    let stops: [Value]
    let isMajor: (Value) -> Bool
    let formatValue: (Value) -> String
    var onSelectionChange: ((Value) -> Void)?
    var onInteractionStart: (() -> Void)?
    var onInteractionEnd: (() -> Void)?

    private let tickSpacing: CGFloat = 16

    var body: some View {
        Group {
            if #available(iOS 17.5, *) {
                TickRulerModern(
                    value: $value,
                    stops: stops,
                    isMajor: isMajor,
                    formatValue: formatValue,
                    onSelectionChange: onSelectionChange,
                    onInteractionStart: onInteractionStart,
                    onInteractionEnd: onInteractionEnd,
                    tickSpacing: tickSpacing
                )
            } else {
                TickRulerLegacy(
                    value: $value,
                    stops: stops,
                    isMajor: isMajor,
                    formatValue: formatValue,
                    onSelectionChange: onSelectionChange,
                    onInteractionStart: onInteractionStart,
                    onInteractionEnd: onInteractionEnd,
                    tickSpacing: tickSpacing
                )
            }
        }
    }
}

// MARK: - scale view
struct RulerTick: View {
    let label: String
    let isMajor: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .center) {
                Spacer()
                RoundedRectangle(cornerRadius: 1)
                    .fill(isSelected ? Color.accentColor : (isMajor ? Color.white : Color.white.opacity(0.4)))
                    .frame(width: isSelected ? 3 : (isMajor ? 2 : 1))
                    .frame(height: isSelected ? 20 : (isMajor ? 14 : 10))
                    .animation(.spring(response: 0.3), value: isSelected)
            }
            .frame(height: 20)

            Spacer().frame(height: 4)

            ZStack(alignment: .top) {
                if isMajor || isSelected {
                    Text(label)
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .accentColor : .white)
                        .fixedSize()
                        .padding(.horizontal, 2)
                        .background(isSelected ? Color(red: 47 / 255, green: 47 / 255, blue: 47 / 255) : Color.clear)
                        .cornerRadius(2)
                        .transition(.opacity)
                } else {
                    Text(" ")
                        .font(.system(size: 10))
                }
            }
            .frame(height: 16)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Modern implementation (iOS 17.5+)

@available(iOS 17.0, *)
private struct TickRulerModern<Value: Hashable>: View {
    @Binding var value: Value
    let stops: [Value]
    let isMajor: (Value) -> Bool
    let formatValue: (Value) -> String
    var onSelectionChange: ((Value) -> Void)?
    var onInteractionStart: (() -> Void)?
    var onInteractionEnd: (() -> Void)?
    let tickSpacing: CGFloat

    @State private var scrollID: Int?
    @State private var isInteracting: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                        RulerTick(
                            label: formatValue(stop),
                            isMajor: isMajor(stop),
                            isSelected: scrollID == index
                        )
                        .id(index)
                        .frame(width: tickSpacing)
                        .zIndex(scrollID == index ? 100 : 0)
                        .onTapGesture {
                            withAnimation(.snappy) {
                                scrollID = index
                            }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollID)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, (geometry.size.width - tickSpacing) / 2, for: .scrollContent)
            .onChange(of: scrollID) { _, newID in
                handleScrollSelectionChange(newID)
            }
            .onChange(of: value) { _, newValue in
                alignScrollID(with: newValue)
            }
            .onAppear {
                initializeScrollID()
            }
            .simultaneousGesture(commonDragGesture())
        }
        .frame(height: 50)
        .mask(edgeMask)
    }

    private func handleScrollSelectionChange(_ newID: Int?) {
        guard let index = newID, index >= 0, index < stops.count else { return }
        let newValue = stops[index]
        if value != newValue {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            value = newValue
            onSelectionChange?(newValue)
        }
    }

    private func alignScrollID(with newValue: Value) {
        guard let index = stops.firstIndex(of: newValue), scrollID != index else { return }
        withAnimation(.snappy) {
            scrollID = index
        }
    }

    private func initializeScrollID() {
        if let index = stops.firstIndex(of: value) {
            scrollID = index
        }
    }

    private func commonDragGesture() -> some Gesture {
        DragGesture()
            .onChanged { _ in
                if !isInteracting {
                    isInteracting = true
                    onInteractionStart?()
                }
            }
            .onEnded { _ in
                isInteracting = false
                onInteractionEnd?()
            }
    }

    private var edgeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(gradient: Gradient(colors: [.clear, .black]), startPoint: .leading, endPoint: .trailing)
                .frame(width: 30)
            Rectangle().fill(Color.black)
            LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .leading, endPoint: .trailing)
                .frame(width: 30)
        }
    }
}

// MARK: - Legacy implementation (<= iOS 17.4)

private struct TickRulerLegacy<Value: Hashable>: View {
    @Binding var value: Value
    let stops: [Value]
    let isMajor: (Value) -> Bool
    let formatValue: (Value) -> String
    var onSelectionChange: ((Value) -> Void)?
    var onInteractionStart: (() -> Void)?
    var onInteractionEnd: (() -> Void)?
    let tickSpacing: CGFloat

    @State private var scrollID: Int?
    @State private var isInteracting: Bool = false

    private let coordinateSpaceName = "TickRulerScrollView"

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    let inset = max((geometry.size.width - tickSpacing) / 2, 0)
                    HStack(spacing: 0) {
                        Color.clear.frame(width: inset)

                        ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                            RulerTick(
                                label: formatValue(stop),
                                isMajor: isMajor(stop),
                                isSelected: scrollID == index
                            )
                            .id(index)
                            .frame(width: tickSpacing)
                            .background(centerPreference(index: index))
                            .zIndex(scrollID == index ? 100 : 0)
                            .onTapGesture {
                                withAnimation(.snappy) {
                                    scrollID = index
                                }
                            }
                        }

                        Color.clear.frame(width: inset)
                    }
                }
                .coordinateSpace(name: coordinateSpaceName)
                .onAppear {
                    initializeScrollID()
                    if let index = scrollID {
                        proxyScroll(to: index, proxy: proxy, animated: false)
                    }
                }
                .onChange(of: scrollID) { _, newID in
                    handleScrollSelectionChange(newID)
                    guard let index = newID, !isInteracting else { return }
                    proxyScroll(to: index, proxy: proxy, animated: true)
                }
                .onChange(of: value) { _, newValue in
                    guard !isInteracting else { return }
                    alignScrollID(with: newValue, proxy: proxy)
                }
                .onPreferenceChange(TickCenterPreferenceKey.self) { centers in
                    guard isInteracting else { return }
                    let targetCenter = geometry.size.width / 2
                    if let closest = centers.min(by: { abs($0.center - targetCenter) < abs($1.center - targetCenter) }),
                       scrollID != closest.index
                    {
                        scrollID = closest.index
                    }
                }
                .simultaneousGesture(commonDragGesture())
            }
        }
        .frame(height: 50)
        .mask(edgeMask)
    }

    private func handleScrollSelectionChange(_ newID: Int?) {
        guard let index = newID, index >= 0, index < stops.count else { return }
        let newValue = stops[index]
        if value != newValue {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            value = newValue
            onSelectionChange?(newValue)
        }
    }

    private func alignScrollID(with newValue: Value, proxy: ScrollViewProxy) {
        guard let index = stops.firstIndex(of: newValue), scrollID != index else { return }
        scrollID = index
        proxyScroll(to: index, proxy: proxy, animated: true)
    }

    private func initializeScrollID() {
        if let index = stops.firstIndex(of: value) {
            scrollID = index
        }
    }

    private func proxyScroll(to index: Int, proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.snappy) {
                proxy.scrollTo(index, anchor: .center)
            }
        } else {
            proxy.scrollTo(index, anchor: .center)
        }
    }

    private func centerPreference(index: Int) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TickCenterPreferenceKey.self,
                value: [TickCenterPreferenceData(index: index, center: proxy.frame(in: .named(coordinateSpaceName)).midX)]
            )
        }
    }

    private func commonDragGesture() -> some Gesture {
        DragGesture()
            .onChanged { _ in
                if !isInteracting {
                    isInteracting = true
                    onInteractionStart?()
                }
            }
            .onEnded { _ in
                isInteracting = false
                onInteractionEnd?()
            }
    }

    private var edgeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(gradient: Gradient(colors: [.clear, .black]), startPoint: .leading, endPoint: .trailing)
                .frame(width: 30)
            Rectangle().fill(Color.black)
            LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .leading, endPoint: .trailing)
                .frame(width: 30)
        }
    }

    private struct TickCenterPreferenceData: Equatable {
        let index: Int
        let center: CGFloat
    }

    private struct TickCenterPreferenceKey: PreferenceKey {
        static var defaultValue: [TickCenterPreferenceData] { [] }

        static func reduce(value: inout [TickCenterPreferenceData], nextValue: () -> [TickCenterPreferenceData]) {
            value.append(contentsOf: nextValue())
        }
    }
}

// MARK: - Convenient extension: supports nearest value lookup of Double type
extension TickRuler where Value == Double {
    /// Create a `TickRuler` for `Double` values with nearest-value matching.
    init(
        value: Binding<Double>,
        stops: [Double],
        isMajor: @escaping (Double) -> Bool,
        formatValue: @escaping (Double) -> String,
        onSelectionChange: ((Double) -> Void)? = nil,
        onInteractionStart: (() -> Void)? = nil,
        onInteractionEnd: (() -> Void)? = nil
    ) {
        _value = value
        self.stops = stops
        self.isMajor = isMajor
        self.formatValue = formatValue
        self.onSelectionChange = onSelectionChange
        self.onInteractionStart = onInteractionStart
        self.onInteractionEnd = onInteractionEnd
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            // ISO example.
            TickRuler(
                value: .constant(400),
                stops: Array(stride(from: 50, through: 3200, by: 50)),
                isMajor: { $0 % 400 == 0 || $0 == 50 },
                formatValue: { "\(Int($0))" }
            )

            // Exposure compensation example.
            TickRuler(
                value: .constant(0.0),
                stops: Array(stride(from: -2.0, through: 2.0, by: 0.1)),
                isMajor: { abs($0.truncatingRemainder(dividingBy: 1.0)) < 0.01 },
                formatValue: { String(format: "%+.1f", $0) }
            )
        }
        .padding()
    }
}
