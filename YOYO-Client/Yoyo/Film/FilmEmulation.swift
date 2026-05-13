import CoreImage

// ═══════════════════════════════════════════════════════════════════════════════
// FilmEmulation.swift - Physically accurate all-in-one Film simulation
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified Film simulation portal
enum FilmEmulation {
    // MARK: - Compute Shader Engine

    private static let computeEngine = FilmComputeEngine.shared

    // MARK: - Metal Kernels

    private static let mainKernel: CIKernel? = FilmEffectUtils.loadGeneralKernel(name: "yoyoFilmEmulationMain")
    private static let bloomExtractKernel: CIColorKernel? = FilmEffectUtils.loadColorKernel(name: "yoyoFilmBloomExtract")
    private static let halationExtractWithTintKernel: CIColorKernel? = FilmEffectUtils.loadColorKernel(name: "yoyoFilmHalationExtractWithTint")
    private static let pyramidBlendKernel: CIColorKernel? = FilmEffectUtils.loadColorKernel(name: "yoyoFilmPyramidBlend")
    private static let lightLeakKernel: CIKernel? = FilmEffectUtils.loadGeneralKernel(name: "yoyoFilmLightLeak")

    // MARK: - Lens presets

    struct LensPreset {
        let maxFieldAngle: Float
        let naturalPower: Float
        let opticalStart: Float
        let opticalStrength: Float
        let mechStart: Float
        let mechSharpness: Float
        let edgeColorTemp: Float

        static let classic50mm = LensPreset(
            maxFieldAngle: 0.7, naturalPower: 4.0, opticalStart: 0.65, opticalStrength: 0.3,
            mechStart: 0.95, mechSharpness: 0.1, edgeColorTemp: 0.3
        )

        static let wideAngle24mm = LensPreset(
            maxFieldAngle: 1.2, naturalPower: 4.5, opticalStart: 0.5, opticalStrength: 0.5,
            mechStart: 0.85, mechSharpness: 0.3, edgeColorTemp: 0.1
        )

        static let telephoto85mm = LensPreset(
            maxFieldAngle: 0.5, naturalPower: 3.5, opticalStart: 0.7, opticalStrength: 0.25,
            mechStart: 0.98, mechSharpness: 0.05, edgeColorTemp: 0.4
        )
    }

    // MARK: - Grain parameter

    struct GrainParams {
        let rms: Float
        let shadowBoost: Float
        let midtonePeak: Float
        let highlightFalloff: Float
        let chromaRatio: Float

        static func fromISO(_ iso: Float) -> GrainParams {
            // Reference physical properties from Kodak Portra (fine) to Ilford Delta 3200 (coarse)
            // Optimization strategy: Tighten the RMS range to 0.75-0.85 and maintain the "oily" texture
            // RMS controls the amplitude intensity, and size changes are independently controlled by adjustedGrainCrystalSize
            let rms: Float = switch iso {
            case ..<200: 0.18 // Baseline: ISO < 200, delicate and smooth
            case ..<400: 0.28 // ISO 400: visible but not obtrusive
            case ..<800: 0.38 // ISO 800: Visible but still delicate
            case ..<3200: 0.55 // ISO 3200: rough but oily
            default: 0.75 // ISO 6400+: Highest limit to avoid excessive roughness
            }
            let shadowBoost = min(max(1.0 + log2(max(iso, 50) / 400.0) * 0.15, 0.8), 2.5)
            return GrainParams(rms: rms, shadowBoost: shadowBoost, midtonePeak: 0.35, highlightFalloff: 0.6, chromaRatio: 0.4)
        }
    }

    // MARK: - Main entrance

