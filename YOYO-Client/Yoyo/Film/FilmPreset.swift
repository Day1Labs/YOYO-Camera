import Foundation

/// Film Characteristics Presets - Based on real film measurement data
struct FilmPreset: Identifiable, Codable {
    var id: String { name }
    let name: String
    var author: String?
    let negativeExposure: Float // Negative exposure offset (-1 ~ +1)
    let developmentGamma: Float // Development Gamma (0 ~ 1)
    let printContrast: Float // Print contrast (0 ~ 1)
    let dyeDensity: Float // Dye density (0 ~ 1)
    let colorCrosstalk: Float // Color crosstalk (0 ~ 1)
    let highlightRolloff: Float // Highlight roll-off (0 ~ 1)
    let shadowLift: Float // Shadow Boost (0 ~ 1)
    let printWarmth: Float // Print color temperature (0 ~ 1)

    // New: Film physical property parameters
    let layerSpeeds: SIMD3<Float> // Three-layer emulsion relative velocity (R, G, B)
    let layerCrossovers: SIMD3<Float> // Crosstalk crossover point (low/medium/high exposure)
    let adjacencyStrength: Float // Adjacency effect strength

    // New: Film Grain and Halo Physics
    let grainRoughness: Float // Grain Roughness (1.0 = Standard)
    let halationSpreadScale: Float // Halo diffusion scaling (1.0 = standard)
    let halationThresholdOffset: Float // Halo threshold shift (negative = easier to trigger)

    // New: Default Effect Strength (user-adjustable base strength)
    let cineToneIntensity: Float // Effect strength (0 ~ 1), default core properties

    let grainIntensity: Float // Particle strength (0 ~ 1)
    let halationIntensity: Float // Halo intensity (0 ~ 1)

    // MARK: - Halation color properties

    /// Color of the halo core area (high energy area, close to the light source)
    /// Usually warm white, there are slight differences between different films
    let halationTintCore: SIMD3<Float>

    /// Halo middle zone color (medium energy zone)
    /// This is the most characteristic color area of ​​the halo
    let halationTintMid: SIMD3<Float>

    /// Color of halo edge area (low energy area, furthest scattering)
    let halationTintEdge: SIMD3<Float>

    /// Halo intensity factor (1.0 = standard, films without Rem-Jet layer such as CineStill should be higher)
    let halationStrength: Float

    // MARK: - Color Mixer (Channel Mixer)

    // Used to simulate non-linear hue shifts (such as Fuji's blue cast, Canon's skin tone protection)
    let channelMixerRed: SIMD3<Float>
    let channelMixerGreen: SIMD3<Float>
    let channelMixerBlue: SIMD3<Float>

    /// Kodak Vision3 500T - Classic Tungsten Balanced Cinema Negative
    /// Features: High tolerance, rich shadow details, natural skin tone, soft highlights
    /// Reference: Kodak Publication H-1-500T
    /// Halo characteristics: With Rem-Jet anti-halation layer, the halo is mild and orange-red in color
    /// [Physical Correction]: Vision3 is a film negative film with extremely high tolerance for dark areas.
    static let kodakVision3 = FilmPreset(
        name: "Kodak Vision3 500T",
        negativeExposure: 0,
        developmentGamma: 0.55,
        printContrast: 0.45,
        dyeDensity: 0.38,
        colorCrosstalk: 0.5,
        highlightRolloff: 0.72, // Increase 0.65 -> 0.72, film negative highlight rolloff is softer
        shadowLift: 0.52, // Increased 0.48 -> 0.52, extremely wide shadow latitude
        printWarmth: 0.75, // Increase 0.70 -> 0.75, tungsten balance (3200K) more pronounced warm tone
        // Vision3's three-layer emulsion uses advanced KODAK VISION Color Negative Film technology
        // DLT (Dye Layering Technology) reduces particles in dark areas
        layerSpeeds: SIMD3<Float>(0.97, 1.0, 1.03),
        layerCrossovers: SIMD3<Float>(0.2, 0.5, 0.85),
        adjacencyStrength: 0.3,
        // Vision3: T-grain technology, extremely fine particles
        grainRoughness: 0.85, // Reduce 0.9 -> 0.85, closer to true detail
        halationSpreadScale: 1.0,
        halationThresholdOffset: 0.0,
        cineToneIntensity: 0.85, // Film negative, the effect is obvious but natural
        grainIntensity: 0.32, // Reduce 0.35 -> 0.32, modern film negatives have extremely fine grain
        halationIntensity: 0.25,
        // Vision3 has a Rem-Jet layer with a milder halo and a classic orange-red hue
        halationTintCore: SIMD3<Float>(1.0, 0.90, 0.80),
        halationTintMid: SIMD3<Float>(1.0, 0.35, 0.10),
        halationTintEdge: SIMD3<Float>(0.80, 0.20, 0.05),
        halationStrength: 1.0,
        // Kodak Matrix: Tungsten balanced, green slightly yellowish, blue suppressed (warm)
        channelMixerRed: SIMD3<Float>(0.98, 0.02, 0.0),
        channelMixerGreen: SIMD3<Float>(0.08, 0.90, 0.02), // Enhance green->red mix, warm tone
        channelMixerBlue: SIMD3<Float>(0.0, 0.05, 0.95) // Mix blue with green to reduce the cold tone
    )

