import CoreImage

/// ISO sensitivity presets based on real film data
enum ISOPreset {
    case iso50 // Ultra-fine grain (Velvia 50, Ektar 100)
    case iso100 // Fine grain (Portra 160, Provia 100)
    case iso400 // Standard grain (Portra 400, Superia 400)
    case iso800 // Medium grain (Portra 800)
    case iso1600 // Coarse grain (Natura 1600)
    case iso3200 // Very coarse grain (push processing)

    /// RMS granularity values based on Kodak/Fuji datasheets, scaled up for visual effect
    var rmsGranularity: Float {
        // The original RMS values are too small, so they are scaled into a visible range here.
        // Digitized grain from actual film scans needs higher intensity to read correctly.
        switch self {
        case .iso50: return 0.15
        case .iso100: return 0.20
        case .iso400: return 0.30
        case .iso800: return 0.40
        case .iso1600: return 0.55
        case .iso3200: return 0.75
        }
    }

    /// Selwyn granularity constant
    var selwynConstant: Float {
        // G = RMS x sqrt(measurement area), normalized here to a 48 um scan aperture.
        rmsGranularity * 6.93 // √48
    }
}

struct FilmEmulationSnapshot: Equatable, Codable {
    /// === Unified film emulation parameters ===
    var cineToneIntensity: Float // Overall film emulation intensity

    // === Film preset parameters (flattened) ===
    var negativeExposure: Float
    var developmentGamma: Float
    var printContrast: Float
    var dyeDensity: Float
    var colorCrosstalk: Float
    var highlightRolloff: Float
    var shadowLift: Float
    var printWarmth: Float

    var layerSpeeds: SIMD3<Float>
    var layerCrossovers: SIMD3<Float>
    var adjacencyStrength: Float

    var grainRoughness: Float
    var halationSpreadScale: Float
    var halationThresholdOffset: Float

    var halationTintCore: SIMD3<Float>
    var halationTintMid: SIMD3<Float>
    var halationTintEdge: SIMD3<Float>
    var halationStrength: Float

    var channelMixerRed: SIMD3<Float>
    var channelMixerGreen: SIMD3<Float>
    var channelMixerBlue: SIMD3<Float>

    // === Optical effect parameters ===
    var halationIntensity: Float
    var bloomIntensity: Float
    var fogIntensity: Float
    var vignetteIntensity: Float
    var lightLeakIntensity: Float
    var dustIntensity: Float
    var scratchesIntensity: Float
    var hairIntensity: Float

    /// === Physical effect parameters ===
    var grainIntensity: Float

    /// === Capture parameters used for physical coupling ===
    var captureISO: Float // Actual ISO used when shooting
    var captureAperture: Float // Aperture value (f-number)
    var captureColorTemperature: Float // Color temperature (K)
    var captureExposureBias: Float // Exposure compensation (EV)
    var captureFocalLength: Float // Equivalent focal length (mm, 35mm equivalent)
    var captureCameraType: CameraType // Camera type

    // === Custom parameter overrides (optional) ===
    // Used by the advanced editing mode to override the default physically linked values.

    // Development / Printing - REMOVED (now in main params)

    var sat: Float? // Additional saturation adjustment
    var vibrance: Float? // Vibrance adjustment
    var exposure: Float? // Exposure adjustment (EV)
    var contrast: Float? // Contrast adjustment (0.0-1.0, 0.5 is neutral)
    var temp: Float? // Color temperature adjustment (-1.0 ~ 1.0)
    var tint: Float? // Tint adjustment (-1.0 ~ 1.0, Green/Magenta)
    var hue: Float? // Hue adjustment (-1.0 ~ 1.0)
    var highlights: Float? // Highlight adjustment (-1.0 ~ 1.0)
    var shadows: Float? // Shadow adjustment (-1.0 ~ 1.0)
    var whites: Float? // White point adjustment (-1.0 ~ 1.0)
    var blacks: Float? // Black point adjustment (-1.0 ~ 1.0)

    // Effects
    var texture: Float?
    var clarity: Float?
    var dehaze: Float?
    var sharpening: Float?

