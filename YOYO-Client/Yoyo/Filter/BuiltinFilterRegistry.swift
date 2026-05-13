import CoreGraphics
import CoreImage
import Foundation

/// Built-in filter registry (data-driven, extensible)
final class BuiltinFilterRegistry {
    static let shared = BuiltinFilterRegistry()

    private var filters: [String: FilterInfo] = [:]

    /// All built-in filter names (in order of registration)
    private(set) var allNames: [String] = []

    private init() {
        registerAllBuiltinFilters()
    }

    // MARK: - public method

    func info(for name: String) -> FilterInfo? {
        filters[name]
    }

    func contains(_ name: String) -> Bool {
        filters[name] != nil
    }

    // MARK: - Registration method

    private func register(name: String, info: FilterInfo) {
        filters[name] = info
        allNames.append(name)
    }

    // MARK: - Register all built-in filters

    private func registerAllBuiltinFilters() {
        func idx(_ preset: FilmPreset) -> String {
            preset.id
        }

        // F-Chrome - Fuji Style
        let fChromeChain: [FilterChainStep] = []
        register(name: "FC", info: FilterInfo(
            colorTemperature: .neutral, // Change it to neutral, not cool.
            intensity: .moderate,
            descriptionKey: "filter_f_chrome_description",
            processingType: .builtin,
            chain: fChromeChain,
            filmEffects: FilterDefaultFilmEffects(
                cineToneIntensity: 1.0, // Maximize the intensity to make the physical model fully effective
                filmPresetID: idx(.fujiEterna), // fujifilmClassicChrome
                vignetteIntensity: 0.15, // Fine-tuning: 0.35 -> 0.15, simulate camera straight out, reduce overly suppressed vignetting
                grainIntensity: 0.20 // Slightly more granular
            )
        ))

        // L-Classic - Leica style
        let lClassicChain: [FilterChainStep] = []
        register(name: "LC", info: FilterInfo(
            colorTemperature: .warm,
            intensity: .strong,
            descriptionKey: "filter_l_classic_description",
            processingType: .builtin,
            chain: lClassicChain,
            filmEffects: FilterDefaultFilmEffects(
                cineToneIntensity: 1.0,
                filmPresetID: idx(.agfaVista400), // leicaClassic
                vignetteIntensity: 0.25, // 0.35 -> 0.25: Slightly weaken the vignetting and brighten the edges of the screen
                grainIntensity: 0.12 // Add trace amounts of organic particles to eliminate digital smoothness
            )
        ))

        // GR - Ricoh Style
        let grChain: [FilterChainStep] = []
        register(name: "GR", info: FilterInfo(
            colorTemperature: .neutral, // Changed to neutral, mainly relying on Preset's printWarmth color cast
            intensity: .strong,
            descriptionKey: "filter_gr_description",
            processingType: .builtin,
            chain: grChain,
            filmEffects: FilterDefaultFilmEffects(
                cineToneIntensity: 1.0,
                filmPresetID: idx(.kodak5219), // ricohGR
                halationIntensity: 0,
                vignetteIntensity: 0.30, // 0.35 -> 0.30: Fine-tune vignetting
                grainIntensity: 0.25 // 0.30 -> 0.25: fine-tune particles
            )
        ))

        register(name: "Silk", info: FilterInfo(
            colorTemperature: .neutral,
            intensity: .moderate,
            descriptionKey: "filter_spring_description",
            inspired: "FP 100C",
            filterName: "Silk",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakPortra400), // Portra 400 - Softening skin tone properties of FP 100C
                bloomIntensity: 0.15, // Soft halo
                vignetteIntensity: 0.10,
                grainIntensity: 0.08
            )
        ))
        register(name: "Breeze", info: FilterInfo(
            colorTemperature: .warm,
            intensity: .subtle,
            descriptionKey: "filter_breeze_description",
            inspired: "C200",
            filterName: "Breeze",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakVision3), // Kodak Vision3 - C200's warm everyday feel
                halationIntensity: 0.10, // warm glow
                fogIntensity: 0.08,
                grainIntensity: 0.12
            )
        ))
        register(name: "Dusk", info: FilterInfo(
            colorTemperature: .neutral,
            intensity: .moderate,
            descriptionKey: "filter_dusk_description",
            filterName: "Dusk",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodak5219), // Kodak 5219 - High contrast and deep shadows at dusk
                halationIntensity: 0.08,
                vignetteIntensity: 0.20, // Moderate vignetting
                grainIntensity: 0.15
            )
        ))

        register(name: "Pearl", info: FilterInfo(
            colorTemperature: .neutral,
            intensity: .subtle,
            descriptionKey: "filter_kyoto_description",
            inspired: "Pro 160S",
            filterName: "Pearl",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakPortra400), // Portra 400 - Pro 160S for delicate skin tones
                bloomIntensity: 0.12,
                vignetteIntensity: 0.08,
                grainIntensity: 0.05
            )
        ))
        register(name: "Horizon", info: FilterInfo(
            colorTemperature: .cool,
            intensity: .moderate,
            descriptionKey: "filter_horizon_description",
            inspired: "Provia 100F",
            filterName: "Horizon",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakEktar100), // Ektar 100 - Provia's bright colors and fine grain
                bloomIntensity: 0.08,
                vignetteIntensity: 0.12,
                grainIntensity: 0.06
            )
        ))
        register(name: "Haze", info: FilterInfo(
            colorTemperature: .neutral,
            intensity: .moderate,
            descriptionKey: "filter_haze_description",
            inspired: "Film 3513",
            filterName: "Haze",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.cinestill800T), // CineStill 800T - The unique glow of motion picture film
                halationIntensity: 0.18, // Main effect: red glow
                fogIntensity: 0.20, // Moderate haze
                grainIntensity: 0.18
            )
        ))
        register(name: "Dawn", info: FilterInfo(
            colorTemperature: .warm,
            intensity: .subtle,
            descriptionKey: "filter_dawn_description",
            inspired: "Sensia 100",
            filterName: "Dawn",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakPortra400), // Portra 400 - Soft warm tone of Sensia
                bloomIntensity: 0.15, // Soft halo
                grainIntensity: 0.08
            )
        ))
        register(name: "Blossom", info: FilterInfo(
            colorTemperature: .warm,
            intensity: .strong,
            descriptionKey: "filter_blossom_description",
            inspired: "Velvia 50",
            filterName: "Blossom",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.fujiVelvia50), // Velvia 50 - high saturation and vivid colors
                // Velvia is known for its sharpness and should not have halation
                vignetteIntensity: 0.15,
                grainIntensity: 0.05 // fine particles
            )
        ))

        register(name: "Frost", info: FilterInfo(
            colorTemperature: .cool,
            intensity: .moderate,
            descriptionKey: "filter_frost_description",
            inspired: "T64",
            filterName: "Frost",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.fujiEterna), // Fuji Eterna - T64 cold-tuned tungsten lamp characteristics
                halationIntensity: 0.15, // cool halo
                fogIntensity: 0.08,
                grainIntensity: 0.10
            )
        ))

        register(name: "Petal", info: FilterInfo(
            colorTemperature: .cool,
            intensity: .subtle,
            descriptionKey: "filter_petal_description",
            inspired: "Astia 100F",
            filterName: "Petal",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.fujiPro400H), // Fuji Pro 400H - Astia's soft skin tones and pastel shades
                bloomIntensity: 0.12,
                vignetteIntensity: 0.06,
                grainIntensity: 0.05
            )
        ))

        register(name: "Oasis", info: FilterInfo(
            colorTemperature: .cool,
            intensity: .subtle,
            descriptionKey: "filter_oasis_description",
            inspired: "Pro 400H",
            filterName: "Oasis",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.fujiPro400H), // Fuji Pro 400H - Airy and soft highlights
                bloomIntensity: 0.10, // Soft halo
                fogIntensity: 0.15, // air feeling
                grainIntensity: 0.15
            )
        ))

        // black and white
        register(name: "Decisive", info: FilterInfo(
            colorTemperature: .blackWhite,
            intensity: .strong,
            descriptionKey: "filter_decisive_description",
            filterName: "Decisive",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodak5219), // Kodak 5219 - Deep blacks with high contrast black and white
                halationIntensity: 0.08,
                vignetteIntensity: 0.25, // Moderate vignetting
                grainIntensity: 0.25 // Noticeable but not excessive graininess
            )
        ))

        register(name: "Fan", info: FilterInfo(
            colorTemperature: .blackWhite,
            intensity: .strong,
            descriptionKey: "filter_fan_description",
            filterName: "Fan",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakPortra400), // Portra 400 - Rich gradations of soft black and white
                bloomIntensity: 0.15, // Soft halo
                fogIntensity: 0.06,
                grainIntensity: 0.18
            )
        ))

        // TODO: Change the 3 filters adapted to movies to place names

        // MARK: - Asian regional style series - China

        register(name: "Xihu", info: FilterInfo(
            colorTemperature: .cool,
            intensity: .moderate,
            descriptionKey: "filter_xihu_description",
            filterName: "Xihu",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.fujiEterna), // Fuji Eterna - The cool ink painting mood of West Lake
                bloomIntensity: 0.12,
                fogIntensity: 0.18, // ink mist
                vignetteIntensity: 0.10,
                grainIntensity: 0.08
            )
        ))

        // Film nostalgia, faded matte texture, warm skin tones, and desaturated yellowish greens
        register(name: "Dali", info: FilterInfo(
            colorTemperature: .warm,
            intensity: .moderate,
            descriptionKey: "filter_dali_description",
            inspired: "Sensia 200",
            filterName: "Dali",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakVision3), // Kodak Vision3 - The warm sunshine and nostalgia of Dali
                halationIntensity: 0.12, // warm glow
                fogIntensity: 0.10,
                vignetteIntensity: 0.12,
                grainIntensity: 0.15
            )
        ))

        register(name: "Fuji", info: FilterInfo(
            colorTemperature: .neutral,
            intensity: .moderate,
            descriptionKey: "filter_fuji_description",
            inspired: "Pro 160NC",
            filterName: "Fuji",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakPortra400), // Portra 400 - Pro 160NC Natural Color
                bloomIntensity: 0.08,
                vignetteIntensity: 0.10,
                grainIntensity: 0.10
            )
        ))

        register(name: "Kamakura", info: FilterInfo(
            colorTemperature: .neutral,
            intensity: .moderate,
            descriptionKey: "filter_kamakura_description",
            inspired: "ProImage 100",
            filterName: "Kamakura",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakVision3), // Kodak Vision3 - Japanese freshness
                bloomIntensity: 0.10,
                vignetteIntensity: 0.15,
                grainIntensity: 0.12
            )
        ))
        // register(name: "Lijiang", info: FilterInfo(
        //     colorTemperature: .cool,
        //     intensity: .moderate,
        //     descriptionKey: "filter_lijiang_description",
        //     filterName: "Lijiang"
        // ))
        // register(name: "Potala", info: FilterInfo(
        //     colorTemperature: .warm,
        //     intensity: .strong,
        //     descriptionKey: "filter_potala_description",
        //     inspired: "Fortia SP",
        //     filterName: "Potala"
        // ))
        // register(name: "Wuzhen", info: FilterInfo(
        //     colorTemperature: .cool,
        //     intensity: .moderate,
        //     descriptionKey: "filter_wuzhen_description",
        //     inspired: "Provia 400X",
        //     filterName: "Wuzhen"
        // ))

        // register(name: "Taipei", info: FilterInfo(
        //     colorTemperature: .warm,
        //     intensity: .subtle,
        //     descriptionKey: "filter_taipei_description",
        //     inspired: "C200",
        //     filterName: "Taipei"
        // ))

        // MARK: - Asian regional style series - Japan

        // register(name: "Sagami", info: FilterInfo(
        //     colorTemperature: .cool,
        //     intensity: .moderate,
        //     descriptionKey: "filter_sagami_description",
        //     filterName: "Sagami"
        // ))
        // register(name: "Shibuya", info: FilterInfo(
        //     colorTemperature: .cool,
        //     intensity: .strong,
        //     descriptionKey: "filter_shibuya_description",
        //     filterName: "Shibuya"
        // ))

        // MARK: - European regional style series

        register(name: "Lisbon", info: FilterInfo(
            colorTemperature: .warm,
            intensity: .moderate,
            descriptionKey: "filter_lisbon_description",
            filterName: "Lisbon",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.cinestill800T), // CineStill 800T – Lisbon’s warm streets and neon glow
                halationIntensity: 0.18, // CineStill Signature Blush
                vignetteIntensity: 0.12,
                grainIntensity: 0.15
            )
        ))

        register(name: "Faroe", info: FilterInfo(
            colorTemperature: .cool,
            intensity: .moderate,
            descriptionKey: "filter_faroe_description",
            inspired: "Pro 400H", // The low-saturation air sense integrates the ambient colors into cool cyan blue and mint green, while retaining the warm golden skin tone and giving the picture a soft and nostalgic matte faded (Matte) texture.
            filterName: "Faroe",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.fujiPro400H), // Fuji Pro 400H - Faroese air and soft fade
                bloomIntensity: 0.10,
                fogIntensity: 0.20, // Air haze
                grainIntensity: 0.18
            )
        ))
        register(name: "Marrakech", info: FilterInfo(
            colorTemperature: .neutral,
            intensity: .moderate,
            descriptionKey: "filter_marrakech_description",
            inspired: "2383", // A warm-toned filter with a retro cinematic feel, it can render the image into a golden sunset atmosphere like Kodachrome film, with deep cyan blue shadows and dry, low-saturated olive green.
            filterName: "Marrakech",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodak5219), // Kodak 5219/2383 - Golden sunset and cinematic feel in Marrakech
                halationIntensity: 0.15, // film halo
                vignetteIntensity: 0.20,
                grainIntensity: 0.22
            )
        ))

        // register(name: "Paris", info: FilterInfo(
        //     colorTemperature: .warm,
        //     intensity: .subtle,
        //     descriptionKey: "filter_paris_description",
        //     inspired: "Pro 400H",
        //     filterName: "Paris"
        // ))
        // register(name: "London", info: FilterInfo(
        //     colorTemperature: .warm,
        //     intensity: .moderate,
        //     descriptionKey: "filter_london_description",
        //     filterName: "London"
        // ))
        // register(name: "Vienna", info: FilterInfo(
        //     colorTemperature: .neutral,
        //     intensity: .moderate,
        //     descriptionKey: "filter_vienna_description",
        //     filterName: "Vienna"
        // ))
        // register(name: "Alpine", info: FilterInfo(
        //     colorTemperature: .cool,
        //     intensity: .moderate,
        //     descriptionKey: "filter_alpine_description",
        //     filterName: "Alpine"
        // ))
        // register(name: "Iceland", info: FilterInfo(
        //     colorTemperature: .cool,
        //     intensity: .strong,
        //     descriptionKey: "filter_iceland_description",
        //     filterName: "Iceland"
        // ))
        // register(name: "Santorini", info: FilterInfo(
        //     colorTemperature: .warm,
        //     intensity: .subtle,
        //     descriptionKey: "filter_santorini_description",
        //     inspired: "Pro 400H",
        //     filterName: "Santorini"
        // ))

        // MARK: - American regional style series

        register(name: "GoldenGate", info: FilterInfo(
            colorTemperature: .neutral,
            intensity: .moderate,
            descriptionKey: "filter_golden_gate_description",
            inspired: "Gold 200",
            filterName: "GoldenGate",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakGold200), // The warm golden tone of Gold 200
                halationIntensity: 0.12, // golden halo
                vignetteIntensity: 0.12,
                grainIntensity: 0.15
            )
        ))

        register(name: "Joshua", info: FilterInfo(
            colorTemperature: .neutral,
            intensity: .subtle,
            descriptionKey: "filter_joshua_description",
            inspired: "Portra 400",
            filterName: "Joshua",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakPortra400), // Portra 400 - The soft desert light of Joshua Tree
                bloomIntensity: 0.08,
                fogIntensity: 0.05,
                vignetteIntensity: 0.10,
                grainIntensity: 0.12
            )
        ))

        register(name: "Havana", info: FilterInfo(
            colorTemperature: .warm,
            intensity: .moderate,
            descriptionKey: "filter_havana_description",
            inspired: "5219", // Movie film, "dry, faded, warm-toned, and aged after long exposure to sunlight."
            // Since it greatly suppresses the blue (the sky becomes gray) and intensifies the earth tones (yellow/orange/brown), it is not suitable for places known for their blue sea and sky (such as the Maldives), but is very suitable for places with a "dusty feel", "rock texture" or "nostalgic time feeling"
            filterName: "Havana",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodak5219), // Kodak 5219 - Retro cinematic feel and faded texture of Havana
                halationIntensity: 0.15, // retro glow
                fogIntensity: 0.10,
                vignetteIntensity: 0.20,
                grainIntensity: 0.25
            )
        ))

        // register(name: "Hollywood", info: FilterInfo(
        //     colorTemperature: .neutral,
        //     intensity: .moderate,
        //     descriptionKey: "filter_hollywood_description",
        //     inspired: "5294",
        //     filterName: "Hollywood"
        // ))

        // register(name: "California", info: FilterInfo(
        //     colorTemperature: .warm,
        //     intensity: .strong,
        //     descriptionKey: "filter_california_description",
        //     inspired: "Ektar 100",
        //     filterName: "California"
        // ))
        // register(name: "Texas", info: FilterInfo(
        //     colorTemperature: .warm,
        //     intensity: .moderate,
        //     descriptionKey: "filter_texas_description",
        //     inspired: "Gold Master",
        //     filterName: "Texas"
        // ))
        // register(name: "Vegas", info: FilterInfo(
        //     colorTemperature: .warm,
        //     intensity: .moderate,
        //     descriptionKey: "filter_vegas_description",
        //     inspired: "UltraMax 400",
        //     filterName: "Vegas"
        // ))
        // register(name: "NewYork", info: FilterInfo(
        //     colorTemperature: .cool,
        //     intensity: .strong,
        //     descriptionKey: "filter_newyork_description",
        //     filterName: "NewYork"
        // ))
        // register(name: "Yosemite", info: FilterInfo(
        //     colorTemperature: .neutral,
        //     intensity: .moderate,
        //     descriptionKey: "filter_yosemite_description",
        //     filterName: "Yosemite"
        // ))
        // register(name: "Patagonia", info: FilterInfo(
        //     colorTemperature: .cool,
        //     intensity: .moderate,
        //     descriptionKey: "filter_patagonia_description",
        //     filterName: "Patagonia"
        // ))

        // MARK: - African regional style series

        // High warm tone, low cool color saturation, cream highlight, retro green
        register(name: "Sahara", info: FilterInfo(
            colorTemperature: .warm,
            intensity: .moderate,
            descriptionKey: "filter_dune_description",
            filterName: "Sahara",
            filmEffects: FilterDefaultFilmEffects(
                filmPresetID: idx(.kodakVision3), // Kodak Vision3 - The golden desert and warm light of the Sahara
                halationIntensity: 0.12, // desert halo
                fogIntensity: 0.12,
                vignetteIntensity: 0.15,
                grainIntensity: 0.18
            )
        ))
    }
}