    /// Fuji Eterna 500 - Japanese cinematic feel
    /// Features: Cool color, green and transparent, highlights converge quickly, dark parts are bluish with a red shift
    /// Reference: Fujifilm Motion Picture Products Technical Data
    /// Halo characteristics: There is an anti-halo layer, the halo is cooler, and the red color is slightly magenta.
    /// [Physical Correction]: Eterna is known for its extremely soft tones and dark levels, with a slight red shift in the dark areas.
    static let fujiEterna = FilmPreset(
        name: "Fuji Eterna 500",
        negativeExposure: 0.10,
        developmentGamma: 0.45,
        printContrast: 0.35,
        dyeDensity: 0.30,
        colorCrosstalk: 0.42,
        highlightRolloff: 0.82, // Increase 0.80 -> 0.82, extremely soft highlight transition
        shadowLift: 0.58, // Increase 0.55 -> 0.58, Eterna has extremely high tolerance for dark areas
        printWarmth: 0.48, // Reduce 0.50 -> 0.48, more obvious cold tone
        // Fuji's green-sensitive layer is specially optimized for excellent restoration of green plants.
        layerSpeeds: SIMD3<Float>(0.95, 1.02, 1.05),
        layerCrossovers: SIMD3<Float>(0.25, 0.55, 0.9),
        adjacencyStrength: 0.20,
        // Eterna: extremely fine, finer than Vision3
        grainRoughness: 0.82, // Decrease 0.85 -> 0.82
        halationSpreadScale: 0.9,
        halationThresholdOffset: 0.05,
        cineToneIntensity: 0.70, // Japanese light style, soft effect
        grainIntensity: 0.26, // Decrease 0.28 -> 0.26
        halationIntensity: 0.20,
        // Fuji halo is cooler, red with magenta undertones
        halationTintCore: SIMD3<Float>(0.95, 0.95, 1.0),
        halationTintMid: SIMD3<Float>(0.80, 0.20, 0.40),
        halationTintEdge: SIMD3<Float>(0.60, 0.10, 0.30),
        halationStrength: 0.8,
        // Fuji Matrix: Radical cyan shift, green transparency
        // The red shift in the dark parts is achieved by mixing the red channel into blue (magenta tendency)
        channelMixerRed: SIMD3<Float>(0.90, 0.0, 0.10), // Enhanced red->blue mixture, dark parts appear magenta
        channelMixerGreen: SIMD3<Float>(0.02, 0.82, 0.16), // Radical green->blue mix, transparent green
        channelMixerBlue: SIMD3<Float>(0.0, 0.18, 0.82) // Blue mixed with more green, deep cyan
    )

    /// Kodak 5219 (high contrast print version of Vision3 500T)
    /// Features: High contrast, rich colors, deep blacks, suitable for night scenes
    /// Commonly used in: film noir, crime films, night city scenes
    /// Halo properties: Similar to Vision3, but high contrast processing makes the halo edges sharper
    /// [Physical correction]: Although the contrast is high, it is still a negative film, and the dark parts should not be too black.
    static let kodak5219 = FilmPreset(
        name: "Kodak 5219",
        negativeExposure: -0.1,
        developmentGamma: 0.62,
        printContrast: 0.55, // Reduce 0.62 -> 0.55 to avoid excessive shadows
        dyeDensity: 0.48, // Reduce 0.55 -> 0.48, high contrast but not excessive
        colorCrosstalk: 0.58,
        highlightRolloff: 0.52,
        shadowLift: 0.32, // Increase 0.22 -> 0.32, retain dark details
        printWarmth: 0.83,
        // The difference in the emulsion layer is more obvious when processing with high contrast
        layerSpeeds: SIMD3<Float>(0.88, 1.0, 1.1),
        layerCrossovers: SIMD3<Float>(0.15, 0.45, 0.8),
        adjacencyStrength: 0.4,
        // Slightly more grainy under high contrast
        grainRoughness: 0.95,
        halationSpreadScale: 1.0,
        halationThresholdOffset: -0.02,
        cineToneIntensity: 0.90, // High contrast film roll with strong effects
        // Default effect intensity: obvious grain, strong halo
        grainIntensity: 0.40,
        halationIntensity: 0.30,
        // High-contrast version with a richer orange-red glow
        halationTintCore: SIMD3<Float>(1.0, 0.95, 0.90),
        halationTintMid: SIMD3<Float>(1.0, 0.30, 0.12),
        halationTintEdge: SIMD3<Float>(0.95, 0.42, 0.18),
        halationStrength: 1.1,
        // standard matrix
        channelMixerRed: SIMD3<Float>(1.0, 0.0, 0.0),
        channelMixerGreen: SIMD3<Float>(0.0, 1.0, 0.0),
        channelMixerBlue: SIMD3<Float>(0.0, 0.0, 1.0)
    )