    nonisolated static func apply(
        to input: CIImage,
        snapshot: FilmEmulationSnapshot,
        enableCineTone: Bool = true,
        frameSeed: UInt32? = nil,
        quality: FilmEmulationQuality = .full,
        isRawSource: Bool = false
    ) -> CIImage {
        var effectiveSnapshot = snapshot
        if !enableCineTone {
            effectiveSnapshot.cineToneIntensity = 0
        }

        let hasAnyEffect = effectiveSnapshot.cineToneIntensity > 0.001 ||
            effectiveSnapshot.halationIntensity > 0.001 ||
            effectiveSnapshot.bloomIntensity > 0.001 ||
            effectiveSnapshot.fogIntensity > 0.001 ||
            effectiveSnapshot.vignetteIntensity > 0.001 ||
            effectiveSnapshot.lightLeakIntensity > 0.001 ||
            effectiveSnapshot.grainIntensity > 0.001 ||
            effectiveSnapshot.dustIntensity > 0.001 ||
            effectiveSnapshot.scratchesIntensity > 0.001 ||
            effectiveSnapshot.hairIntensity > 0.001 ||
            abs(effectiveSnapshot.exposure ?? 0) > 0.001 ||
            abs((effectiveSnapshot.contrast ?? 0.5) - 0.5) > 0.001 ||
            abs(effectiveSnapshot.temp ?? 0) > 0.001 ||
            abs(effectiveSnapshot.tint ?? 0) > 0.001 ||
            abs(effectiveSnapshot.hue ?? 0) > 0.001 ||
            abs((effectiveSnapshot.sat ?? 1.0) - 1.0) > 0.001 ||
            abs(effectiveSnapshot.vibrance ?? 0) > 0.001 ||
            abs(effectiveSnapshot.highlights ?? 0) > 0.001 ||
            abs(effectiveSnapshot.shadows ?? 0) > 0.001 ||
            abs(effectiveSnapshot.whites ?? 0) > 0.001 ||
            abs(effectiveSnapshot.blacks ?? 0) > 0.001 ||
            abs(effectiveSnapshot.texture ?? 0) > 0.001 ||
            abs(effectiveSnapshot.clarity ?? 0) > 0.001 ||
            abs(effectiveSnapshot.dehaze ?? 0) > 0.001 ||
            abs(effectiveSnapshot.sharpening ?? 0) > 0.001

        guard hasAnyEffect else { return input }

        let linkage = FilmPhysicsLinkage(userSnapshot: effectiveSnapshot)
        let params = linkage.computeLinkedParameters()
        let workingInput = input

        return applyImplementation(
            to: workingInput,
            snapshot: effectiveSnapshot,
            params: params,
            frameSeed: frameSeed,
            quality: quality,
            isRawSource: isRawSource
        )
    }

    // MARK: - Segmentation entrance (used for Color Grading front and rear splitting)

    /// Optical Stage: Used before Color Grading.
    /// Goal: Preserve optical scattering-like effects that depend on specular structure/threshold.
    nonisolated static func applyOpticalStage(
        to input: CIImage,
        snapshot: FilmEmulationSnapshot,
        frameSeed: UInt32? = nil,
        quality: FilmEmulationQuality = .full
    ) -> CIImage {
        var opticalSnapshot = snapshot
        opticalSnapshot.cineToneIntensity = 0
        opticalSnapshot.fogIntensity = 0
        opticalSnapshot.vignetteIntensity = 0
        opticalSnapshot.lightLeakIntensity = 0
        opticalSnapshot.grainIntensity = 0
        opticalSnapshot.dustIntensity = 0
        opticalSnapshot.scratchesIntensity = 0
        opticalSnapshot.hairIntensity = 0

        return apply(
            to: input,
            snapshot: opticalSnapshot,
            enableCineTone: false,
            frameSeed: frameSeed,
            quality: quality
        )
    }

    /// Finishing stage: used after Color Grading.
    /// Goal: Preserve "overlay/film-like texture" effects (grain, vignetting, haze, dust scratches).
    nonisolated static func applyFinishingStage(
        to input: CIImage,
        snapshot: FilmEmulationSnapshot,
        frameSeed: UInt32? = nil,
        quality: FilmEmulationQuality = .full
    ) -> CIImage {
        var finishingSnapshot = snapshot
        finishingSnapshot.cineToneIntensity = 0
        finishingSnapshot.halationIntensity = 0
        finishingSnapshot.bloomIntensity = 0

        return apply(
            to: input,
            snapshot: finishingSnapshot,
            enableCineTone: false,
            frameSeed: frameSeed,
            quality: quality
        )
    }

    // MARK: - Unified processing path (Full & Preview)