    /// Grain
    var grainSize: Float? // Grain physical size scale factor (defaults to 1.0)

    // Halation
    var halationThreshold: Float?
    var halationSpread: Float?
    var halationWarmth: Float?
    var halationColor: SIMD3<Float>?

    // Bloom
    var bloomThreshold: Float?
    var bloomSpread: Float?
    var bloomWarmth: Float?

    // Fog
    var fogColor: SIMD3<Float>?
    var fogContrast: Float?

    // Light Leak
    var lightLeakThreshold: Float?
    var lightLeakSpread: Float?
    var lightLeakWarmth: Float?
    var lightLeakColor: SIMD3<Float>? // Custom light leak color
    var lightLeakPosition: Float? // Light leak position preference (0-1: left to right, 2: corner, 3: center)
    var lightLeakSaturation: Float? // Light leak saturation (0.5-2.0)
    var lightLeakContrast: Float? // Light leak contrast (0-1)
    var lightLeakRandomTrigger: Int? // Random trigger counter

    // Vignette
    var vignetteSoftness: Float?
    var vignetteRoundness: Float?

    /// Preset ID for Restoration
    var presetID: String?

    /// Camera type enum
    enum CameraType: String, Equatable, Codable {
        case ultraWide // Ultra-wide (13mm equivalent)
        case wide // Wide / main camera (24-26mm equivalent)
        case telephoto // Telephoto (77mm+ equivalent)
        case front // Front camera
    }