    /// Kodak Portra 400 - Professional Portrait Negative Film
    /// Features: Excellent skin tone, soft highlights, warm shadows, natural colors, medium and low contrast
    /// Commonly used for: Portraits, weddings, fashion, lifestyle photography
    /// Glow properties: Warm, soft orange glow that harmonizes with skin tone
    /// [Physical Correction]: The core characteristics of Portra are rich details in dark areas, high tolerance, and slightly warmer gray areas in dark areas.
    static let kodakPortra400 = FilmPreset(
        name: "Kodak Portra 400",
        negativeExposure: 0.15,
        developmentGamma: 0.48,
        printContrast: 0.38,
        dyeDensity: 0.28,
        colorCrosstalk: 0.38,
        highlightRolloff: 0.78, // Increase 0.75 -> 0.78, softer highlight transition
        shadowLift: 0.58, // Increased 0.55 -> 0.58, extremely wide shadow tolerance
        printWarmth: 0.85, // Increase 0.82 -> 0.85, more obvious warmth in the dark areas
        // Portra is optimized for skin tone and responds particularly softly to the red-sensitive layer.
        layerSpeeds: SIMD3<Float>(0.96, 1.0, 1.03),
        layerCrossovers: SIMD3<Float>(0.25, 0.55, 0.88),
        adjacencyStrength: 0.2,
        // Portra: "The world's finest grain 400 speed film"
        grainRoughness: 0.75, // Decrease 0.80 -> 0.75
        halationSpreadScale: 1.0,
        halationThresholdOffset: 0.0,
        cineToneIntensity: 0.80, // Portrait preset, the effect is natural and soft
        grainIntensity: 0.22, // Decrease 0.25 -> 0.22, very fine particles
        halationIntensity: 0.22,
        // Portra's halo is warm and soft, with an orange-yellow tone
        halationTintCore: SIMD3<Float>(1.0, 0.95, 0.85),
        halationTintMid: SIMD3<Float>(1.0, 0.50, 0.25),
        halationTintEdge: SIMD3<Float>(0.90, 0.40, 0.15),
        halationStrength: 0.85,
        // Portrait Matrix: Finely optimize skin color, natural transition between red and yellow, warmer gray in dark areas
        channelMixerRed: SIMD3<Float>(0.96, 0.04, 0.0), // Red and yellow, more natural
        channelMixerGreen: SIMD3<Float>(0.10, 0.88, 0.02), // Green mixed with more red, warm tone
        channelMixerBlue: SIMD3<Float>(0.0, 0.08, 0.92) // Blue is mixed with green, reducing the cold tone, and the dark parts are not bluish.
    )

    /// Kodak Gold 200 - Classic consumer grade negative film
    /// Features: Iconic golden warm tone, full color, moderate graininess, excellent performance in sunlight, yellowish mid-tone
    /// Commonly used for: travel, daily records, family photography
    /// Halo characteristics: Distinctive warm gold/orange halo
    /// [Physical Correction]: Although Gold is a civilian roll, the negative characteristics still retain dark details.
    static let kodakGold200 = FilmPreset(
        name: "Kodak Gold 200",
        negativeExposure: 0.0,
        developmentGamma: 0.55,
        printContrast: 0.48,
        dyeDensity: 0.38,
        colorCrosstalk: 0.45,
        highlightRolloff: 0.62, // Increase 0.60 -> 0.62, civilian volume highlights are slightly softer
        shadowLift: 0.38, // Increase 0.35 -> 0.38, negative shadow details
        printWarmth: 0.90, // Improved 0.88 -> 0.90, extremely strong "Kodak Yellow"
        // The grain size of civilian rolls is slightly coarser and the tolerance is slightly lower.
        layerSpeeds: SIMD3<Float>(0.95, 1.0, 1.05),
        layerCrossovers: SIMD3<Float>(0.22, 0.52, 0.82),
        adjacencyStrength: 0.25,
        // Civil rolls, coarser particles
        grainRoughness: 1.25,
        halationSpreadScale: 1.15,
        halationThresholdOffset: -0.05,
        cineToneIntensity: 0.75, // Civil roll, classic Kodak yellow effect
        grainIntensity: 0.45,
        halationIntensity: 0.28,
        // classic golden glow
        halationTintCore: SIMD3<Float>(1.0, 0.92, 0.82),
        halationTintMid: SIMD3<Float>(1.0, 0.45, 0.15),
        halationTintEdge: SIMD3<Float>(0.90, 0.35, 0.10),
        halationStrength: 0.9,
        // Warm tone matrix: The middle tone is obviously yellowish, and the green is mixed with red (yellow-green)
        channelMixerRed: SIMD3<Float>(1.0, 0.0, 0.0),
        channelMixerGreen: SIMD3<Float>(0.12, 0.88, 0.0), // Enhanced Green->Red Mix, "Kodak Yellow"
        channelMixerBlue: SIMD3<Float>(0.0, 0.10, 0.90) // Mix blue with green to reduce the cold tone
    )