    private static func applyImplementation(
        to input: CIImage,
        snapshot: FilmEmulationSnapshot,
        params: LinkedEffectsParameters,
        frameSeed: UInt32?,
        quality: FilmEmulationQuality,
        isRawSource _: Bool
    ) -> CIImage {
        let extent = input.extent
        let workExtent = extent

        guard let mainKernel else { return input }

        // Generate Bloom/Halation layers using physical parameters
        let physics = params.physics
        let effectivePrintWarmth = adjustedPrintWarmth(printWarmth: snapshot.printWarmth, captureColorTemperature: snapshot.captureColorTemperature)

        let effectiveCineTone = params.cineTone
        let effectiveGrain = params.grain

        // Unified light effect calculation resolution:
        // Regardless of Preview or Full, Bloom/Halation is always calculated at a scale of ~1280px.
        // This ensures that the physical radius of the light effect (relative to the screen) is consistent under different resolutions and avoids the light effect in Full mode being too weak.
        let effectsReferenceSize: CGFloat = 1280.0
        // Performance scaling factor for Bloom/Halation (limited to a maximum of 1.0, i.e. no upsampling to ensure clarity)
        let effectsScale = min(1.0, effectsReferenceSize / max(extent.width, extent.height))

        let effectsInput: CIImage
        if effectsScale < 0.999 {
            effectsInput = FilmEffectUtils.scaleImageKeepingOrigin(input, scale: effectsScale)
        } else {
            effectsInput = input
        }
        let effectsExtent = effectsInput.extent

        // Generate effects layer (based on scaled effectsInput)
        var bloomLayer = params.bloom > 0.001
            ? generateBloomLayer(
                from: effectsInput,
                intensity: params.bloom,
                threshold: physics.bloomThreshold,
                spread: physics.bloomSpread
            )
            : emptyImage(effectsExtent)

        var halationLayer = params.halation > 0.001
            ? generateHalationLayer(
                from: effectsInput,
                intensity: params.halation,
                threshold: physics.halationThreshold,
                spread: physics.halationSpread,
                warmth: physics.halationWarmth,
                tintCore: snapshot.halationTintCore,
                tintMid: snapshot.halationTintMid,
                tintEdge: snapshot.halationTintEdge,
                strength: snapshot.halationStrength,
                customColor: snapshot.halationColor
            )
            : emptyImage(effectsExtent)

        // Upsample the effects layer back to the current working resolution (Upsample back to input extent)
        if effectsScale < 0.999 {
            // Use progressiveUpsample or scale directly?
            // Bloom/Halation itself is fuzzy and can be directly bilinear/bicubic interpolation.
            bloomLayer = bloomLayer.transformed(by: CGAffineTransform(scaleX: 1.0 / effectsScale, y: 1.0 / effectsScale))
                .cropped(to: extent)
            halationLayer = halationLayer.transformed(by: CGAffineTransform(scaleX: 1.0 / effectsScale, y: 1.0 / effectsScale))
                .cropped(to: extent)
        }

        // Generate local contrast reference layer (for adjacency effect)
        // This layer needs to have the same resolution as the original image and is used to calculate edges.
        // Contiguity effects usually occur at microscopic scales, but also require a certain physical radius.
        // Optimization: Use resolutionScale instead of effectsScale to ensure that the radius can be reduced correctly in Preview (small image) mode
        let resolutionScale = Float(max(workExtent.width, workExtent.height) / effectsReferenceSize)
        let contrastRadius = 2.5 * resolutionScale
        let localContrastLayer = FilmEffectUtils.gaussianBlur(input, radius: contrastRadius)

        // Prepare parameters
        let grainParams = GrainParams.fromISO(snapshot.captureISO)
        let lensPreset = lensPresetForSnapshot(snapshot)

        // Apply vignetting optical reduction
        let adjustedOpticalStrength = max(0, lensPreset.opticalStrength + physics.vignetteOpticalReduction)

        // Grain crystal size correction
        // Optimization: Reduce the weight of RMS influence on size (5.0 -> 2.5)
        // Purpose: To keep high ISO particles with a "tight and sharp" silver salt feel and avoid becoming blurry "mosaic blocks"
        // Base size range changed from [1.75 ~ 5.25]px to [1.4 ~ 4.25]px (assuming RMS 0.12~1.3)
        let baseCrystalSize = grainParams.rms * 2.5 + 1.1
        let grainResolutionScale = Float(max(extent.width, extent.height) / effectsReferenceSize)
        let adjustedGrainCrystalSize = baseCrystalSize * physics.grainCrystalSize * grainResolutionScale * (snapshot.grainSize ?? 1.0)

        // No size compensation for amplitudes: RMS is no longer multiplied by physics.grainCrystalSize
        // Amplitude strength is controlled independently by RMS and size changes are controlled by adjustedGrainCrystalSize
        // Increase the grainRoughness of the film itself
        let grainAmplitude = grainParams.rms * snapshot.grainRoughness

        // Seed Calculation (Shared between Grain and Light Leak)
        let seedValue = Float(frameSeed ?? (quality == .preview ? 42 : UInt32.random(in: 0 ... 10000)))

        // NOTE: The parameter order must be exactly the same as that of yoyoFilmEmulationMain of FilmEmulation.metal.
        // Otherwise, subsequent parameters will be misaligned as a whole (for example, Dust/Scratches will not take effect in the Preview).
        let args: [Any] = [
            input, bloomLayer, halationLayer, localContrastLayer,
            CIVector(x: workExtent.width, y: workExtent.height),
            effectiveCineTone, params.halation, params.bloom, params.fog + physics.fogDensityBoost, params.vignette, effectiveGrain,
            snapshot.resolvedVignetteSoftness, snapshot.resolvedVignetteRoundness, snapshot.vignetteAperture,
            lensPreset.maxFieldAngle, lensPreset.naturalPower, lensPreset.opticalStart,
            adjustedOpticalStrength, lensPreset.mechStart, lensPreset.mechSharpness, lensPreset.edgeColorTemp,
            grainAmplitude, adjustedGrainCrystalSize, seedValue,
            grainParams.shadowBoost, grainParams.midtonePeak, grainParams.highlightFalloff, grainParams.chromaRatio,
            physics.halationWarmth,
            snapshot.negativeExposure, snapshot.developmentGamma,
            CIVector(x: CGFloat(snapshot.layerSpeeds.x), y: CGFloat(snapshot.layerSpeeds.y), z: CGFloat(snapshot.layerSpeeds.z)),
            CIVector(x: CGFloat(snapshot.layerCrossovers.x), y: CGFloat(snapshot.layerCrossovers.y), z: CGFloat(snapshot.layerCrossovers.z)),
            snapshot.colorCrosstalk, snapshot.dyeDensity + params.grainInducedDyeDensity,
            snapshot.adjacencyStrength, snapshot.shadowLift, snapshot.highlightRolloff,
            CIVector(x: CGFloat(snapshot.channelMixerRed.x), y: CGFloat(snapshot.channelMixerRed.y), z: CGFloat(snapshot.channelMixerRed.z)),
            CIVector(x: CGFloat(snapshot.channelMixerGreen.x), y: CGFloat(snapshot.channelMixerGreen.y), z: CGFloat(snapshot.channelMixerGreen.z)),
            CIVector(x: CGFloat(snapshot.channelMixerBlue.x), y: CGFloat(snapshot.channelMixerBlue.y), z: CGFloat(snapshot.channelMixerBlue.z)),
            snapshot.printContrast, effectivePrintWarmth,
            CIVector(x: CGFloat(snapshot.fogColor?.x ?? 0.08), y: CGFloat(snapshot.fogColor?.y ?? 0.09), z: CGFloat(snapshot.fogColor?.z ?? 0.10)),
            snapshot.fogContrast ?? 0.5,
            physics.bloomWarmth,
            snapshot.dustIntensity,
            snapshot.scratchesIntensity,
            snapshot.hairIntensity,
        ]

        let result = mainKernel.apply(extent: workExtent, roiCallback: { _, rect in rect }, arguments: args)?.cropped(to: workExtent) ?? input

        // Apply Light Leak
        var finalResult = result
        if snapshot.lightLeakIntensity > 0.001, let lightLeakKernel {
            // Prepare custom color parameters
            let customColor = snapshot.lightLeakColor ?? SIMD3<Float>(0, 0, 0)
            let position = snapshot.lightLeakPosition ?? 0.5
            let saturation = snapshot.lightLeakSaturation ?? 1.0
            let contrast = snapshot.lightLeakContrast ?? 0.5

            // If the position is random (0.5), use a random trigger counter to generate a new seed
            var effectiveSeed = seedValue
            if abs(position - 0.5) < 0.01 {
                // Random mode: generate new seeds based on trigger counter
                let triggerSeed = Float(snapshot.lightLeakRandomTrigger ?? 0) * 1234.5
                effectiveSeed = seedValue + triggerSeed
            }

            finalResult = lightLeakKernel.apply(
                extent: workExtent,
                roiCallback: { _, rect in rect },
                arguments: [
                    finalResult,
                    snapshot.lightLeakIntensity,
                    snapshot.lightLeakThreshold ?? 0.2,
                    snapshot.lightLeakSpread ?? 0.5,
                    snapshot.lightLeakWarmth ?? 0.5,
                    effectiveSeed,
                    CIVector(x: workExtent.width, y: workExtent.height),
                    CIVector(x: CGFloat(customColor.x), y: CGFloat(customColor.y), z: CGFloat(customColor.z)),
                    position,
                    saturation,
                    contrast,
                ]
            )?.cropped(to: workExtent) ?? finalResult
        }

        // Apply Common Adjustments using ImageAdjuster
        finalResult = ImageAdjuster.applyAdjustments(snapshot.imageAdjustments, to: finalResult)

        return finalResult
    }