    init(
        cineToneIntensity: Float = 0,
        // Preset params
        negativeExposure: Float = 0,
        developmentGamma: Float = 0.5,
        printContrast: Float = 0.5,
        dyeDensity: Float = 0.5,
        colorCrosstalk: Float = 0,
        highlightRolloff: Float = 0.5,
        shadowLift: Float = 0,
        printWarmth: Float = 0.5,
        layerSpeeds: SIMD3<Float> = SIMD3(1, 1, 1),
        layerCrossovers: SIMD3<Float> = SIMD3(0.3, 0.6, 0.9),
        adjacencyStrength: Float = 0,
        grainRoughness: Float = 1,
        halationSpreadScale: Float = 1,
        halationThresholdOffset: Float = 0,
        halationTintCore: SIMD3<Float> = SIMD3(1, 1, 1),
        halationTintMid: SIMD3<Float> = SIMD3(1, 0.5, 0.2),
        halationTintEdge: SIMD3<Float> = SIMD3(1, 0, 0),
        halationStrength: Float = 1,
        channelMixerRed: SIMD3<Float> = SIMD3(1, 0, 0),
        channelMixerGreen: SIMD3<Float> = SIMD3(0, 1, 0),
        channelMixerBlue: SIMD3<Float> = SIMD3(0, 0, 1),

        halationIntensity: Float = 0,
        bloomIntensity: Float = 0,
        fogIntensity: Float = 0,
        vignetteIntensity: Float = 0,
        lightLeakIntensity: Float = 0,
        dustIntensity: Float = 0,
        scratchesIntensity: Float = 0,
        hairIntensity: Float = 0,
        grainIntensity: Float = 0,
        captureISO: Float = 400,
        captureAperture: Float = 2.8,
        captureColorTemperature: Float = 5500,
        captureExposureBias: Float = 0,
        captureFocalLength: Float = 26,
        captureCameraType: CameraType = .wide,

        // Custom override parameters
        sat: Float? = nil,
        vibrance: Float? = nil,
        exposure: Float? = nil,
        contrast: Float? = nil,
        temp: Float? = nil,
        tint: Float? = nil,
        hue: Float? = nil,
        highlights: Float? = nil,
        shadows: Float? = nil,
        whites: Float? = nil,
        blacks: Float? = nil,
        texture: Float? = nil,
        clarity: Float? = nil,
        dehaze: Float? = nil,
        sharpening: Float? = nil,
        grainSize: Float? = nil,
        halationThreshold: Float? = nil,
        halationSpread: Float? = nil,
        halationWarmth: Float? = nil,
        halationColor: SIMD3<Float>? = nil,
        bloomThreshold: Float? = nil,
        bloomSpread: Float? = nil,
        bloomWarmth: Float? = nil,
        fogColor: SIMD3<Float>? = nil,
        fogContrast: Float? = nil,
        lightLeakThreshold: Float? = nil,
        lightLeakSpread: Float? = nil,
        lightLeakWarmth: Float? = nil,
        lightLeakColor: SIMD3<Float>? = nil,
        lightLeakPosition: Float? = nil,
        lightLeakSaturation: Float? = nil,
        lightLeakContrast: Float? = nil,
        lightLeakRandomTrigger: Int? = nil,
        vignetteSoftness: Float? = nil,
        vignetteRoundness: Float? = nil,

        presetID: String? = nil
    ) {
        self.cineToneIntensity = cineToneIntensity

        self.negativeExposure = negativeExposure
        self.developmentGamma = developmentGamma
        self.printContrast = printContrast
        self.dyeDensity = dyeDensity
        self.colorCrosstalk = colorCrosstalk
        self.highlightRolloff = highlightRolloff
        self.shadowLift = shadowLift
        self.printWarmth = printWarmth
        self.layerSpeeds = layerSpeeds
        self.layerCrossovers = layerCrossovers
        self.adjacencyStrength = adjacencyStrength
        self.grainRoughness = grainRoughness
        self.halationSpreadScale = halationSpreadScale
        self.halationThresholdOffset = halationThresholdOffset
        self.halationTintCore = halationTintCore
        self.halationTintMid = halationTintMid
        self.halationTintEdge = halationTintEdge
        self.halationStrength = halationStrength
        self.channelMixerRed = channelMixerRed
        self.channelMixerGreen = channelMixerGreen
        self.channelMixerBlue = channelMixerBlue

        self.halationIntensity = halationIntensity
        self.bloomIntensity = bloomIntensity
        self.fogIntensity = fogIntensity
        self.vignetteIntensity = vignetteIntensity
        self.lightLeakIntensity = lightLeakIntensity
        self.dustIntensity = dustIntensity
        self.scratchesIntensity = scratchesIntensity
        self.hairIntensity = hairIntensity
        self.grainIntensity = grainIntensity
        self.captureISO = captureISO
        self.captureAperture = captureAperture
        self.captureColorTemperature = captureColorTemperature
        self.captureExposureBias = captureExposureBias
        self.captureFocalLength = captureFocalLength
        self.captureCameraType = captureCameraType

        self.sat = sat
        self.vibrance = vibrance
        self.exposure = exposure
        self.contrast = contrast
        self.temp = temp
        self.tint = tint
        self.hue = hue
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
        self.texture = texture
        self.clarity = clarity
        self.dehaze = dehaze
        self.sharpening = sharpening
        self.grainSize = grainSize
        self.halationThreshold = halationThreshold
        self.halationSpread = halationSpread
        self.halationWarmth = halationWarmth
        self.halationColor = halationColor
        self.bloomThreshold = bloomThreshold
        self.bloomSpread = bloomSpread
        self.bloomWarmth = bloomWarmth
        self.fogColor = fogColor
        self.fogContrast = fogContrast
        self.lightLeakThreshold = lightLeakThreshold
        self.lightLeakSpread = lightLeakSpread
        self.lightLeakWarmth = lightLeakWarmth
        self.lightLeakColor = lightLeakColor
        self.lightLeakPosition = lightLeakPosition
        self.lightLeakSaturation = lightLeakSaturation
        self.lightLeakContrast = lightLeakContrast
        self.lightLeakRandomTrigger = lightLeakRandomTrigger
        self.vignetteSoftness = vignetteSoftness
        self.vignetteRoundness = vignetteRoundness

        self.presetID = presetID
    }