    /// Kodak Ektar 100 - Very fine grain color negative film
    /// Features: extremely fine particles, bright colors, high saturation, strong contrast
    /// Commonly used in: landscapes, architecture, products, scenes requiring high saturation
    /// Halo characteristics: low-sensitivity film, weak halo, neutral red color
    /// [Physical Correction]: Although Ektar has high contrast, it still retains dark details as a negative film
    static let kodakEktar100 = FilmPreset(
        name: "Kodak Ektar 100",
        negativeExposure: -0.05,
        developmentGamma: 0.65, // high contrast
        printContrast: 0.55, // Reduce 0.60 -> 0.55 to avoid darkness in the dark area
        dyeDensity: 0.55, // Reduce 0.65 -> 0.55, high saturation but not excessive
        colorCrosstalk: 0.45,
        highlightRolloff: 0.50, // Highlights are hard
        shadowLift: 0.30, // Increase 0.20 -> 0.30, basic characteristics of negative film
        printWarmth: 0.70,
        // Low sensitivity film, silver salt crystals are small and uniform
        layerSpeeds: SIMD3<Float>(0.98, 1.0, 1.02),
        layerCrossovers: SIMD3<Float>(0.2, 0.5, 0.85),
        adjacencyStrength: 0.15,
        // Ektar: Known as the finest-grained negative film in the world
        grainRoughness: 0.60,
        // Extremely difficult to produce halo
        halationSpreadScale: 0.8,
        halationThresholdOffset: 0.1,
        cineToneIntensity: 0.85, // Bright scenery, high saturation effect
        // Default effect intensity: very fine grain, weak halo
        grainIntensity: 0.18,
        halationIntensity: 0.15,
        // Ektar has a weak halo and a neutral color
        halationTintCore: SIMD3<Float>(1.0, 0.96, 0.92),
        halationTintMid: SIMD3<Float>(0.98, 0.38, 0.18),
        halationTintEdge: SIMD3<Float>(0.90, 0.45, 0.22),
        halationStrength: 0.6, // low halo
        // Ektar Matrix: Enhanced Blue-Red Separation, a Landscape Tool
        channelMixerRed: SIMD3<Float>(1.05, -0.05, 0.0), // Increase red purity
        channelMixerGreen: SIMD3<Float>(0.0, 1.0, 0.0),
        channelMixerBlue: SIMD3<Float>(0.0, -0.05, 1.05) // Increase blue purity
    )

    /// Fuji Pro 400H – A favorite among wedding photographers
    /// Features: Soft highlights, natural pinkish skin tone, overall cool tone, rich layers
    /// Discontinued, but has a unique style and is often simulated digitally
    /// Halo characteristics: Soft pink halo, very dreamy
    /// [Physical Correction]: 400H is known for its extremely soft transitions and dark details
    static let fujiPro400H = FilmPreset(
        name: "Fuji Pro 400H",
        negativeExposure: 0.15,
        developmentGamma: 0.42,
        printContrast: 0.35, // Reduce 0.4 -> 0.35, 400H contrast is very low
        dyeDensity: 0.25, // Reduce 0.32 -> 0.25, 400H dye density is very low
        colorCrosstalk: 0.35,
        highlightRolloff: 0.8,
        shadowLift: 0.52, // Increase 0.42 -> 0.52, 400H extremely soft dark areas
        printWarmth: 0.53,
        // 400H is known for its ultra-soft highlight transitions
        layerSpeeds: SIMD3<Float>(0.92, 1.0, 1.05),
        layerCrossovers: SIMD3<Float>(0.3, 0.6, 0.92),
        adjacencyStrength: 0.18,
        // Delicate and soft
        grainRoughness: 0.90,
        // Extremely dreamy soft light
        halationSpreadScale: 1.25,
        halationThresholdOffset: 0.0,
        cineToneIntensity: 0.75, // Cool-toned portrait, soft and dreamy
        // Default effect intensity: fine particles, soft dreamy halo
        grainIntensity: 0.30,
        halationIntensity: 0.25,
        // 400H halo is pinkish, very soft and dreamy
        halationTintCore: SIMD3<Float>(1.0, 0.96, 0.98),
        halationTintMid: SIMD3<Float>(0.98, 0.35, 0.38),
        halationTintEdge: SIMD3<Float>(0.92, 0.45, 0.48),
        halationStrength: 0.8,
        // standard matrix
        channelMixerRed: SIMD3<Float>(1.0, 0.0, 0.0),
        channelMixerGreen: SIMD3<Float>(0.0, 1.0, 0.0),
        channelMixerBlue: SIMD3<Float>(0.0, 0.0, 1.0)
    )