    // MARK: - Bloom layer generation

    private static func generateBloomLayer(
        from input: CIImage,
        intensity: Float,
        threshold: Float,
        spread: Float
    ) -> CIImage {
        let extent = input.extent

        // Prefer Compute Shader if available
        if let engine = computeEngine,
           engine.isAvailable,
           let result = engine.generateBloomLayer(from: input, intensity: intensity, threshold: threshold, spread: spread)
        {
            return result.cropped(to: extent)
        }

        // Fallback: CIFilter path (Pyramid)
        guard let extractKernel = bloomExtractKernel,
              let bright = extractKernel.apply(
                  extent: extent,
                  roiCallback: { _, rect in rect },
                  arguments: [input, threshold, Float(0.2), 1.0 + intensity * 0.5]
              )?.cropped(to: extent)
        else {
            return emptyImage(extent)
        }

        // Optimization: Bloom radius adaptive resolution
        // Ensure that the visual proportion of the halo is consistent under Preview (small resolution) and Full (1280px baseline)
        // 1280.0 is the baseline resolution during parameter tuning
        let maxDim = Float(max(extent.width, extent.height))
        let radiusScale = maxDim / 1280.0
        let baseRadius: Float = (8.0 + spread * 20.0) * radiusScale

        // Unified use of four-layer pyramid (performance is fast enough at 1280px)
        let half = FilmEffectUtils.scaleImageKeepingOrigin(bright, scale: 0.5)
        let quarter = FilmEffectUtils.scaleImageKeepingOrigin(half, scale: 0.5)
        let eighth = FilmEffectUtils.scaleImageKeepingOrigin(quarter, scale: 0.5)
        let sixteenth = FilmEffectUtils.scaleImageKeepingOrigin(eighth, scale: 0.5)

        let blur0 = FilmEffectUtils.gaussianBlur(half, radius: baseRadius * 0.15).cropped(to: half.extent)
        let blur1 = FilmEffectUtils.gaussianBlur(quarter, radius: baseRadius * 0.125).cropped(to: quarter.extent)
        let blur2 = FilmEffectUtils.gaussianBlur(eighth, radius: baseRadius * 0.0875).cropped(to: eighth.extent)
        let blur3 = FilmEffectUtils.gaussianBlur(sixteenth, radius: baseRadius * 0.0625).cropped(to: sixteenth.extent)

        let up0 = FilmEffectUtils.progressiveUpsample(blur0, targetExtent: extent)
        let up1 = FilmEffectUtils.progressiveUpsample(blur1, targetExtent: extent)
        let up2 = FilmEffectUtils.progressiveUpsample(blur2, targetExtent: extent)
        let up3 = FilmEffectUtils.progressiveUpsample(blur3, targetExtent: extent)

        return pyramidBlendKernel?.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [up0, up1, up2, up3, spread]
        )?.cropped(to: extent) ?? up0
    }

    // MARK: - Halation layer generation

    private static func generateHalationLayer(
        from input: CIImage,
        intensity: Float,
        threshold: Float,
        spread: Float,
        warmth: Float,
        tintCore: SIMD3<Float>,
        tintMid: SIMD3<Float>,
        tintEdge: SIMD3<Float>,
        strength: Float,
        customColor: SIMD3<Float>? = nil
    ) -> CIImage {
        let extent = input.extent

        // Overlay with custom color
        var effectiveTintCore = tintCore
        var effectiveTintMid = tintMid
        var effectiveTintEdge = tintEdge

        if let color = customColor {
            effectiveTintMid = color
            // The core area is brighter
            effectiveTintCore = SIMD3<Float>(1.0, 1.0, 1.0) * 0.6 + color * 0.4
            // Marginal area same color but slightly darker/darker
            effectiveTintEdge = color * 0.8
        }

        // Prefer using Compute Shader
        if let engine = computeEngine,
           engine.isAvailable,
           let result = engine.generateHalationLayer(
               from: input,
               intensity: intensity,
               threshold: threshold,
               spread: spread,
               warmth: warmth,
               tintCore: effectiveTintCore,
               tintMid: effectiveTintMid,
               tintEdge: effectiveTintEdge,
               strength: strength
           )
        {
            return result.cropped(to: extent)
        }

        // Fallback: CIFilter path - use kernel with custom colors
        guard let extractKernel = halationExtractWithTintKernel,
              let extracted = extractKernel.apply(
                  extent: extent,
                  roiCallback: { _, rect in rect },
                  arguments: [
                      input,
                      threshold,
                      spread,
                      warmth,
                      CIVector(x: CGFloat(effectiveTintCore.x), y: CGFloat(effectiveTintCore.y), z: CGFloat(effectiveTintCore.z)),
                      CIVector(x: CGFloat(effectiveTintMid.x), y: CGFloat(effectiveTintMid.y), z: CGFloat(effectiveTintMid.z)),
                      CIVector(x: CGFloat(effectiveTintEdge.x), y: CGFloat(effectiveTintEdge.y), z: CGFloat(effectiveTintEdge.z)),
                      strength,
                  ]
              )?.cropped(to: extent)
        else {
            return emptyImage(extent)
        }

        let minDim = Float(min(extent.width, extent.height))
        let baseRadius = min(minDim / 95.0, 28.0)
        let sf = 0.5 + spread * 0.8
        let rf = 0.6 + 0.4 * intensity

        // Unified use of four layers of scattering
        let half = FilmEffectUtils.scaleImageKeepingOrigin(extracted, scale: 0.5)
        let quarter = FilmEffectUtils.scaleImageKeepingOrigin(half, scale: 0.5)
        let eighth = FilmEffectUtils.scaleImageKeepingOrigin(quarter, scale: 0.5)
        let sixteenth = FilmEffectUtils.scaleImageKeepingOrigin(eighth, scale: 0.5)

        let l0 = FilmEffectUtils.gaussianBlur(half, radius: baseRadius * 0.32 * sf * rf * 0.5).cropped(to: half.extent)
        let l1 = FilmEffectUtils.gaussianBlur(quarter, radius: min(baseRadius * 1.9 * sf * rf, 56) * 0.25).cropped(to: quarter.extent)
        let l2 = FilmEffectUtils.gaussianBlur(eighth, radius: min(baseRadius * 6.5 * sf * rf, 160) * 0.125).cropped(to: eighth.extent)
        let l3 = FilmEffectUtils.gaussianBlur(sixteenth, radius: min(baseRadius * 16 * sf * rf, 360) * 0.0625).cropped(to: sixteenth.extent)

        let up0 = FilmEffectUtils.progressiveUpsample(l0, targetExtent: extent)
        let up1 = FilmEffectUtils.progressiveUpsample(l1, targetExtent: extent)
        let up2 = FilmEffectUtils.progressiveUpsample(l2, targetExtent: extent)
        let up3 = FilmEffectUtils.progressiveUpsample(l3, targetExtent: extent)

        return pyramidBlendKernel?.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [up0, up1, up2, up3, spread]
        )?.cropped(to: extent) ?? up0
    }

    // MARK: - helper method

    private static func emptyImage(_ extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
    }

    private static func lensPresetForSnapshot(_ snapshot: FilmEmulationSnapshot) -> LensPreset {
        switch snapshot.captureCameraType {
        case .ultraWide: return .wideAngle24mm
        case .telephoto: return .telephoto85mm
        case .front: return .classic50mm
        case .wide:
            if snapshot.captureFocalLength < 30 { return .wideAngle24mm }
            else if snapshot.captureFocalLength > 60 { return .telephoto85mm }
            else { return .classic50mm }
        }
    }

    private static func adjustedPrintWarmth(printWarmth: Float, captureColorTemperature: Float) -> Float {
        let offset = (5500.0 - captureColorTemperature) / 2000.0
        let compensation = offset * 0.08
        return min(max(printWarmth - compensation, 0.0), 1.0)
    }
}