    /// Convenience initializer to create snapshot from a preset
    init(
        preset: FilmPreset?,
        cineToneIntensity: Float = 0,

        // Overrides for Preset Parameters
        negativeExposure: Float? = nil,
        developmentGamma: Float? = nil,
        printContrast: Float? = nil,
        dyeDensity: Float? = nil,
        colorCrosstalk: Float? = nil,
        highlightRolloff: Float? = nil,
        shadowLift: Float? = nil,
        printWarmth: Float? = nil,

        // Overrides for physical properties
        layerSpeeds: SIMD3<Float>? = nil,
        layerCrossovers: SIMD3<Float>? = nil,
        adjacencyStrength: Float? = nil,
        grainRoughness: Float? = nil,
        halationSpreadScale: Float? = nil,
        halationThresholdOffset: Float? = nil,
        halationTintCore: SIMD3<Float>? = nil,
        halationTintMid: SIMD3<Float>? = nil,
        halationTintEdge: SIMD3<Float>? = nil,
        halationStrength: Float? = nil,
        channelMixerRed: SIMD3<Float>? = nil,
        channelMixerGreen: SIMD3<Float>? = nil,
        channelMixerBlue: SIMD3<Float>? = nil,

        halationIntensity: Float? = nil,
        bloomIntensity: Float = 0,
        fogIntensity: Float = 0,
        vignetteIntensity: Float = 0,
        lightLeakIntensity: Float = 0,
        dustIntensity: Float = 0,
        scratchesIntensity: Float = 0,
        hairIntensity: Float = 0,
        grainIntensity: Float? = nil,
        captureISO: Float = 400,
        captureAperture: Float = 2.8,
        captureColorTemperature: Float = 5500,
        captureExposureBias: Float = 0,
        captureFocalLength: Float = 26,
        captureCameraType: CameraType = .wide,
        sat: Float? = nil,
        vibrance: Float? = nil,
        exposure: Float? = nil,
        contrast: Float? = nil,
        temp: Float? = nil,
        tint: Float? = nil,
        hue: Float? = nil,
        highlights: Float? = nil,
        shadows: Float? = nil,
        whites: Float? = nil,
        blacks: Float? = nil,
        texture: Float? = nil,
        clarity: Float? = nil,
        dehaze: Float? = nil,
        sharpening: Float? = nil,
        grainSize: Float? = nil,
        halationThreshold: Float? = nil,
        halationSpread: Float? = nil,
        halationWarmth: Float? = nil,
        halationColor: SIMD3<Float>? = nil,
        bloomThreshold: Float? = nil,
        bloomSpread: Float? = nil,
        bloomWarmth: Float? = nil,
        fogColor: SIMD3<Float>? = nil,
        fogContrast: Float? = nil,
        lightLeakThreshold: Float? = nil,
        lightLeakSpread: Float? = nil,
        lightLeakWarmth: Float? = nil,
        lightLeakColor: SIMD3<Float>? = nil,
        lightLeakPosition: Float? = nil,
        lightLeakSaturation: Float? = nil,
        lightLeakContrast: Float? = nil,
        lightLeakRandomTrigger: Int? = nil,
        vignetteSoftness: Float? = nil,
        vignetteRoundness: Float? = nil,
        presetID: String? = nil
    ) {
        self.init(
            cineToneIntensity: cineToneIntensity,
            negativeExposure: negativeExposure ?? preset?.negativeExposure ?? 0,
            developmentGamma: developmentGamma ?? preset?.developmentGamma ?? 0.5,
            printContrast: printContrast ?? preset?.printContrast ?? 0.5,
            dyeDensity: dyeDensity ?? preset?.dyeDensity ?? 0.5,
            colorCrosstalk: colorCrosstalk ?? preset?.colorCrosstalk ?? 0,
            highlightRolloff: highlightRolloff ?? preset?.highlightRolloff ?? 0.5,
            shadowLift: shadowLift ?? preset?.shadowLift ?? 0,
            printWarmth: printWarmth ?? preset?.printWarmth ?? 0.5,
            layerSpeeds: layerSpeeds ?? preset?.layerSpeeds ?? SIMD3(1, 1, 1),
            layerCrossovers: layerCrossovers ?? preset?.layerCrossovers ?? SIMD3(0.3, 0.6, 0.9),
            adjacencyStrength: adjacencyStrength ?? preset?.adjacencyStrength ?? 0,
            grainRoughness: grainRoughness ?? preset?.grainRoughness ?? 1,
            halationSpreadScale: halationSpreadScale ?? preset?.halationSpreadScale ?? 1,
            halationThresholdOffset: halationThresholdOffset ?? preset?.halationThresholdOffset ?? 0,
            halationTintCore: halationTintCore ?? preset?.halationTintCore ?? SIMD3(1, 1, 1),
            halationTintMid: halationTintMid ?? preset?.halationTintMid ?? SIMD3(1, 0.5, 0.2),
            halationTintEdge: halationTintEdge ?? preset?.halationTintEdge ?? SIMD3(1, 0, 0),
            halationStrength: halationStrength ?? preset?.halationStrength ?? 1,
            channelMixerRed: channelMixerRed ?? preset?.channelMixerRed ?? SIMD3(1, 0, 0),
            channelMixerGreen: channelMixerGreen ?? preset?.channelMixerGreen ?? SIMD3(0, 1, 0),
            channelMixerBlue: channelMixerBlue ?? preset?.channelMixerBlue ?? SIMD3(0, 0, 1),
            halationIntensity: halationIntensity ?? preset?.halationIntensity ?? 0,
            bloomIntensity: bloomIntensity,
            fogIntensity: fogIntensity,
            vignetteIntensity: vignetteIntensity,
            lightLeakIntensity: lightLeakIntensity,
            dustIntensity: dustIntensity,
            scratchesIntensity: scratchesIntensity,
            hairIntensity: hairIntensity,
            grainIntensity: grainIntensity ?? preset?.grainIntensity ?? 0,
            captureISO: captureISO,
            captureAperture: captureAperture,
            captureColorTemperature: captureColorTemperature,
            captureExposureBias: captureExposureBias,
            captureFocalLength: captureFocalLength,
            captureCameraType: captureCameraType,
            sat: sat,
            vibrance: vibrance,
            exposure: exposure,
            contrast: contrast,
            temp: temp,
            tint: tint,
            hue: hue,
            highlights: highlights,
            shadows: shadows,
            whites: whites,
            blacks: blacks,
            texture: texture,
            clarity: clarity,
            dehaze: dehaze,
            sharpening: sharpening,
            grainSize: grainSize,
            halationThreshold: halationThreshold,
            halationSpread: halationSpread,
            halationWarmth: halationWarmth,
            halationColor: halationColor,
            bloomThreshold: bloomThreshold,
            bloomSpread: bloomSpread,
            bloomWarmth: bloomWarmth,
            fogColor: fogColor,
            fogContrast: fogContrast,
            lightLeakThreshold: lightLeakThreshold,
            lightLeakSpread: lightLeakSpread,
            lightLeakWarmth: lightLeakWarmth,
            lightLeakColor: lightLeakColor,
            lightLeakPosition: lightLeakPosition,
            lightLeakSaturation: lightLeakSaturation,
            lightLeakContrast: lightLeakContrast,
            lightLeakRandomTrigger: lightLeakRandomTrigger,
            vignetteSoftness: vignetteSoftness,
            vignetteRoundness: vignetteRoundness,
            presetID: presetID ?? preset?.id
        )
    }