    /// CineStill 800T - Still photography film modified from film negative
    /// Features: Signature red glow after removing Rem-Jet layer, tungsten color, high sensitivity
    /// Commonly used in: night street photography, neon lights, artificial light environments
    /// Halo Properties: No Rem-Jet anti-halo layer! The glow is very intense and has the signature deep red color
    /// [Physical correction]: Based on Vision3 500T, retain the dark characteristics of the negative, push one stop to 800
    static let cinestill800T = FilmPreset(
        name: "CineStill 800T",
        negativeExposure: 0.0,
        developmentGamma: 0.55,
        printContrast: 0.48,
        dyeDensity: 0.38,
        colorCrosstalk: 0.60,
        highlightRolloff: 0.55, // Increase 0.50 -> 0.55, night scene highlights need a soft transition
        shadowLift: 0.48, // Improved 0.42 -> 0.48, based on Vision3’s dark features
        printWarmth: 0.65, // Increase 0.60 -> 0.65, tungsten lamp balance is more obvious
        // 800T is based on Vision3 500T and is pushed to the next level.
        layerSpeeds: SIMD3<Float>(0.90, 1.0, 1.10),
        layerCrossovers: SIMD3<Float>(0.18, 0.48, 0.82),
        adjacencyStrength: 0.40,
        // High sensitivity + RemJet removal, rough grain
        grainRoughness: 1.5,
        // No Rem-Jet, extremely diffuse red halo, easy to trigger
        halationSpreadScale: 2.0, // Improved 1.8 -> 2.0, more exaggerated diffusion
        halationThresholdOffset: -0.18, // Reduce -0.15 -> -0.18, easier to trigger
        cineToneIntensity: 0.95, // Iconic night scene style with strong effect
        grainIntensity: 0.55,
        halationIntensity: 0.70, // Improved 0.65 -> 0.70, iconic strong halo
        // CineStill Halo: Iconic pure red scattering
        halationTintCore: SIMD3<Float>(1.0, 0.65, 0.45), // Slightly softer core
        halationTintMid: SIMD3<Float>(1.0, 0.0, 0.0), // Pure red in the middle (iconic)
        halationTintEdge: SIMD3<Float>(0.85, 0.0, 0.05), // edge crimson
        halationStrength: 2.0, // Improved 1.8 -> 2.0, extremely strong halo
        // Night scene matrix: tungsten light balance, cool background
        channelMixerRed: SIMD3<Float>(1.0, 0.0, 0.0),
        channelMixerGreen: SIMD3<Float>(0.0, 0.95, 0.05),
        channelMixerBlue: SIMD3<Float>(0.0, 0.02, 0.98) // Blue is slightly mixed with green to reduce excessive coldness
    )

    /// No Film Effect - Default state for activePreset (no Film simulation is applied)
    static let none = FilmPreset(
        name: "None",
        negativeExposure: 0,
        developmentGamma: 0.55,
        printContrast: 0.50,
        dyeDensity: 0.50,
        colorCrosstalk: 0.0,
        highlightRolloff: 0.50,
        shadowLift: 0.0,
        printWarmth: 0.50,
        layerSpeeds: SIMD3<Float>(1.0, 1.0, 1.0),
        layerCrossovers: SIMD3<Float>(0.3, 0.6, 0.9),
        adjacencyStrength: 0.0,
        grainRoughness: 1.0,
        halationSpreadScale: 1.0,
        halationThresholdOffset: 0.0,
        cineToneIntensity: 0.0, // No effect
        // Default effect intensity: no effect
        grainIntensity: 0.0,
        halationIntensity: 0.0,
        halationTintCore: SIMD3<Float>(1.0, 1.0, 1.0),
        halationTintMid: SIMD3<Float>(1.0, 0.5, 0.2),
        halationTintEdge: SIMD3<Float>(1.0, 0, 0),
        halationStrength: 0,
        channelMixerRed: SIMD3<Float>(1.0, 0.0, 0.0),
        channelMixerGreen: SIMD3<Float>(0.0, 1.0, 0.0),
        channelMixerBlue: SIMD3<Float>(0.0, 0.0, 1.0)
    )