// MARK: - Physical parameter calculation system

/// Physical parameter calculator
/// Core Principle: User controls intensity, camera parameters control physical properties
/// - The intensity value set by the user is used directly without any linkage modification.
/// - Camera parameters (ISO, aperture, color temperature, etc.) affect the physical performance of the effect (such as particle size, scattering radius)
private struct FilmPhysicsLinkage {
    let userSnapshot: FilmEmulationSnapshot

    // MARK: - physical constant

    private enum PhysicsConstants {
        // Reference value
        static let referenceISO: Float = 400
        static let referenceAperture: Float = 2.8
        static let referenceColorTemp: Float = 5500

        // particle physics
        static let grainCrystalSizeBase: Float = 1.0
        static let grainCrystalSizePerStop: Float = 0.15 // Increased crystal size per ISO stop

        // Physics
        // Then lower the base threshold and increase the base spread to highlight the CineStill blush
        static let halationThresholdBase: Float = 0.28
        static let halationThresholdPerISOStop: Float = 0.04
        static let halationThresholdPerEV: Float = 0.03
        static let halationSpreadBase: Float = 0.70
        static let halationSpreadPerApertureStop: Float = 0.08

        // Bloom Physics
        static let bloomThresholdBase: Float = 0.7
        static let bloomThresholdPerEV: Float = 0.05
        static let bloomSpreadBase: Float = 0.5
        static let bloomSpreadPerApertureStop: Float = 0.1