// MARK: - FilterIdentifier extension

extension FilterIdentifier {
    /// Get filter information
    var info: FilterInfo? {
        switch category {
        case .none:
            return FilterInfo(
                colorTemperature: .neutral,
                intensity: .subtle,
                descriptionKey: "filter_none_description",
                processingType: .builtin,
                chain: []
            )
        case .builtin:
            return BuiltinFilterRegistry.shared.info(for: name)
        case .custom:
            return FilterInfo(
                colorTemperature: .neutral,
                intensity: .moderate,
                descriptionKey: "filter_custom_description",
                processingType: .custom
            )
        }
    }

    /// Color temperature type
    var colorTemperature: FilterColorTemperature {
        info?.colorTemperature ?? .neutral
    }

    /// filter strength
    var intensity: FilterIntensity {
        info?.intensity ?? .moderate
    }

    /// describe
    var description: String {
        info?.localizedDescription ?? ""
    }

    /// source of inspiration
    var inspired: String? {
        info?.inspired
    }

    /// display name
    var displayName: String {
        switch category {
        case .none:
            return "None"
        case .builtin:
            return name
        case .custom:
            return name
        }
    }
}

// MARK: - Search function

extension BuiltinFilterRegistry {
    /// Search filters based on keywords
    func search(keyword: String) -> [String] {
        let lowercaseKeyword = keyword.lowercased()

        return allNames.filter { name in
            guard let info = filters[name] else { return false }
            return name.lowercased().contains(lowercaseKeyword) ||
                info.localizedDescription.lowercased().contains(lowercaseKeyword) ||
                (info.inspired?.lowercased().contains(lowercaseKeyword) ?? false)
        }
    }
}