    /// Kodak Tri-X 400 - The legendary black and white film
    /// Features: High contrast, strong graininess, strong documentary feel, high-light "explosion" feeling, red light sensitivity
    /// Commonly used in: photojournalism, street photography, documentary photography
    /// Halo characteristics: The halo of black and white film usually appears as a glow around highlights without color bleeding (pure white/gray)
    static let kodakTriX400 = FilmPreset(
        name: "Kodak Tri-X 400",
        negativeExposure: 0.0,
        developmentGamma: 0.78,
        printContrast: 0.75,
        dyeDensity: 0.90,
        colorCrosstalk: 0.0,
        highlightRolloff: 0.28, // Lower 0.30 -> 0.28, harder highlight cutoff
        shadowLift: 0.10, // Increase 0.08 -> 0.10, black and white negative film still has basic dark details
        printWarmth: 0.5,
        // Tri-X spectral response: extremely sensitive to red light (similar to adding a red filter)
        layerSpeeds: SIMD3<Float>(0.80, 1.0, 1.20), // More extreme red light sensitivity
        layerCrossovers: SIMD3<Float>(0.3, 0.5, 0.7),
        adjacencyStrength: 0.90, // Increase 0.85 -> 0.90, extremely strong edge effect
        // Classic coarse grain black and white
        grainRoughness: 1.65, // Improved 1.6 -> 1.65
        halationSpreadScale: 1.1,
        halationThresholdOffset: -0.05,
        cineToneIntensity: 1.0, // Hard black and white, strong effect
        grainIntensity: 0.52, // Increase 0.50 -> 0.52, more obvious graininess
        halationIntensity: 0.22,
        // Black and white halo: pure glow
        halationTintCore: SIMD3<Float>(1.0, 1.0, 1.0),
        halationTintMid: SIMD3<Float>(0.75, 0.75, 0.75),
        halationTintEdge: SIMD3<Float>(0.35, 0.35, 0.35),
        halationStrength: 0.7,
        // Tri-X spectral response: extremely sensitive to red light, darkening blue sky and green
        // Red has a higher weight and blue has a lower weight
        channelMixerRed: SIMD3<Float>(0.55, 0.40, 0.05), // Enhance red light response
        channelMixerGreen: SIMD3<Float>(0.55, 0.40, 0.05),
        channelMixerBlue: SIMD3<Float>(0.55, 0.40, 0.05)
    )

    /// Ilford HP5 Plus 400 - Classic British black and white film
    /// Features: Extremely high tolerance, fine grains, soft and elegant tones, rich layers
    /// Commonly used for: portraits, scenery, architecture, scenes that require delicate transitions
    /// Halo characteristics: black and white glow, soft and natural
    static let ilfordHP5 = FilmPreset(
        name: "Ilford HP5 Plus 400",
        negativeExposure: 0.05, // Slightly overexpose to preserve shadows
        developmentGamma: 0.52, // Lower contrast, softer transitions
        printContrast: 0.48, // soft contrast
        dyeDensity: 0.65, // Silver salt density is moderate
        colorCrosstalk: 0.0, // Black and white without color crosstalk
        highlightRolloff: 0.72, // Very soft highlight transition
        shadowLift: 0.38, // Rich details in dark areas
        printWarmth: 0.5, // Pure black and white (neutral)
        // HP5 spectral response: relatively balanced, slightly sensitive to green light
        layerSpeeds: SIMD3<Float>(0.95, 1.0, 1.05),
        layerCrossovers: SIMD3<Float>(0.35, 0.55, 0.75),
        adjacencyStrength: 0.35, // Edge effect is moderate and soft
        // HP5: Delicate black and white
        grainRoughness: 1.1,
        halationSpreadScale: 1.05,
        halationThresholdOffset: 0.0,
        cineToneIntensity: 1.0, // Soft black and white, elegant effect
        // Default effect intensity: fine grain, weak halo (soft black and white)
        grainIntensity: 0.32,
        halationIntensity: 0.12,
        // Black and white halo: pure glow, soft and natural
        halationTintCore: SIMD3<Float>(1.0, 1.0, 1.0),
        halationTintMid: SIMD3<Float>(0.70, 0.70, 0.70),
        halationTintEdge: SIMD3<Float>(0.40, 0.40, 0.40),
        halationStrength: 0.35,
        // HP5 spectral response: balanced full color response, slightly sensitive to green light
        // More natural grayscale transition, suitable for portraits and landscapes
        channelMixerRed: SIMD3<Float>(0.32, 0.58, 0.10),
        channelMixerGreen: SIMD3<Float>(0.32, 0.58, 0.10),
        channelMixerBlue: SIMD3<Float>(0.32, 0.58, 0.10)
    )