        /// Vignette physics
        static let vignetteOpticalStrengthPerApertureStop: Float = 0.08

        /// Dye density linkage (the only physical linkage retained: higher dye clouds for higher ISO films are larger)
        static let dyeDensityPerISOStop: Float = 0.03
    }

    // MARK: - Calculate final parameters

    func computeLinkedParameters() -> LinkedEffectsParameters {
        let user = userSnapshot

        // Calculate relative values ​​of camera parameters (in stops)
        let isoStops = log2(user.captureISO / PhysicsConstants.referenceISO)
        // The exposure of f-number is proportional to 1/N^2, so "aperture stop" should use 2*log2(N/Nref)
        let apertureStops = 2.0 * log2(user.captureAperture / PhysicsConstants.referenceAperture)
        let colorTempOffset = (PhysicsConstants.referenceColorTemp - user.captureColorTemperature) / 2000.0

        // Calculate physical property parameters
        let physics = computePhysicsParameters(
            isoStops: isoStops,
            apertureStops: apertureStops,
            colorTempOffset: colorTempOffset,
            exposureBias: user.captureExposureBias
        )

        // Dye density linkage: larger particles and larger dye clouds at high ISO
        // This is the only physical linkage retained because it has a real physical basis
        let grainInducedDyeDensity = user.grainIntensity * max(0, isoStops) * PhysicsConstants.dyeDensityPerISOStop

        return LinkedEffectsParameters(
            // User strength: use directly without modification
            cineTone: user.cineToneIntensity,
            halation: user.halationIntensity,
            bloom: user.bloomIntensity,
            grain: user.grainIntensity,
            fog: user.fogIntensity,
            vignette: user.vignetteIntensity,
            // Physical property parameters
            physics: physics,
            // Dye density linkage
            grainInducedDyeDensity: grainInducedDyeDensity
        )
    }