    /// Returns the grain preset for the current ISO value.
    /// Uses logarithmic mapping to convert continuous ISO values into discrete presets.
    var grainISOPreset: ISOPreset {
        // ISO range mapping:
        // < 75 -> iso50
        // 75-150 -> iso100
        // 150-600 -> iso400
        // 600-1200 -> iso800
        // 1200-2400 -> iso1600
        // > 2400 -> iso3200
        if captureISO < 75 {
            return .iso50
        } else if captureISO < 150 {
            return .iso100
        } else if captureISO < 600 {
            return .iso400
        } else if captureISO < 1200 {
            return .iso800
        } else if captureISO < 2400 {
            return .iso1600
        } else {
            return .iso3200
        }
    }

    // MARK: - Halation dynamic adjustments based on camera parameters

    /// Calculates the Halation trigger threshold from camera parameters.
    var resolvedHalationThreshold: Float {
        if let custom = halationThreshold { return custom }

        // Base threshold, lowered further so Halation is easier to trigger in scenes like indoor LEDs.
        // This also makes the core red fringe easier to trigger.
        var threshold: Float = 0.22

        // Film physical property adjustment
        threshold += halationThresholdOffset

        // ISO contribution
        let isoStops = log2(max(captureISO, 50) / 400.0)
        threshold -= isoStops * 0.05

        // Exposure bias contribution
        threshold -= captureExposureBias * 0.03

        return min(max(threshold, 0.08), 0.65)
    }