    /// Fuji Velvia 50 - legendary scenery reversal film (feature film)
    /// Features: Extremely high saturation, extremely high contrast, amazing clarity, almost no grain, "Fuji Green"
    /// Commonly used for: landscape, nature, macro, commercial product photography
    /// Differences: Unlike negative film, its latitude is extremely narrow and dark areas tend to go black, but the colors are extremely impactful.
    /// Halo characteristics: The positive film base is thicker, the halo is very weak and controlled, showing a cool purple tone
    static let fujiVelvia50 = FilmPreset(
        name: "Fuji Velvia 50",
        negativeExposure: -0.15,
        developmentGamma: 0.85,
        printContrast: 0.75,
        dyeDensity: 0.92, // Increase 0.90 -> 0.92, ultimate saturation
        colorCrosstalk: 0.75, // Increase 0.70 -> 0.75, color penetration is stronger
        highlightRolloff: 0.25, // Decrease 0.30 -> 0.25, positive film highlight cutoff is harder
        shadowLift: 0.02, // Decrease 0.05 -> 0.02, there is almost no detail in the dark parts of the feature film
        printWarmth: 0.38, // Decrease 0.40 -> 0.38, more obvious cold/magenta tendency
        // Very slow film (ISO 50), very fine grain
        layerSpeeds: SIMD3<Float>(0.95, 1.0, 1.05),
        layerCrossovers: SIMD3<Float>(0.3, 0.5, 0.7),
        adjacencyStrength: 0.90, // Increase 0.85 -> 0.90, the positive film edge effect is extremely strong
        // ISO 50 positive film, extremely delicate
        grainRoughness: 0.35, // Decrease 0.4 -> 0.35
        halationSpreadScale: 0.6,
        halationThresholdOffset: 0.15,
        cineToneIntensity: 0.95, // Extremely high saturation positive film, the effect is extremely impactful
        grainIntensity: 0.10, // Reduce 0.12 -> 0.10, almost no particles
        halationIntensity: 0.10,
        // The halo is weak and the color is cold purple
        halationTintCore: SIMD3<Float>(0.90, 0.90, 1.0),
        halationTintMid: SIMD3<Float>(0.60, 0.20, 0.50),
        halationTintEdge: SIMD3<Float>(0.30, 0.10, 0.40),
        halationStrength: 0.3,
        // Velvia matrix: aggressive color, iconic "Fuji Green"
        // Red is mixed with blue (purple), green is greatly mixed with blue (verdant), and blue is enhanced
        channelMixerRed: SIMD3<Float>(0.90, -0.08, 0.18), // Stronger purple-red tendency
        channelMixerGreen: SIMD3<Float>(0.18, 0.75, 0.20), // Radical "Fuji Green"
        channelMixerBlue: SIMD3<Float>(0.0, 0.08, 1.08) // Deep blue, beyond the standard range
    )

    /// Agfa Vista 400 - Classic "German" color
    /// Features: Rich and thick colors, iconic bright red (Agfa Red), deep blue
    /// Commonly used in: street photography, humanistic documentary, scenes that require color impact
    /// Differences: Unlike Kodak’s warm yellow and Fuji’s green, Agfa presents a unique depth and red tendency
    /// Halo characteristics: The halo is warm red, but deeper than Kodak
    /// [Physical Correction]: Although Agfa has rich colors, it still retains dark details as a negative film
    static let agfaVista400 = FilmPreset(
        name: "Agfa Vista 400",
        negativeExposure: 0.0,
        developmentGamma: 0.58,
        printContrast: 0.52, // Increase 0.50 -> 0.52, Agfa contrast is slightly higher
        dyeDensity: 0.55, // Increase 0.52 -> 0.55, richer colors
        colorCrosstalk: 0.55, // Increase 0.52 -> 0.55 for stronger color penetration
        highlightRolloff: 0.55,
        shadowLift: 0.35,
        printWarmth: 0.58, // Decrease 0.60 -> 0.58, Agfa is less warm than Kodak, more neutral
        // The red layer of Agfa is very sensitive and unique
        layerSpeeds: SIMD3<Float>(1.08, 1.0, 0.92), // More extreme red layer sensitivity
        layerCrossovers: SIMD3<Float>(0.25, 0.55, 0.85),
        adjacencyStrength: 0.35,
        // Typical 400 degree civilian roll pellets
        grainRoughness: 1.15,
        halationSpreadScale: 1.0,
        halationThresholdOffset: 0.0,
        cineToneIntensity: 0.80, // Rich German flavor, iconic Agfa Red
        grainIntensity: 0.42,
        halationIntensity: 0.26,
        // Agfa Halo: Deep red/orange, darker than Kodak
        halationTintCore: SIMD3<Float>(1.0, 0.88, 0.82),
        halationTintMid: SIMD3<Float>(0.98, 0.28, 0.08), // deeper red
        halationTintEdge: SIMD3<Float>(0.85, 0.18, 0.05),
        halationStrength: 0.85,
        // Agfa Matrix: Iconic "Agfa Red", deep blue
        channelMixerRed: SIMD3<Float>(1.08, -0.08, 0.0), // Extremely enhanced red purity
        channelMixerGreen: SIMD3<Float>(0.05, 0.90, 0.05),
        channelMixerBlue: SIMD3<Float>(0.0, 0.12, 0.88) // Blue is mixed with more cyan, giving it a deeper feel
    )