    // MARK: - Calculation of physical properties

    private func computePhysicsParameters(
        isoStops: Float,
        apertureStops: Float,
        colorTempOffset: Float,
        exposureBias: Float
    ) -> EffectPhysicsParameters {
        // === Grain Physical Properties ===
        // High ISO → larger silver salt crystals → coarser grains
        // Increase the impact of film roughness coefficient
        let grainCrystalSize = (PhysicsConstants.grainCrystalSizeBase +
            max(0, isoStops) * PhysicsConstants.grainCrystalSizePerStop) * userSnapshot.grainRoughness

        // === Halation Physical Properties ===
        // High ISO → Emulsion layer more sensitive → Threshold lowered
        // Positive exposure compensation → more highlights → lower threshold
        // Added film physics threshold shift
        let halationThreshold = clamp(
            PhysicsConstants.halationThresholdBase -
                max(0, isoStops) * PhysicsConstants.halationThresholdPerISOStop -
                exposureBias * PhysicsConstants.halationThresholdPerEV +
                userSnapshot.halationThresholdOffset,
            0.15, 0.65
        )

        // Large aperture → softer scattering
        // Added film physical diffusion scaling
        let halationSpread = clamp(
            (PhysicsConstants.halationSpreadBase -
                apertureStops * PhysicsConstants.halationSpreadPerApertureStop) * userSnapshot.halationSpreadScale,
            0.2, 0.9
        )

        // Color temperature affects Halation Warmth
        let halationWarmth = clamp(0.5 + colorTempOffset * 0.2, 0.3, 0.8)

        // === Bloom Physical Properties ===
        // Positive exposure compensation → more highlights → lower threshold
        let bloomThreshold = clamp(
            PhysicsConstants.bloomThresholdBase -
                exposureBias * PhysicsConstants.bloomThresholdPerEV,
            0.5, 0.9
        )

        // Large aperture → larger scattering radius
        let bloomSpread = clamp(
            PhysicsConstants.bloomSpreadBase -
                apertureStops * PhysicsConstants.bloomSpreadPerApertureStop,
            0.2, 0.8
        )

        // Color temperature affects Bloom warmth
        let bloomWarmth = clamp(0.5 + colorTempOffset * 0.15, 0.2, 0.8)

        // === Vignette Physical Properties ===
        // Large aperture → reduced optical vignetting (reduced entrance pupil occlusion)
        let vignetteOpticalReduction = clamp(
            -apertureStops * PhysicsConstants.vignetteOpticalStrengthPerApertureStop,
            -0.3, 0.3
        )

        // === Fog Physical Properties ===
        // High ISO films have a slightly higher base haze
        let fogDensityBoost = clamp(max(0, isoStops) * 0.02, 0.0, 0.1)

        // Apply Overrides
        let finalHalationThreshold = userSnapshot.halationThreshold ?? halationThreshold
        let finalHalationSpread = userSnapshot.halationSpread ?? halationSpread
        let finalHalationWarmth = userSnapshot.halationWarmth ?? halationWarmth

        let finalBloomThreshold = userSnapshot.bloomThreshold ?? bloomThreshold
        let finalBloomSpread = userSnapshot.bloomSpread ?? bloomSpread
        let finalBloomWarmth = userSnapshot.bloomWarmth ?? bloomWarmth

        return EffectPhysicsParameters(
            grainCrystalSize: grainCrystalSize,
            halationThreshold: finalHalationThreshold,
            halationSpread: finalHalationSpread,
            halationWarmth: finalHalationWarmth,
            bloomThreshold: finalBloomThreshold,
            bloomSpread: finalBloomSpread,
            bloomWarmth: finalBloomWarmth,
            vignetteOpticalReduction: vignetteOpticalReduction,
            fogDensityBoost: fogDensityBoost
        )
    }

