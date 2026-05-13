import SwiftUI

enum FilmEffectType: String, CaseIterable, Identifiable {
    case vignette = "Vignette"
    case halation = "Halation"
    case bloom = "Bloom"
    case fog = "Fog"
    case lightLeak = "LightLeak"
    case cineTone = "CineTone"
    case grain = "Grain"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vignette: return "square.arrowtriangle.4.outward"
        case .halation: return "sun.haze.fill"
        case .bloom: return "sun.max.fill"
        case .fog: return "cloud.fog.fill"
        case .lightLeak: return "rays"
        case .cineTone: return "paintpalette.fill"
        case .grain: return "aqi.medium"
        }
    }

    var localizedName: String {
        switch self {
        case .vignette: return String.filmEffectVignette.localized
        case .halation: return String.filmEffectHalation.localized
        case .bloom: return String.filmEffectBloom.localized
        case .fog: return String.filmEffectFog.localized
        case .lightLeak: return String.filmEffectLightLeak.localized
        case .cineTone: return String.filmEffectCinetone.localized
        case .grain: return String.filmEffectGrain.localized
        }
    }
}

struct FilmEffectSettingsView: View {
    @ObservedObject var filterManager: FilterManager
    @Binding var selectedEffect: FilmEffectType

    private var isSmallScreen: Bool {
        UIScreen.main.bounds.width < 395
    }

    private var viewHeight: CGFloat {
        isSmallScreen ? 84 : 96
    }

    private var cardSize: CGFloat {
        isSmallScreen ? 64 : 72
    }

    private var isLUTActive: Bool {
        if case .lut = filterManager.selectedFilter.info?.processingType { return true }
        if filterManager.selectedFilter.category == .custom { return true }
        return false
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Spacer()
                    .frame(width: 50)

                ForEach(availableEffects) { effect in
                    EffectCard(
                        effect: effect,
                        isSelected: selectedEffect == effect,
                        intensity: getIntensity(for: effect),
                        size: cardSize
                    )
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation {
                            selectedEffect = effect
                        }
                    }
                }

                ResetCard(
                    isEnabled: filterManager.hasCustomFilmEffects,
                    size: cardSize
                ) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation {
                        filterManager.resetCurrentFilmEffects()
                    }
                }

                Spacer()
                    .frame(width: 50)
            }
            .padding(.vertical, isSmallScreen ? 6 : 8)
        }
        .frame(height: viewHeight)
    }

    private var availableEffects: [FilmEffectType] {
        if isLUTActive {
            return FilmEffectType.allCases.filter { $0 != .cineTone }
        }
        return FilmEffectType.allCases
    }

    private func getIntensity(for effect: FilmEffectType) -> Float {
        switch effect {
        case .vignette: return Float(filterManager.vignetteIntensity)
        case .halation: return Float(filterManager.halationIntensity)
        case .bloom: return Float(filterManager.bloomIntensity)
        case .fog: return Float(filterManager.fogIntensity)
        case .lightLeak: return Float(filterManager.lightLeakIntensity)
        case .cineTone: return Float(filterManager.cineToneIntensity)
        case .grain: return Float(filterManager.grainIntensity)
        }
    }
}

struct EffectCard: View {
    let effect: FilmEffectType
    let isSelected: Bool
    let intensity: Float
    var size: CGFloat = 72

    var body: some View {
        VStack(spacing: size < 70 ? 4 : 6) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                    .frame(width: size < 70 ? 24 : 28, height: size < 70 ? 24 : 28)

                Image(systemName: effect.icon)
                    .font(.system(size: size < 70 ? 12 : 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            }

            VStack(spacing: 2) {
                Text(effect.localizedName)
                    .font(.system(size: size < 70 ? 9 : 10, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))

                Text("\(Int(intensity * 100))")
                    .font(.system(size: size < 70 ? 9 : 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .white.opacity(0.3))
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size < 70 ? 12 : 14)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.black.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: size < 70 ? 12 : 14)
                        .stroke(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}

struct ResetCard: View {
    let isEnabled: Bool
    var size: CGFloat = 72
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: size < 70 ? 4 : 6) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: size < 70 ? 24 : 28, height: size < 70 ? 24 : 28)

                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: size < 70 ? 12 : 14, weight: .bold))
                        .foregroundColor(isEnabled ? .white : .white.opacity(0.3))
                }

                VStack(spacing: 2) {
                    Text(String.filmReset.localized)
                        .font(.system(size: size < 70 ? 9 : 10, weight: .semibold))
                        .foregroundColor(isEnabled ? .white : .white.opacity(0.3))

                    Text(String.filmDefault.localized)
                        .font(.system(size: size < 70 ? 9 : 10, weight: .medium))
                        .foregroundColor(isEnabled ? .white.opacity(0.6) : .white.opacity(0.2))
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size < 70 ? 12 : 14)
                    .fill(Color.black.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: size < 70 ? 12 : 14)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .disabled(!isEnabled)
    }
}