    /// Calculates the Halation spread radius from camera parameters.
    var resolvedHalationSpread: Float {
        if let custom = halationSpread { return custom }

        // Base spread value
        var spread: Float = 0.70

        // Film physical property adjustment
        spread *= halationSpreadScale

        // Aperture contribution
        let apertureStops = log2(max(captureAperture, 1.0) / 2.8)
        spread -= apertureStops * 0.1

        // ISO contribution
        let isoFactor = log2(max(captureISO, 50) / 400.0) * 0.03
        spread += isoFactor

        return min(max(spread, 0.2), 0.9)
    }

    /// Calculates Halation color temperature, or warmth, from camera parameters.
    var resolvedHalationWarmth: Float {
        if let custom = halationWarmth { return custom }

        // Base warmth
        var warmth: Float = 0.55

        // Color temperature contribution
        let tempOffset = (5500.0 - captureColorTemperature) / 2000.0
        warmth += tempOffset * 0.15

        return min(max(warmth, 0.3), 0.8)
    }

    // MARK: - Vignette dynamic adjustments based on camera parameters

    /// Calculates vignette softness from camera parameters.
    var resolvedVignetteSoftness: Float {
        if let custom = vignetteSoftness { return custom }

        var softness: Float = 0.5

        // Focal length contribution
        let focalFactor = log2(max(captureFocalLength, 13) / 50.0)
        softness += focalFactor * 0.15

        // Camera type fine-tuning
        switch captureCameraType {
        case .ultraWide:
            softness -= 0.1
        case .telephoto:
            softness += 0.1
        case .front:
            softness += 0.05
        case .wide:
            break
        }

        return min(max(softness, 0.2), 0.9)
    }

    /// Calculates vignette roundness from camera parameters.
    var resolvedVignetteRoundness: Float {
        if let custom = vignetteRoundness { return custom }

        var roundness: Float = 0.3

        // Focal length contribution
        let focalFactor = log2(max(captureFocalLength, 13) / 50.0)
        roundness += focalFactor * 0.1

        // Camera type fine-tuning
        switch captureCameraType {
        case .ultraWide:
            roundness -= 0.1
        case .telephoto:
            roundness += 0.15
        case .front:
            roundness += 0.1
        case .wide:
            break
        }

        return min(max(roundness, 0.1), 0.8)
    }

    /// Calculates a normalized aperture value from camera parameters.
    var vignetteAperture: Float {
        let fStops = log2(max(captureAperture, 1.4) / 1.4)
        return min(max(fStops / 6.5, 0), 1)
    }

    /// Converts the snapshot into unified processor parameters.
    var imageAdjustments: ImageAdjuster.Adjustments {
        var adj = ImageAdjuster.Adjustments()
        adj.exposure = exposure ?? 0.0
        // `FilmEmulation` uses contrast in the 0...1 range, where 0.5 is neutral.
        // `ImageAdjuster` uses contrast as an offset, where 0 is neutral.
        if let c = contrast {
            adj.contrast = (c * 2.0) - 1.0
        }
        adj.saturation = sat ?? 1.0
        adj.vibrance = vibrance ?? 0.0
        adj.hue = hue ?? 0.0
        // `FilmEmulation` temperature and tint are normalized in `ImageAdjuster`.
        adj.temperature = temp ?? 0.0
        adj.tint = tint ?? 0.0
        adj.highlights = highlights ?? 0.0
        adj.shadows = shadows ?? 0.0
        adj.whites = whites ?? 0.0
        adj.blacks = blacks ?? 0.0
        adj.texture = texture ?? 0.0
        adj.clarity = clarity ?? 0.0
        adj.dehaze = dehaze ?? 0.0
        adj.sharpening = sharpening ?? 0.0
        return adj
    }
}