    private func clamp(_ value: Float, _ minVal: Float, _ maxVal: Float) -> Float {
        min(max(value, minVal), maxVal)
    }
}

// MARK: - Effect physical parameters

/// Physical property parameters calculated based on camera parameters
/// These parameters affect the "texture" of the effect, not its intensity
private struct EffectPhysicsParameters {
    /// Grain Physics
    let grainCrystalSize: Float // Crystal size factor (1.0 = standard)

    // Physics
    let halationThreshold: Float // Trigger threshold (0.2~0.7)
    let halationSpread: Float // Scattering range (0.2~0.9)
    let halationWarmth: Float // Color warmth (0.3~0.8)

    // Bloom Physics
    let bloomThreshold: Float // Trigger threshold (0.5~0.9)
    let bloomSpread: Float // Scattering range (0.2~0.8)
    let bloomWarmth: Float // Color warmth (0.2~0.8)

    /// Physics
    let vignetteOpticalReduction: Float // Optical vignetting reduction amount (-0.3~0.3)

    /// Physics
    let fogDensityBoost: Float // Haze enhancement (0~0.1)
}

// MARK: - Linkage parameter output

private struct LinkedEffectsParameters {
    // User strength (direct transparent transmission, no modification)
    let cineTone: Float
    let halation: Float
    let bloom: Float
    let grain: Float
    let fog: Float
    let vignette: Float

    /// Physical property parameters
    let physics: EffectPhysicsParameters

    /// Dye density linkage (the only physical linkage)
    let grainInducedDyeDensity: Float
}