    /// Polaroid 600 - retro instant imaging style
    /// Features: Low contrast, faded look, creamy highlights, unique color cast
    /// Commonly used for: creating a nostalgic atmosphere, mood films, still lifes
    /// Points of difference: Extremely high shadow lift and unique chemical development color cast, completely different from other negative films
    /// Halo characteristics: soft and diffuse, usually with a chemical yellow-green tint
    static let polaroid600 = FilmPreset(
        name: "Polaroid 600",
        negativeExposure: 0.1, // Slightly overexposed to simulate the buttery feel of Polaroid
        developmentGamma: 0.40, // Low Gamma, smooth curve
        printContrast: 0.35, // low contrast
        dyeDensity: 0.45,
        colorCrosstalk: 0.30,
        highlightRolloff: 0.90, // Extremely soft highlight roll-off
        shadowLift: 0.60, // Significant enhancement of dark areas, resulting in a "faded" effect
        printWarmth: 0.75, // Obvious warm tone, with a bit of retro yellow
        // Photosensitive properties of instant photo paper
        layerSpeeds: SIMD3<Float>(0.98, 1.02, 1.0),
        layerCrossovers: SIMD3<Float>(0.3, 0.5, 0.7),
        adjacencyStrength: 0.10, // soft edges
        // Instant imaging emulsion with special graininess
        grainRoughness: 0.95,
        // Extremely soft glow
        halationSpreadScale: 1.4,
        halationThresholdOffset: -0.1,
        cineToneIntensity: 0.65, // Retro Polaroid, faded effect
        // Default effect intensity: moderate grain, soft halo (retro Polaroid)
        grainIntensity: 0.35,
        halationIntensity: 0.20,
        // Polaroid Halo: Yellow-Green Tone
        halationTintCore: SIMD3<Float>(1.0, 0.98, 0.90),
        halationTintMid: SIMD3<Float>(0.80, 0.75, 0.50), // Yellow green
        halationTintEdge: SIMD3<Float>(0.50, 0.45, 0.30),
        halationStrength: 0.6,
        // Polaroid Matrix: Simulate chemical color cast
        channelMixerRed: SIMD3<Float>(0.90, 0.10, 0.0),
        channelMixerGreen: SIMD3<Float>(0.0, 0.95, 0.05),
        channelMixerBlue: SIMD3<Float>(0.0, 0.05, 0.90) // Slightly yellowish
    )

    static let all: [FilmPreset] = [
        .kodakPortra400, // The first choice for portraits, the most lovable
        .kodakGold200, // Warm and retro, versatile for everyday use
        .fujiEterna, // Japanese style is light and cinematic
        .kodakVision3, // classic film negative
        .cinestill800T, // Night scene halo artifact
        .agfaVista400, // Rich German flavor
        .polaroid600, // Retro Polaroid
        .kodakEktar100, // bright scenery
        .fujiPro400H, // cool portrait
        .kodak5219, // high contrast film reel
        .fujiVelvia50, // High contrast positive film
        .kodakTriX400, // hard black and white
        .ilfordHP5, // Soft black and white
    ]

    func copy(withName newName: String, author: String? = nil) -> FilmPreset {
        FilmPreset(
            name: newName,
            author: author ?? self.author,
            negativeExposure: negativeExposure,
            developmentGamma: developmentGamma,
            printContrast: printContrast,
            dyeDensity: dyeDensity,
            colorCrosstalk: colorCrosstalk,
            highlightRolloff: highlightRolloff,
            shadowLift: shadowLift,
            printWarmth: printWarmth,
            layerSpeeds: layerSpeeds,
            layerCrossovers: layerCrossovers,
            adjacencyStrength: adjacencyStrength,
            grainRoughness: grainRoughness,
            halationSpreadScale: halationSpreadScale,
            halationThresholdOffset: halationThresholdOffset,
            cineToneIntensity: cineToneIntensity,
            grainIntensity: grainIntensity,
            halationIntensity: halationIntensity,
            halationTintCore: halationTintCore,
            halationTintMid: halationTintMid,
            halationTintEdge: halationTintEdge,
            halationStrength: halationStrength,
            channelMixerRed: channelMixerRed,
            channelMixerGreen: channelMixerGreen,
            channelMixerBlue: channelMixerBlue
        )
    }
}
