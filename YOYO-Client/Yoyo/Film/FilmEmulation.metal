// ═══════════════════════════════════════════════════════════════════════════════
// FilmEmulation.metal - physically accurate integrated film emulation
// ═══════════════════════════════════════════════════════════════════════════════
//
// Complete simulation pipeline based on real film physics:
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │                          Physical process order                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │  1. [LENS]      Vignette    - cos^4 law, edge light falloff                       │
// │  2. [EMULSION]  Halation    - red light passes through the base and reflects back before development                  │
// │  3. [DEVELOP]   H&D Curve   - negative characteristic curve (toe / linear section / shoulder)                │
// │                 Layer Response - differentiated response of the three emulsion layers                          │
// │                 Adjacency   - adjacency effect (Mackie Line edge enhancement)               │
// │                 Crosstalk   - inter-layer color crosstalk                                   │
// │                 Dye Density - dye cloud density response                                 │
// │  4. [PRINT]     Contrast    - print contrast S-curve                              │
// │                 Color Grade - split toning (highlight/shadow color temperature)                      │
// │  5. [SCAN]      Base Fog    - base fog / D-min lift                          │
// │  6. [EXPOSURE]  Grain Base  - silver halide crystals as the exposure medium (response curve based on original exposure)    │
// │  7. [OPTICAL]   Bloom       - lens scattering (mixed last to preserve highlight energy)              │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ═══════════════════════════════════════════════════════════════════════════════

#include <CoreImage/CoreImage.h>
#include "FilmShaderCommon.h"

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Stage 1: Lens vignetting (Vignette)
// ═══════════════════════════════════════════════════════════════════════════════

/// Physically accurate cos^4 vignette computation
/// Includes natural, optical, and mechanical vignetting models
inline float3 applyVignette(
    float3 rgb,
    float2 uv,
    float aspect,
    float intensity,
    float softness,
    float roundness,
    float aperture,
    float maxFieldAngle,
    float naturalPower,
    float opticalStart,
    float opticalStrength,
    float mechStart,
    float mechSharpness,
    float edgeColorTemp
) {
    if (intensity <= 0.0001) return rgb;
    
    // Geometric setup
    float2 distVec = uv - float2(0.5);
    float aspectCorrection = mix(1.0, aspect, roundness);
    distVec.x *= aspectCorrection;
    
    float cornerDist = length(float2(0.5 * aspectCorrection, 0.5));
    float d = length(distVec) / max(cornerDist, 0.001);
    
    // A. Natural vignetting - Cos^n(theta) law
    float theta = d * maxFieldAngle;
    float cosTheta = cos(theta);
    float naturalFalloff = pow(max(cosTheta, 0.0), naturalPower);
    
    // B. Optical vignetting - entrance pupil occlusion
    float apertureEffect = 1.0 - aperture * 0.7;
    float opticalVignette = 1.0;
    if (d > opticalStart) {
        float opticalD = (d - opticalStart) / max(1.0 - opticalStart, 0.001);
        opticalVignette = 1.0 - (opticalD * opticalD * opticalStrength * apertureEffect);
    }
    
    // C. Mechanical vignetting - barrel occlusion
    float mechVignette = 1.0;
    if (d > mechStart) {
        float mechD = (d - mechStart) / max(1.0 - mechStart, 0.001);
        float mechFactor = smoothstep(0.0, 1.0 - mechSharpness, mechD);
        mechVignette = 1.0 - mechFactor * 0.9;
    }
    
    // Combine
    float softFactor = 0.2 + softness * 0.6;
    float smoothNatural = mix(1.0, naturalFalloff, smoothstep(softFactor * 0.3, softFactor, d));
    float combinedVignette = smoothNatural * opticalVignette * mechVignette;
    
    // Apply vignette
    float3 vignetteMask = float3(mix(1.0, combinedVignette, intensity));
    
    // Edge color temperature shift
    float tempEffect = (1.0 - combinedVignette) * edgeColorTemp * intensity * 0.15;
    vignetteMask.r *= (1.0 + tempEffect * 0.8);
    vignetteMask.g *= (1.0 + tempEffect * 0.2);
    vignetteMask.b *= (1.0 - tempEffect * 0.6);
    
    // Edge saturation response
    float luma = dot(rgb, LUMA_WEIGHTS);
    float3 chroma = rgb - luma;
    float satReduction = mix(1.0, 0.85, (1.0 - combinedVignette) * intensity);
    rgb = luma + chroma * satReduction;
    
    return rgb * vignetteMask;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Stage 2: Exposure + silver halide grain base (Grain as Exposure Medium)
// ═══════════════════════════════════════════════════════════════════════════════

/// Physically accurate silver halide grain blended with Soft Light
/// Based on the Selwyn granularity law: G = sigmaD x sqrt(A)
///
/// Silver halide saturation behavior in real film:
/// - Low exposure: crystals are partially developed and grain is obvious (underexposed noise)
/// - Midtones: the optimal grain rendering zone
/// - High exposure: crystals are fully developed and saturated, so grain drops rapidly
/// - Overexposure: silver halide is fully saturated and grain is almost gone (blown-out look)
///
/// @param originalLuma Original exposure luminance used to compute the response curve.
///        When < 0, uses the current rgb luminance for backward compatibility.
///        Physical principle: silver halide saturation is determined during exposure,
///        and should not be affected by later development or print stages.
inline float3 applyGrainAsExposure(
    float3 rgb,
    float2 coord,
    float intensity,
    float rmsGranularity, // Used to compute intensity
    float crystalSize,    // Physical size passed directly (pixels)
    float seed,
    float shadowBoost,
    float midtonePeak,
    float highlightFalloff,
    float chromaRatio,
    float originalLuma = -1.0
) {
    if (intensity <= 0.0001) return rgb;
    
    // Use the original exposure luminance to compute the response curve (physically correct).
    // If original luminance is not provided (< 0), use the current luminance for compatibility.
    float luma = originalLuma >= 0.0 ? originalLuma : dot(rgb, LUMA_WEIGHTS);
    uint seedInt = seed < 0.0 ? 42u : uint(seed * 65536.0);
    
    // === Physically accurate silver halide saturation response curve ===
    // Simulates how grain varies with density on a real film H&D curve
    float response = 1.0;
    
    // 1. Shadow Boost (low-luminance region boost - grain is more visible in underexposed areas)
    // Adjustment: deep shadows should have less grain to mimic D-min behavior and avoid digital-looking noise.
    // The peak is shifted to Zone II-III (luma 0.15-0.35).
    // Adjustment: the start point is raised from 0.02 to 0.05 so the boost does not affect the deepest shadows.
    float deepShadowRise = smoothstep(0.05, 0.25, luma);
    float shadowFalloff = 1.0 - smoothstep(0.25, 0.55, luma);
    float shadowMask = deepShadowRise * shadowFalloff;
    
    response += shadowMask * (shadowBoost - 1.0);
    
    // Extra: base grain rolloff in deep shadows
    // Even without the boost, grain should fall off strongly in deep shadows to prevent heavy black noise.
    // Adjustment: only roll off below the near-black point (0.08) and keep more floor noise (0.5) to preserve a dirty low-light feel.
    float baseShadowRolloff = smoothstep(0.0, 0.08, luma);
    response *= (0.5 + 0.5 * baseShadowRolloff);
    
    // 2. Silver halide saturation falloff
    // Real film: in bright regions the silver halide crystals saturate and grain drops sharply.
    // Use an earlier starting point and a steeper falloff curve.
    float saturationStart = 0.5;   // Falloff begins in the mid-high luminance range
    float saturationEnd = 0.95;    // Grain is nearly gone close to overexposure
    float lumaSaturationMask = smoothstep(saturationStart, saturationEnd, luma);
    // Use exponential falloff to simulate the nonlinear behavior of silver halide saturation.
    float saturationFalloff = 1.0 - pow(lumaSaturationMask, 1.5) * (0.85 + highlightFalloff * 0.15);
    response *= saturationFalloff;
    
    // 3. Midtone peak
    // Real film has the best grain rendering in the midtones.
    float midtoneCenter = 0.3 + midtonePeak * 0.1;
    float midtoneCurve = exp(-pow((luma - midtoneCenter) / 0.25, 2.0));
    response *= 0.7 + midtoneCurve * 0.3;
    
    // 4. Highlight hard cutoff
    // Extremely bright regions, such as light sources, are fully saturated and show almost no grain.
    float hardCutoff = 1.0 - smoothstep(0.85, 1.0, luma) * 0.9;
    response *= hardCutoff;
    
    // === Grain size calculation ===
    // Use the incoming crystalSize, which already includes scaling and physical characteristics.
    float2 uv = coord / max(crystalSize, 1.0);
    
    // === Generate dye clouds ===
    // Adjustment: stop using hashFloatSigned to generate sharp high-frequency white noise (Silver Halide),
    // and instead use high-frequency gradient noise to generate soft-edged dye clouds.
    // After color negative development, the silver halide is removed and soft-edged dye clumps remain.
    
    // 1. High Freq (Dye Core): higher frequency with continuous smooth edges
    // Increase the frequency (1.45 -> 1.80) so the core grain is finer and sharper.
    float dyeCore = gradientNoise(uv * 1.80, seedInt) - 0.5;
    
    // 2. Medium Freq (Cloud Clumping): simulate cloud clumping
    // Increase the frequency (0.7 -> 0.9) so the dye clumps are tighter.
    float dyeClump = gradientNoise(uv * 0.9, seedInt + 1000u) - 0.5;
    
    // Blend: reduce high-frequency sharpness and emphasize the clumped look.
    // Gradient noise has much lower RMS than hash noise, so it needs a strong gain boost (1.25 -> 2.0) to reach the same visual strength.
    float rawGrain = (dyeCore * 0.65 + dyeClump * 0.35) * 2.0;
    
    // === Chroma grain (dye clouds) - differentiated channel frequencies ===
    // Physical characteristics:
    // - Blue Layer (Top): largest crystals and the coarsest grain -> lowest frequency (0.85x)
    // - Green Layer (Mid): medium crystals -> baseline frequency (1.0x)
    // - Red Layer (Bottom): smallest crystals and the finest grain -> highest frequency (1.3x)
    float3 chromaNoise;
    chromaNoise.r = gradientNoise(uv * 1.3 + float2(80.0, 180.0), seedInt + 8000u) - 0.5;
    chromaNoise.g = gradientNoise(uv * 1.0 + float2(150.0, 120.0), seedInt + 7000u) - 0.5;
    chromaNoise.b = gradientNoise(uv * 0.85 + float2(100.0, 73.0), seedInt + 6000u) - 0.5;
    
    // Slightly boost the blue-channel amplitude to make its coarse-grain character more visible.
    chromaNoise.b *= 1.15;
    
    // === Portra DIR Coupler simulation: saturation-dependent grain suppression ===
    // Physical principle: development inhibitors are released in highly saturated regions.
    // Reduce grain response in medium-saturation regions (0.15-0.45).
    // This range happens to cover most skin tones, along with other medium-saturation colors.
    float saturation = length(rgb - luma);
    float saturationMask = smoothstep(0.12, 0.22, saturation) * 
                           smoothstep(0.55, 0.45, saturation);
    
    // DIR effect: grain is reduced by 15-25% in medium-saturation regions.
    float dirInhibition = 1.0 - saturationMask * 0.20;
    response *= dirInhibition;
    
    // === Compose the grain layer ===
    // Dye clouds have soft edges and need higher amplitude to be perceived clearly.
    // Optimization: lower the strength coefficient from 2.8 to 2.1 to reduce roughness in skin-tone regions.
    float finalIntensity = intensity * rmsGranularity * 2.1;
    float lumaDelta = rawGrain * finalIntensity * response;
    float3 chromaDelta = chromaNoise * finalIntensity * response * chromaRatio;
    
    // Build the Soft Light blend layer (0.5 is neutral).
    // noise > 0 (higher density) -> darkens -> Soft Light input < 0.5
    float3 grainLayer = float3(0.5) - float3(lumaDelta) - chromaDelta;
    grainLayer = clamp(grainLayer, 0.02, 0.98);
    
    // === Soft Light blend ===
    float3 result = blendSoftLight3(rgb, grainLayer);
    
    return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Stage 3: Halation scattering inside the emulsion
// ═══════════════════════════════════════════════════════════════════════════════

/// Compute Halation energy for highlight extraction during preprocessing, using a custom color.
inline float4 extractHalationEnergyWithTint(
    float3 rgb,
    float threshold,
    float softness,
    float warmth,
    float3 tintCore,
    float3 tintMid,
    float3 tintEdge,
    float strength
) {
    float luma = dot(rgb, LUMA_WEIGHTS);
    float penetratedEnergy = calculatePenetratedEnergy(rgb, luma, threshold);
    float energyMask = remJetFailure(penetratedEnergy, threshold, softness);
    float bouncedEnergy = penetratedEnergy * energyMask * strength;
    float rolled = halationEnergyRolloff(bouncedEnergy);
    float3 halationColor = getHalationColorWithTint(rolled, tintCore, tintMid, tintEdge);
    // Adaptive energy boost: enhance the middle range and suppress the extreme high end.
    float energyBoost = mix(1.15, 1.45, clamp(rolled * 1.4, 0.0, 1.0));
    float3 boosted = halationColor * rolled * energyBoost;
    return float4(boosted, rolled * energyBoost);
}

/// Blend the preprocessed Halation scatter layer
inline float3 blendHalation(
    float3 rgb,
    float4 halationLayer,
    float intensity,
    float warmth
) {
    if (intensity <= 0.0001) return rgb;
    
    // Reduce convergence so more red tint is preserved.
    float3 converged = applySaturationConvergence(halationLayer.rgb, halationLayer.a, warmth);
    float3 halation = mix(halationLayer.rgb, converged, 0.25);
    float luma = dot(rgb, LUMA_WEIGHTS);
    
    // Shadow protection: prevent black backgrounds from looking hazy.
    float cleanMask = smoothstep(0.005, 0.15, luma + length(halation) * 0.2);
    float boostedIntensity = intensity * 1.6;
    float3 halo = clamp(halation * boostedIntensity * cleanMask, 0.0, 1.0);
    return 1.0 - (1.0 - rgb) * (1.0 - halo);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Stage 4: Chemical development (Film Development)
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete chemical development simulation (physics-based version)
/// Includes the H&D curve, three-layer emulsion response, adjacency effects, color crosstalk, and dye density.
inline float3 applyDevelopment(
    float3 rgb,
    float3 localContrast,  // Local contrast used for the adjacency effect
    float negativeExposure,
    float developmentGamma,
    float3 layerSpeeds,
    float3 layerCrossovers,
    float colorCrosstalk,
    float dyeDensity,
    float adjacencyStrength,
    float shadowLift,
    float highlightRolloff
) {
    // Protect against tiny values
    rgb = max(rgb, float3(1e-5));
    
    // ─────────────────────────────────────────────────────────────────────────
    // STAGE A: Exposure compensation
    // ─────────────────────────────────────────────────────────────────────────
    rgb *= pow(2.0, negativeExposure * 2.0);
    
    // ─────────────────────────────────────────────────────────────────────────
    // STAGE B: Emulsion layer speeds
    // ─────────────────────────────────────────────────────────────────────────
    rgb = pow(max(rgb, float3(0.0001)), 1.0 / layerSpeeds);
    
    // Portra behavior: in the midtones, the green layer has a slightly higher effective speed
    // Physical principle: this is achieved through emulsion thickness and silver halide distribution.
    // This makes midtone color transitions smoother.
    float luma = dot(rgb, LUMA_WEIGHTS);
    float midtoneMask = smoothstep(0.20, 0.35, luma) * 
                        smoothstep(0.75, 0.60, luma);
    
    // Slightly tune the green-channel response in the midtones (green is raised by about 4%).
    rgb.g *= 1.0 + midtoneMask * 0.04;
    
    // Normalize to keep luminance unchanged.
    float newLuma = dot(rgb, LUMA_WEIGHTS);
    rgb *= luma / max(newLuma, 0.001);
    
    // ─────────────────────────────────────────────────────────────────────────
    // STAGE C: Development gamma - piecewise response
    // ─────────────────────────────────────────────────────────────────────────
    // Physics adjustment: digital source images already carry contrast, so the base gamma offset is raised to prevent overshoot.
    float g = 0.75 + developmentGamma * 0.35;
    
    // Portra/Pro 400H behavior: gamma is lower in the midtones for a flatter response
    // Physical principle: the diffusion behavior of the developer produces a gentler response in the middle exposure range.
    luma = dot(rgb, LUMA_WEIGHTS);
    
    // Piecewise gamma: normal in shadows, reduced in midtones, normal in highlights.
    float midtoneGammaReduction = smoothstep(0.15, 0.35, luma) * 
                                  smoothstep(0.75, 0.55, luma);
    float adaptiveGamma = g * (1.0 - midtoneGammaReduction * 0.08);
    
    rgb = pow(max(rgb, float3(0.0001)), float3(1.0 / adaptiveGamma));
    
    // ─────────────────────────────────────────────────────────────────────────
    // STAGE D: Adjacency effects (Mackie Line) - luminance adaptive
    // ─────────────────────────────────────────────────────────────────────────
    if (adjacencyStrength > 0.001) {
        float3 edge = abs(rgb - localContrast);
        float edgeMag = dot(edge, float3(0.333));
        
        // Physical principle: adjacency effects are strongest in the midtones and weaker at both ends.
        // This happens because developer concentration gradients are strongest in the middle exposure range.
        luma = dot(rgb, LUMA_WEIGHTS);
        
        // Midtone peak response
        float midtoneResponse = smoothstep(0.15, 0.30, luma) * 
                                smoothstep(0.85, 0.70, luma);
        
        // Reduce adjacency strength in the midtones to protect soft transitions.
        // Keep normal strength in shadows and highlights to enhance edges.
        float adaptiveStrength = adjacencyStrength * 0.9 * 
                                 mix(1.0, 0.65, midtoneResponse);
        
        rgb *= (1.0 + edgeMag * adaptiveStrength);
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // STAGE E: Color crosstalk - midtone optimization
    // ─────────────────────────────────────────────────────────────────────────
    if (colorCrosstalk > 0.001) {
        luma = dot(rgb, LUMA_WEIGHTS);
        
        // Vision3 behavior: crosstalk is lower in the midtones
        // Physical principle: T-Grain light scattering is lowest in the middle exposure range.
        float midtoneCrosstalkReduction = smoothstep(0.20, 0.35, luma) * 
                                          smoothstep(0.70, 0.55, luma);
        
        float lowCT = colorCrosstalk * smoothstep(0.0, layerCrossovers.x, luma) * 0.6;
        float midCT = colorCrosstalk * smoothstep(layerCrossovers.x, layerCrossovers.y, luma) * 
                      (1.0 - midtoneCrosstalkReduction * 0.35); // Reduce by 35% in the midtones
        float highCT = colorCrosstalk * smoothstep(layerCrossovers.y, layerCrossovers.z, luma) * 1.3;
        float adaptiveCT = clamp(lowCT + midCT + highCT, 0.0, 1.0);
        
        // Optimization: reduce channel crosstalk coefficients by about 25%.
        float3x3 crosstalkMatrix = float3x3(
            float3(1.0 - adaptiveCT * 0.075,  adaptiveCT * 0.038,  adaptiveCT * 0.015),
            float3(adaptiveCT * 0.023,        1.0 - adaptiveCT * 0.053,  adaptiveCT * 0.030),
            float3(adaptiveCT * 0.015,        adaptiveCT * 0.045,        1.0 - adaptiveCT * 0.090)
        );
        rgb = crosstalkMatrix * rgb;
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // STAGE F: Physically accurate dye density - saturation adaptive
    // ─────────────────────────────────────────────────────────────────────────
    if (dyeDensity > 0.001) {
        luma = dot(rgb, LUMA_WEIGHTS);
        // Use simple saturation without squaring so it follows linear density accumulation.
        float saturation = length(rgb - luma);
        
        // Portra behavior: dye density responds more gently in medium-saturation regions
        // Physical principle: this follows the chemical behavior of DIR (Development Inhibitor Releasing) couplers.
        // Highly saturated areas release development inhibitors and reduce local dye density.
        float saturationCurve = 1.0;
        
        // Lower the density coefficient in medium-saturation regions (0.15-0.45).
        // This range happens to cover most skin tones.
        float midSatMask = smoothstep(0.10, 0.20, saturation) * 
                           smoothstep(0.55, 0.45, saturation);
        
        // The density coefficient is reduced by 20-30% in medium-saturation regions.
        saturationCurve = 1.0 - midSatMask * 0.25;
        
        // Physics adjustment: dye density should only affect saturated colors and should not crush low-saturation dark areas.
        // Real negative film: low-saturation dark areas, such as shadows or black clothing, should not darken because of dye buildup.
        // Only highly saturated dark areas, such as deep reds or blues, should deepen because of stacked dye layers.
        
        // Saturation gate: only apply dye density when saturation is above 0.15.
        float saturationGate = smoothstep(0.08, 0.20, saturation);
        
        // Luminance protection: reduce dye density influence in dark areas (luma < 0.2) to avoid crushed blacks.
        // Physical principle: dark areas are underexposed, so they naturally produce less dye.
        float lumaProtection = smoothstep(0.05, 0.25, luma);
        
        // Combined modulation factor
        float densityModulation = saturationGate * (0.3 + 0.7 * lumaProtection);
        
        // Core physical model: Beer-Lambert law simulation
        // The higher the dye density, the lower the transmittance in saturated regions, making them darker and deeper.
        // Coefficient tuning: 1.8 -> 1.5, with a lower transmission bound to preserve clarity.
        float adaptiveDyeDensity = dyeDensity * 1.5 * saturationCurve * densityModulation;
        float minTransmission = 0.22; // Physical floor: prevents highly saturated areas from going fully black
        float transmission = mix(minTransmission, 1.0, exp(-saturation * adaptiveDyeDensity));
        
        // Apply transmittance and add a faint diffuse fill to dark areas.
        rgb *= transmission;
        rgb += (1.0 - transmission) * 0.02 * luma;
        
        // Coupled adjustment: dense dye causes saturation rolloff in highlight regions, producing a shoulder.
        // The thicker the dye, the harder it is for highlights to preserve clean color separation, so they tend to wash out.
        float3 deviation = rgb - luma;
        // The higher the density, the earlier and stronger the highlight desaturation.
        float effectiveRolloff = highlightRolloff * (0.8 + 0.6 * dyeDensity); 
        float highlightSatRolloff = smoothstep(0.5, 1.0, luma) * 0.5 * effectiveRolloff;
        
        rgb = luma + deviation * (1.0 - highlightSatRolloff);
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // STAGE G: Shadow lift + H&D toe simulation
    // ─────────────────────────────────────────────────────────────────────────
    // Physical principle: a real negative H&D curve has an upward toe in low-exposure regions.
    // This lifts shadow detail and prevents fully crushed blacks.
    // This is one of the key reasons negative film has high latitude.
    
    luma = dot(rgb, LUMA_WEIGHTS);
    
    // Toe-lift curve: apply a nonlinear lift in the deepest shadows (0-0.15).
    // Use a square-root curve to simulate the lift of the H&D toe.
    float toeLift = 0.0;
    if (luma < 0.15) {
        float toeRegion = 1.0 - (luma / 0.15); // Darker values receive more lift
        // Nonlinear lift: the sqrt curve makes the deepest shadows lift more noticeably.
        toeLift = sqrt(toeRegion) * (0.010 + shadowLift * 0.018);
    }
    
    // Apply the toe lift while preserving hue.
    if (toeLift > 0.001) {
        float3 lifted = rgb + toeLift;
        // Preserve hue by lifting proportionally.
        float newLuma = dot(lifted, LUMA_WEIGHTS);
        if (luma > 0.001) {
            rgb = rgb * (newLuma / luma);
        } else {
            rgb = lifted;
        }
    }
    
    // Minimum density protection (D-min)
    rgb = max(rgb, float3(0.003 + shadowLift * 0.005));
    
    // ─────────────────────────────────────────────────────────────────────────
    // STAGE H: Highlight shoulder - simulating a rich, glossy feel
    // ─────────────────────────────────────────────────────────────────────────
    // Optimization: lower the blend ratio from 0.18 to 0.15 to preserve highlight clarity.
    // At the same time, do not affect dark areas.
    if (highlightRolloff > 0.001) {
        luma = dot(rgb, LUMA_WEIGHTS);
        // Log2 Curve behavior: linear in low light and gentle in highlights, which is ideal for simulating a film shoulder.
        // log2(x + 1) It is 0 at x = 0 and 1 at x = 1.
        float3 shoulder = log2(rgb + 1.0);
        
        // Only blend the log curve in highlights, entering smoothly from 0.5 to avoid affecting midtones and shadows.
        float mask = smoothstep(0.5, 1.0, luma);
        
        // Blend strength is controlled by highlightRolloff.
        // Optimization: 0.18 -> 0.15 to reduce compression in skin-tone highlights.
        rgb = mix(rgb, shoulder, mask * highlightRolloff * 0.15);
    }
    
    return rgb;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Stage 5: Print (Print)
// ═══════════════════════════════════════════════════════════════════════════════

/// Print stage: contrast curve + split toning
/// Optimization: reduce midtone contrast so skin tones transition more smoothly.
inline float3 applyPrint(
    float3 rgb,
    float printContrast,
    float printWarmth,
    float shadowLift
) {
    // Portra Print behavior: lower contrast in the midtones
    // Physical principle: print paper has a lower contrast response in the midtones.
    float luma = dot(rgb, LUMA_WEIGHTS);
    float midtoneMask = smoothstep(0.20, 0.35, luma) * 
                        smoothstep(0.75, 0.60, luma);
    
    // Reduce contrast by 12-18% in the midtones.
    float adaptiveContrast = printContrast * (1.0 - midtoneMask * 0.15);
    
    // Physics adjustment: shadow contrast protection
    // In real printing, boosting shadow contrast can lose detail and crush blacks.
    // Reduce contrast gain in dark regions (luma < 0.25).
    float shadowProtection = smoothstep(0.05, 0.30, luma);
    adaptiveContrast *= (0.4 + 0.6 * shadowProtection);
    
    // print contrast S-curve
    // Optimization: reduce curve slope and introduce smoother pivot handling.
    float pivot = 0.18;
    float3 powered = pow(max(rgb / pivot, float3(0.0001)), float3(1.0 + adaptiveContrast * 0.28)) * pivot;
    float3 sCurve = rgb * rgb * (3.0 - 2.0 * rgb);
    rgb = mix(rgb, mix(powered, sCurve, adaptiveContrast * 0.1), adaptiveContrast * 0.85);
    
    // [Saturation compensation] 
    // RGB Independent RGB contrast curves can strongly increase saturation.
    // A contrast-dependent negative feedback term is added here to simulate nonlinear film-dye saturation behavior.
    // This preserves the hue shifts created by RGB curves while preventing color clipping.
    // Optimization: lower compensation strength from 0.3 to 0.25 to preserve more color.
    // Also reduce desaturation in dark areas to keep shadow color.
    float lumaPost = dot(rgb, LUMA_WEIGHTS);
    float saturationDampening = adaptiveContrast * 0.25; // Higher contrast applies stronger compensation
    // Shadow protection: reduce desaturation in dark areas.
    float darkSatProtection = smoothstep(0.05, 0.30, lumaPost);
    saturationDampening *= (0.5 + 0.5 * darkSatProtection);
    rgb = mix(rgb, float3(lumaPost), saturationDampening);
    
    // Print color grading (split toning)
    // Recompute luma because rgb has already been modified.
    luma = dot(rgb, LUMA_WEIGHTS);
    float shadowWeight = pow(1.0 - clamp(luma, 0.0, 1.0), 1.8);
    float highlightWeight = pow(clamp(luma, 0.0, 1.0), 2.0);
    
    // Bidirectional warmth logic
    // printWarmth: 0.0 (Cold) -> 0.5 (Neutral) -> 1.0 (Warm)
    float warmthFactor = (printWarmth - 0.5) * 2.0; // -1.0 ~ 1.0
    
    if (warmthFactor > 0.001) {
        // Warm mode
        rgb += float3(
            highlightWeight * warmthFactor * 0.020 + shadowWeight * warmthFactor * 0.018,
            highlightWeight * warmthFactor * 0.008 + shadowWeight * warmthFactor * 0.010,
            -highlightWeight * warmthFactor * 0.010 - shadowWeight * warmthFactor * 0.020
        );
    } else if (warmthFactor < -0.001) {
        // Cool mode (cool highlights, cool shadows, modern cool look)
        float cool = -warmthFactor;
        rgb += float3(
            // R: Reduce red in highlights and shadows to pull warmth out of the image.
            -highlightWeight * cool * 0.025 - shadowWeight * cool * 0.010, // Reduce red in the shadows
            // G: Fine-tune while preserving luminance or adding a slight cyan shift.
            highlightWeight * cool * 0.005 + shadowWeight * cool * 0.005,
            // B: Increase blue in highlights for a cool white look and greatly reduce blue gain in shadows to avoid dead blue shadows.
            highlightWeight * cool * 0.030 + shadowWeight * cool * 0.015
        );
    }
    
    // Final ACES RRT approximation
    float blackPoint = 0.003 + shadowLift * 0.007;
    rgb = acesTonemap(max(rgb, float3(0.0)));
    rgb = max(rgb, float3(blackPoint));
    
    return rgb;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Stage 6: Base fog (Base Fog / D-min)
// ═══════════════════════════════════════════════════════════════════════════════

/// Physical base fog
/// Simulates the minimum density of unexposed film areas.
inline float3 applyBaseFog(
    float3 rgb,
    float intensity,
    float3 fogColor,
    float contrastReductionFactor
) {
    if (intensity <= 0.0001) return rgb;
    
    // Screen blend: naturally lift dark areas
    float3 lift = fogColor * intensity;
    float3 fogged = 1.0 - (1.0 - rgb) * (1.0 - lift);
    
    // Fog also reduces contrast slightly.
    // contrastReductionFactor 0.0 (no effect) -> 1.0 (maximum contrast reduction)
    // The default behavior is intensity * 0.1.
    float contrastReduction = 1.0 - intensity * contrastReductionFactor * 0.5;
    float luma = dot(fogged, LUMA_WEIGHTS);
    fogged = luma + (fogged - luma) * contrastReduction;
    
    return fogged;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Stage 7: Bloom blend (lens scattering)
// ═══════════════════════════════════════════════════════════════════════════════

/// Blend the preprocessed Bloom scatter layer
inline float3 blendBloom(
    float3 rgb,
    float3 bloomLayer,  // Pre-blurred Bloom layer
    float intensity,
    float warmth
) {
    if (intensity <= 0.0001) return rgb;
    
    // Color temperature adjustment
    float3 tintWarm = float3(1.08, 1.03, 0.95);
    float3 tintCool = float3(0.95, 1.0, 1.08);
    float3 tint = mix(tintCool, tintWarm, warmth);
    bloomLayer *= tint;
    
    // Energy-conserving Screen blend
    float3 blended = 1.0 - (1.0 - rgb) * (1.0 - bloomLayer * intensity);
    
    return blended;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Stage 8: Defect simulation (Defects: Dust & Scratches)
// ═══════════════════════════════════════════════════════════════════════════════

/// Old-photo style dust simulation
///
/// Aesthetic goal: create a nostalgic, warm old-photo feel.
/// - Sparkle Dust：Tiny light specks scattered like stardust to add a magical feel.
/// - Soft Motes：Soft floating dust with a warm tint.
/// - Hair/Fiber：Occasional fine fibers that add authentic age.
///
/// Design principle: moderately dense, soft, and slightly glossy, adding to the image rather than damaging it.
/// Optimization: increase count and visibility so the dust effect reads more clearly.
inline float3 applyDust(float3 rgb, float2 uv, float2 imageSize, float intensity, uint seed) {
    if (intensity <= 0.0001) return rgb;
    
    float luma = dot(rgb, LUMA_WEIGHTS);
    float pixelScale = 1280.0 / max(imageSize.x, imageSize.y);
    
    // ══════════════════════════════════════════════════════════════════════
    // 1. Sparkle Dust (Sparkle dust)
    // ══════════════════════════════════════════════════════════════════════
    // Aesthetic feature: tiny highlight specks like silver-halide sparkle on an old photo.
    // More visible in midtones and shadows, while blending naturally in highlights.
    
    float sparkleMask = 0.0;
    // Reduce the grid size to increase density: 0.05 -> 0.04.
    float2 sparkleGrid = float2(0.04, 0.04);
    float2 sparkleCell = floor(uv / sparkleGrid);
    
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 cell = sparkleCell + float2(dx, dy);
            uint cellSeed = seed + uint(cell.x * 127.1 + cell.y * 311.7);
            
            // Increase appearance probability: 0.12 -> 0.25.
            if (hashFloat(cellSeed) > intensity * 0.25) continue;
            
            float2 sparklePos = cell * sparkleGrid + float2(
                hashFloat(cellSeed + 1u) * sparkleGrid.x,
                hashFloat(cellSeed + 2u) * sparkleGrid.y
            );
            
            float dist = length(uv - sparklePos);
            
            // Slightly enlarge the size so dust is more visible, with resolution compensation.
            float coreSize = (0.0012 + hashFloat(cellSeed + 3u) * 0.002) * pixelScale;
            float glowSize = coreSize * 3.5;  // Increase glow size: 3.0 -> 3.5
            
            // Core + glow, with stronger core intensity.
            float core = 1.0 - smoothstep(0.0, coreSize, dist);
            float glow = 1.0 - smoothstep(coreSize, glowSize, dist);
            float sparkle = core * 1.0 + glow * 0.4;  // Raise core from 0.8 to 1.0 and glow from 0.3 to 0.4
            
            // Randomize brightness while raising the minimum brightness.
            float brightness = 0.6 + hashFloat(cellSeed + 4u) * 0.4;  // Raise from 0.5-1.0 to 0.6-1.0
            sparkleMask = max(sparkleMask, sparkle * brightness);
        }
    }
    
    // Sparkle points are more visible in dark regions because of contrast.
    float sparkleVisibility = 1.0 - luma * 0.5;
    float3 sparkleColor = float3(1.0, 0.98, 0.94);  // Warm white
    // Increase overall strength: 0.6 -> 0.8.
    rgb += sparkleColor * sparkleMask * intensity * 0.8 * sparkleVisibility;
    
    // ══════════════════════════════════════════════════════════════════════
    // 2. Soft Motes (Soft motes)
    // ══════════════════════════════════════════════════════════════════════
    // Aesthetic feature: slightly larger soft dots with a subtle warm tint, like dust floating in sunlight.
    
    float moteMask = 0.0;
    // Reduce the grid size to increase density: 0.12 -> 0.09.
    float2 moteGrid = float2(0.09, 0.09);
    float2 moteCell = floor(uv / moteGrid);
    
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 cell = moteCell + float2(dx, dy);
            uint cellSeed = seed + 80000u + uint(cell.x * 269.5 + cell.y * 183.3);
            
            // Increase appearance probability: 0.08 -> 0.18.
            if (hashFloat(cellSeed) > intensity * 0.18) continue;
            
            float2 motePos = cell * moteGrid + float2(
                hashFloat(cellSeed + 1u) * moteGrid.x,
                hashFloat(cellSeed + 2u) * moteGrid.y
            );
            
            float dist = length(uv - motePos);
            
            // Slightly enlarge the size, with resolution compensation.
            float moteSize = (0.005 + hashFloat(cellSeed + 3u) * 0.007) * pixelScale;
            float mote = exp(-dist * dist / (moteSize * moteSize * 0.5));
            
            // Increase opacity from 0.3-0.7 to 0.4-0.8.
            float opacity = 0.4 + hashFloat(cellSeed + 4u) * 0.4;
            moteMask = max(moteMask, mote * opacity);
        }
    }
    
    // Soft motes use a slightly warm beige tint with Screen blending.
    float3 moteColor = float3(0.98, 0.95, 0.88);
    // Increase strength: 0.25 -> 0.35.
    rgb = 1.0 - (1.0 - rgb) * (1.0 - moteColor * moteMask * intensity * 0.35);
    
    // ══════════════════════════════════════════════════════════════════════
    // 3. Vintage Hair/Fiber (Vintage fibers)
    // ══════════════════════════════════════════════════════════════════════
    // Aesthetic feature: occasional elegant curves that add a vintage feel.
    // Designed as decorative elements rather than flaws.
    
    float hairMask = 0.0;
    
    // Fibers only appear at higher intensity and remain very rare.
    if (intensity > 0.3) {
        // At most 1-2 per image.
        for (int i = 0; i < 2; i++) {
            uint hairSeed = seed + 150000u + uint(i) * 31337u;
            
            // Very low appearance probability
            if (hashFloat(hairSeed) > (intensity - 0.3) * 0.3) continue;
            
            // Starting point biased toward the edges for a more natural look.
            float2 hairStart = float2(
                hashFloat(hairSeed + 1u),
                hashFloat(hairSeed + 2u)
            );
            
            // Elegant curved direction
            float baseAngle = hashFloat(hairSeed + 3u) * 3.14159 * 2.0;
            float hairLength = 0.15 + hashFloat(hairSeed + 4u) * 0.25;
            // Apply resolution compensation
            float hairWidth = (0.0006 + hashFloat(hairSeed + 5u) * 0.0006) * pixelScale;
            
            // Curvature with a Bezier-like feel
            float curvature = (hashFloat(hairSeed + 6u) - 0.5) * 2.0;
            
            // Distance from the sample point to the curve
            float2 toPoint = uv - hairStart;
            float2 hairDir = float2(cos(baseAngle), sin(baseAngle));
            float t = dot(toPoint, hairDir) / hairLength;
            
            if (t < 0.0 || t > 1.0) continue;
            
            // Quadratic Bezier-style offset
            float curveOffset = curvature * t * (1.0 - t) * 0.1;
            float2 perpDir = float2(-hairDir.y, hairDir.x);
            float2 curvePoint = hairStart + hairDir * t * hairLength + perpDir * curveOffset;
            
            float dist = length(uv - curvePoint);
            
            // Elegant tapered shape toward both ends
            float taper = sin(t * 3.14159);
            float effectiveWidth = hairWidth * (0.3 + taper * 0.7);
            
            float hair = 1.0 - smoothstep(effectiveWidth * 0.3, effectiveWidth, dist);
            hairMask = max(hairMask, hair * 0.6);
        }
    }
    
    // Fibers are rendered as semi-transparent dark strands with a slight brown tint.
    float3 hairColor = float3(0.25, 0.22, 0.18);
    rgb = mix(rgb, hairColor, hairMask * intensity * 0.5);
    
    return rgb;
}

/// Old-film style scratch simulation
/// Old-film style scratch simulation
///
/// Physical realism: photo scratches come from human-caused damage in many directions.
/// - Vertical scratches: friction during film transport (33% probability).
/// - Horizontal scratches: friction during cleaning or placement (33% probability).
/// - Diagonal scratches: accidental scraping (34% probability).
/// - Short scratches: small random scrapes in all directions.
///
/// Aesthetic goal: create the look of classic old film and vintage stock.
/// - Random Direction Scratches：Elegant fine lines coming from many directions (1-2 lines).
/// - Short Random Scratches：Short glossy scratches (2-4 lines).
/// - Gentle Wear：Soft wear patterns that add age.
///
/// Design principle: scratches should act as decorative elements that add vintage beauty.
/// Aesthetic tuning:
/// - Very strong broken-up behavior with 8-15 major breaks, 18-30 secondary breaks, and 40-70 micro breaks.
/// - Strictly limit length so short scratches cover about 6%-18% of the frame.
/// - Expand the fade regions strongly so scratches look shorter.
/// - Reduce the count to avoid an overly dense look.
/// - Balance direction distribution so no single direction dominates.
inline float3 applyScratches(float3 rgb, float2 uv, float2 imageSize, float intensity, uint seed) {
    if (intensity <= 0.0001) return rgb;
    
    float luma = dot(rgb, LUMA_WEIGHTS);
    float pixelScale = 1280.0 / max(imageSize.x, imageSize.y);
    
    // ══════════════════════════════════════════════════════════════════════
    // 1. Random Direction Scratches (Random direction scratches)
    // ══════════════════════════════════════════════════════════════════════
    // Physical realism: photo scratches come from human-caused damage in many directions.
    // - Vertical scratches: friction during film transport (33% probability).
    // - Horizontal scratches: friction during cleaning or placement (33% probability).
    // - Diagonal scratches: accidental scraping (34% probability).
    // 
    // Aesthetic tuning:
    // - Very strong broken-up behavior to avoid long lines crossing the whole frame
    // - Balanced direction distribution so no single direction dominates
    // - Much larger fade regions so scratches disappear earlier
    
    float scratchMask = 0.0;
    
    // Primary scratches (1-2, reduced count)
    int numScratches = 1 + int(intensity * 1.5);
    for (int i = 0; i < numScratches && i < 4; i++) {
        uint scratchSeed = seed + 200000u + uint(i) * 4919u;
        
        // Appearance probability rises with intensity.
        if (hashFloat(scratchSeed) > intensity * 0.7) continue;
        
        // === Random direction selection ===
        float dirRnd = hashFloat(scratchSeed + 20u);
        float angle;
        float2 primaryAxis;
        float2 secondaryAxis;
        
        // Adjust the probability distribution so directions stay balanced.
        if (dirRnd < 0.33) {
            // Vertical scratches (33%)
            angle = 1.5708 + (hashFloat(scratchSeed + 21u) - 0.5) * 0.15;  // 90° ± 8.6°
            primaryAxis = float2(0.0, 1.0);
            secondaryAxis = float2(1.0, 0.0);
        } else if (dirRnd < 0.66) {
            // Horizontal scratches (33%)
            angle = (hashFloat(scratchSeed + 21u) - 0.5) * 0.15;  // 0° ± 8.6°
            primaryAxis = float2(1.0, 0.0);
            secondaryAxis = float2(0.0, 1.0);
        } else {
            // Diagonal scratches (34%, random angle)
            angle = hashFloat(scratchSeed + 21u) * 3.14159 * 2.0;  // 0-360°
            primaryAxis = float2(cos(angle), sin(angle));
            secondaryAxis = float2(-sin(angle), cos(angle));
        }
        
        // === Scratch position along the axis perpendicular to the scratch direction===
        float positionAlongSecondary = hashFloat(scratchSeed + 1u);
        // Avoid the exact center of the frame.
        if (positionAlongSecondary < 0.33) {
            positionAlongSecondary = positionAlongSecondary * 0.25 + 0.05;
        } else if (positionAlongSecondary > 0.67) {
            positionAlongSecondary = 0.70 + (positionAlongSecondary - 0.67) * 0.75;
        } else {
            positionAlongSecondary = 0.30 + (positionAlongSecondary - 0.33) * 1.2;
        }
        
        // Extremely thin line width, with resolution compensation
        float lineWidth = (0.0004 + hashFloat(scratchSeed + 2u) * 0.0006) * pixelScale;
        
        // Small wobble to simulate irregular scratches.
        float wobbleFreq = 30.0 + hashFloat(scratchSeed + 3u) * 40.0;
        float wobbleAmp = (0.001 + hashFloat(scratchSeed + 4u) * 0.002) * pixelScale;
        float posAlongPrimary = dot(uv, primaryAxis);
        float wobble = sin(posAlongPrimary * wobbleFreq) * wobbleAmp;
        
        // Distance calculation from the point to the scratch line.
        float posAlongSecondaryUV = dot(uv, secondaryAxis);
        float dist = abs(posAlongSecondaryUV - positionAlongSecondary - wobble);
        
        // Soft line edges
        float line = 1.0 - smoothstep(lineWidth * 0.2, lineWidth, dist);
        
        // Brightness variation along the length for a shimmering feel.
        float flicker = 0.5 + 0.5 * sin(posAlongPrimary * 200.0 + hashFloat(scratchSeed + 5u) * 100.0);
        float brightness = 0.4 + flicker * 0.6;
        
        // === Aesthetic tuning:Strongly increase the broken-up behavior. ===
        // Use multiple noise layers to create a more natural broken pattern and avoid overly long scratches.
        // Further increase break frequency and strength.
        
        // 1. Primary break layer: larger broken segments, with frequency raised from 5-10 to 8-15.
        float mainBreakFreq = 8.0 + hashFloat(scratchSeed + 7u) * 7.0;
        float mainContinuity = softValueNoise(float2(posAlongPrimary * mainBreakFreq, float(i)), scratchSeed + 6u);
        // Greatly increase break strength from 0.35-0.50 to 0.40-0.55 so lines break very easily.
        float mainBreakMask = smoothstep(0.40, 0.55, mainContinuity);
        
        // 2. Secondary break layer: medium breaks, with frequency raised from 12-20 to 18-30.
        float midBreakFreq = 18.0 + hashFloat(scratchSeed + 8u) * 12.0;
        float midContinuity = softValueNoise(float2(posAlongPrimary * midBreakFreq, float(i) + 0.5), scratchSeed + 9u);
        // Increase break strength from 0.30-0.45 to 0.35-0.50.
        float midBreakMask = smoothstep(0.35, 0.50, midContinuity);
        
        // 3. Micro break layer: tiny shimmering gaps, with frequency raised from 30-50 to 40-70.
        float microBreakFreq = 40.0 + hashFloat(scratchSeed + 10u) * 30.0;
        float microContinuity = softValueNoise(float2(posAlongPrimary * microBreakFreq, float(i) + 1.0), scratchSeed + 11u);
        // Increase break strength from 0.25-0.40 to 0.30-0.45.
        float microBreakMask = smoothstep(0.30, 0.45, microContinuity);
        
        // Combine the break effects with even more weight so the gaps read very clearly.
        // Shift from 0.4 + 0.35 + 0.25 to a more balanced set of weights.
        float combinedBreak = mainBreakMask * (0.35 + midBreakMask * 0.35 + microBreakMask * 0.30);
        
        // === Aesthetic tuning:Further expand the edge fade. ===
        // Expand the fade region from 15% to 20% so scratches disappear earlier.
        float fadeStart = smoothstep(0.0, 0.20, posAlongPrimary);
        float fadeEnd = smoothstep(1.0, 0.80, posAlongPrimary);
        float edgeFade = fadeStart * fadeEnd;
        
        // Final composition: line x breaks x fade x brightness
        scratchMask = max(scratchMask, line * combinedBreak * edgeFade * brightness);
    }
    
    // Scratches are rendered as bright silver or white for a classic look.
    float3 scratchColor = float3(0.95, 0.93, 0.90);
    // More visible in dark areas and naturally blended in bright areas.
    float scratchVisibility = 0.6 + (1.0 - luma) * 0.4;
    rgb = rgb + scratchColor * scratchMask * intensity * 0.7 * scratchVisibility;
    
    // ══════════════════════════════════════════════════════════════════════
    // 2. Short Random Scratches (Short random scratches)
    // ══════════════════════════════════════════════════════════════════════
    // Physical realism: small scrape and friction marks.
    // Aesthetic feature: short fine lines made of tiny highlights, like scratch reflections in sunlight.
    //
    // Aesthetic tuning:
    // - Strictly limit length to 0.08-0.25 to avoid overly long marks.
    // - Use fully random directions to simulate accidental scratches.
    // - Increase tapering at both ends so scratches look more elegant.
    
    float shimmerMask = 0.0;
    
    // Multiple short scratches with reduced count: 2-6 -> 2-4.
    int numShimmers = 2 + int(intensity * 2.0);
    for (int i = 0; i < numShimmers && i < 4; i++) {
        uint shimmerSeed = seed + 300000u + uint(i) * 7727u;
        
        if (hashFloat(shimmerSeed) > intensity * 0.5) continue;
        
        // Starting position
        float startX = hashFloat(shimmerSeed + 1u);
        float startY = hashFloat(shimmerSeed + 2u);
        
        // === Aesthetic tuning:Strictly limit length to avoid overly long marks. ===
        // Shorten further from 0.08-0.25 to 0.06-0.18.
        float scratchLen = 0.06 + hashFloat(shimmerSeed + 3u) * 0.12;
        
        // === Fully random direction (0-360 degrees).===
        // Simulate human-made scratches from many directions.
        float angle = hashFloat(shimmerSeed + 4u) * 3.14159 * 2.0;
        float2 dir = float2(cos(angle), sin(angle));
        
        // Distance from the point to the line segment
        float2 toPoint = uv - float2(startX, startY);
        float t = dot(toPoint, dir);
        if (t < 0.0 || t > scratchLen) continue;
        
        float2 closestPoint = float2(startX, startY) + dir * t;
        float dist = length(uv - closestPoint);
        
        // Extremely thin width, with resolution compensation
        float width = (0.0003 + hashFloat(shimmerSeed + 5u) * 0.0004) * pixelScale;
        float scratch = 1.0 - smoothstep(width * 0.2, width, dist);
        
        // === Aesthetic tuning:Fade at both ends ===
        // Make scratches disappear naturally at both ends for a more elegant look.
        // Expand the fade region from 15% to 25% so scratches look shorter.
        float tNorm = t / scratchLen;  // Normalized position [0, 1]
        float endFade = smoothstep(0.0, 0.25, tNorm) * smoothstep(1.0, 0.75, tNorm);
        
        // Shimmering behavior that varies along the length.
        float shimmer = pow(sin(tNorm * 3.14159) * 0.5 + 0.5, 0.5);
        // High-frequency shimmer
        shimmer *= 0.6 + 0.4 * sin(t * 300.0 + hashFloat(shimmerSeed + 6u) * 50.0);
        
        // Final composition: scratch x fade x shimmer
        shimmerMask = max(shimmerMask, scratch * endFade * shimmer * 0.8);
    }
    
    // Shimmer is rendered as a soft highlight
    float3 shimmerColor = float3(1.0, 0.98, 0.95);
    rgb = rgb + shimmerColor * shimmerMask * intensity * 0.5;
    
    // ══════════════════════════════════════════════════════════════════════
    // 3. Gentle Patina (Gentle patina)
    // ══════════════════════════════════════════════════════════════════════
    // Aesthetic feature: subtle surface texture like patina on an old photo.
    // Adds age and a warm tactile feel.
    
    if (intensity > 0.2) {
        // Use vertically stretched noise to simulate subtle vertical texture.
        float2 patinaUV = uv * float2(400.0, 40.0);
        float patina = gradientNoise(patinaUV, seed + 400000u);
        
        // Extract high-value regions as subtle vertical lines, with a higher threshold to reduce visible area.
        // Raise the range from 0.6-0.8 to 0.7-0.85 to reduce visible marks.
        patina = smoothstep(0.7, 0.85, patina) * 0.2;  // Lower intensity from 0.3 to 0.2
        
        // Soft regional variation
        float regionVar = softValueNoise(uv * 3.0, seed + 400001u);
        patina *= regionVar;
        
        // Apply it as a slight luminance variation with much lower strength.
        // Lower color intensity from 0.03/0.025/0.02 to 0.015/0.012/0.01.
        // Reduce the overall coefficient from 2.0 to 1.0.
        rgb = rgb + float3(0.015, 0.012, 0.01) * patina * (intensity - 0.2) * 1.0;
    }
    
    return rgb;
}

/// Hair/fiber defect simulation
///
/// Physical realism: hair, fibers, or lint on the film surface or scanner.
/// - Long, thin curved shapes
/// - Semi-transparent dark or light colors
/// - Random distribution with controlled count
/// - Natural curvature and width variation
///
/// Aesthetic goal: add the feeling of real film wear.
inline float3 applyHair(float3 rgb, float2 uv, float2 imageSize, float intensity, uint seed) {
    if (intensity <= 0.0001) return rgb;
    
    float luma = dot(rgb, LUMA_WEIGHTS);
    float pixelScale = 1280.0 / max(imageSize.x, imageSize.y);
    
    float hairMask = 0.0;
    
    // Hair count: 1-5 depending on intensity.
    int numHairs = 1 + int(intensity * 4.0);
    
    for (int i = 0; i < numHairs && i < 5; i++) {
        uint hairSeed = seed + 500000u + uint(i) * 9973u;
        
        // Appearance probability
        if (hashFloat(hairSeed) > intensity * 0.8) continue;
        
        // Start points are biased toward the edges for a more natural look.
        float edgeBias = hashFloat(hairSeed + 1u);
        float2 hairStart;
        
        if (edgeBias < 0.25) {
            // Start from the left edge
            hairStart = float2(hashFloat(hairSeed + 2u) * 0.1, hashFloat(hairSeed + 3u));
        } else if (edgeBias < 0.5) {
            // Start from the right edge
            hairStart = float2(0.9 + hashFloat(hairSeed + 2u) * 0.1, hashFloat(hairSeed + 3u));
        } else if (edgeBias < 0.75) {
            // Start from the top edge
            hairStart = float2(hashFloat(hairSeed + 2u), 0.9 + hashFloat(hairSeed + 3u) * 0.1);
        } else {
            // Start from the bottom edge
            hairStart = float2(hashFloat(hairSeed + 2u), hashFloat(hairSeed + 3u) * 0.1);
        }
        
        // Hair length, relatively long and spanning the frame.
        float hairLength = 0.2 + hashFloat(hairSeed + 4u) * 0.4;
        
        // Base direction
        float baseAngle = hashFloat(hairSeed + 5u) * 3.14159 * 2.0;
        float2 hairDir = float2(cos(baseAngle), sin(baseAngle));
        
        // Curvature parameter with a Bezier-like curve
        float curvature = (hashFloat(hairSeed + 6u) - 0.5) * 3.0;
        
        // Hair width, kept extremely thin.
        float hairWidth = (0.0003 + hashFloat(hairSeed + 7u) * 0.0005) * pixelScale;
        
        // Compute the distance from the point to the curve.
        float2 toPoint = uv - hairStart;
        float t = dot(toPoint, hairDir) / hairLength;
        
        if (t < 0.0 || t > 1.0) continue;
        
        // Quadratic Bezier-style offset
        float2 perpDir = float2(-hairDir.y, hairDir.x);
        float curveOffset = curvature * t * (1.0 - t) * 0.15;
        float2 curvePoint = hairStart + hairDir * t * hairLength + perpDir * curveOffset;
        
        float dist = length(uv - curvePoint);
        
        // Taper at both ends
        float taper = sin(t * 3.14159);
        float effectiveWidth = hairWidth * (0.2 + taper * 0.8);
        
        // Hair shape with soft edges
        float hair = 1.0 - smoothstep(effectiveWidth * 0.3, effectiveWidth, dist);
        
        // Opacity variation along the length to mimic natural hair translucency.
        float alphaVar = 0.5 + 0.5 * sin(t * 3.14159 * 3.0 + hashFloat(hairSeed + 8u) * 10.0);
        
        hairMask = max(hairMask, hair * alphaVar);
    }
    
    // Hair color is chosen as dark or light depending on the background luminance.
    float3 hairColor;
    if (luma > 0.5) {
        // Bright background: dark hair in deep gray or brown.
        hairColor = float3(0.15, 0.12, 0.10);
    } else {
        // Dark background: light hair in pale gray or white.
        hairColor = float3(0.85, 0.83, 0.80);
    }
    
    // Blend mode: semi-transparent overlay
    float hairAlpha = hairMask * intensity * 0.6;
    rgb = mix(rgb, hairColor, hairAlpha);
    
    return rgb;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Highlight extraction kernel (used for Bloom/Halation preprocessing)
// ═══════════════════════════════════════════════════════════════════════════════

/// Bloom highlight extraction
extern "C" float4 yoyoFilmBloomExtract(
    coreimage::sample_t src,
    float threshold,
    float knee,
    float preGain,
    coreimage::destination dest
) {
    float3 rgb = max(src.rgb * preGain, float3(0.0));
    float luma = dot(rgb, LUMA_WEIGHTS);
    
    // Karis average: reduce the weight of extremely bright pixels to suppress fireflies.
    float karisWeight = 1.0 / (1.0 + luma);
    
    // Soft-threshold extraction
    float w = clamp((luma - threshold) / max(knee, 1e-5), 0.0, 1.0);
    w = w * w * (3.0 - 2.0 * w); // Hermite smoothing
    
    // Preserve highlight color and add a slight saturation boost, with lower gain to avoid a fluorescent look.
    float satBoost = 1.0 + 0.05 * w;
    float3 saturated = mix(float3(luma), rgb, satBoost);
    
    float3 bright = saturated * w * karisWeight;
    
    return float4(bright, w);
}

/// Halation Highlight extraction with custom color, supporting Halation colors from different film presets.
extern "C" float4 yoyoFilmHalationExtractWithTint(
    coreimage::sample_t src,
    float threshold,
    float softness,
    float warmth,
    float3 tintCore,
    float3 tintMid,
    float3 tintEdge,
    float strength,
    coreimage::destination dest
) {
    return extractHalationEnergyWithTint(
        src.rgb, threshold, softness, warmth,
        tintCore, tintMid, tintEdge, strength
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Main film emulation kernel (full quality)
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete film emulation that accepts preprocessed Bloom and Halation layers
extern "C" float4 yoyoFilmEmulationMain(
    coreimage::sample_t src,
    coreimage::sample_t bloomSample,      // Pre-blurred Bloom layer
    coreimage::sample_t halationSample,   // Pre-blurred Halation layer
    coreimage::sample_t localContrastSample, // Added: local contrast reference for the adjacency effect
    float2 imageSize,
    
    // Intensity parameters
    float cineToneIntensity,
    float halationIntensity,
    float bloomIntensity,
    float fogIntensity,
    float vignetteIntensity,
    float grainIntensity,
    
    // Vignette parameters
    float vignetteSoftness,
    float vignetteRoundness,
    float vignetteAperture,
    float vignetteMaxFieldAngle,
    float vignetteNaturalPower,
    float vignetteOpticalStart,
    float vignetteOpticalStrength,
    float vignetteMechStart,
    float vignetteMechSharpness,
    float vignetteEdgeColorTemp,
    
    // Grain parameters
    float grainRms,
    float grainCrystalSize, // Added: explicitly pass in crystal size
    float grainSeed,
    float grainShadowBoost,
    float grainMidtonePeak,
    float grainHighlightFalloff,
    float grainChromaRatio,
    
    // Halation parameters
    float halationWarmth,
    
    // Development parameters
    float negativeExposure,
    float developmentGamma,
    float3 layerSpeeds,
    float3 layerCrossovers,
    float colorCrosstalk,
    float dyeDensity,
    float adjacencyStrength,
    float shadowLift,
    float highlightRolloff,
    
    // Channel Mixer parameters
    float3 channelMixerRed,
    float3 channelMixerGreen,
    float3 channelMixerBlue,
    
    // Print parameters
    float printContrast,
    float printWarmth,
    
    // Fog parameters
    float3 fogColor,
    float fogContrast,
    
    // Bloom parameters
    float bloomWarmth,

    // Defects parameters
    float dustIntensity,
    float scratchesIntensity,
    float hairIntensity,
    
    coreimage::destination dest
) {
    float3 rgb = src.rgb;
    float2 coord = dest.coord();
    float2 uv = coord / imageSize;
    float aspect = imageSize.x / imageSize.y;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 1. [LENS] Vignette - edge light falloff
    // ═══════════════════════════════════════════════════════════════════════════
    rgb = applyVignette(
        rgb, uv, aspect,
        vignetteIntensity,
        vignetteSoftness,
        vignetteRoundness,
        vignetteAperture,
        vignetteMaxFieldAngle,
        vignetteNaturalPower,
        vignetteOpticalStart,
        vignetteOpticalStrength,
        vignetteMechStart,
        vignetteMechSharpness,
        vignetteEdgeColorTemp
    );
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 2. [EMULSION] Halation scattering inside the emulsion
    // ═══════════════════════════════════════════════════════════════════════════
    rgb = blendHalation(
        rgb,
        halationSample,
        halationIntensity,
        halationWarmth
    );
    
    // ═══════════════════════════════════════════════════════════════════════════
    // Store the original exposure luminance for the grain response curve.
    // Physical principle: silver halide saturation is determined during exposure,
    // and should not be affected by later development or print stages.
    // ═══════════════════════════════════════════════════════════════════════════
    float originalLuma = dot(rgb, LUMA_WEIGHTS);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 3. [CINETONE PATH] Integrated film path: development -> mixer -> print
    // ═══════════════════════════════════════════════════════════════════════════
    if (cineToneIntensity > 0.0001) {
        float3 filmPath = rgb;
        
        // 3.1. [DEVELOP] Chemical development
        filmPath = applyDevelopment(
            filmPath,
            localContrastSample.rgb, 
            negativeExposure,
            developmentGamma,
            layerSpeeds,
            layerCrossovers,
            colorCrosstalk,
            dyeDensity,
            adjacencyStrength,
            shadowLift,
            highlightRolloff
        );
        
        // 3.2. [MIXER] Brand channel mixer
        float3 mixed = float3(
            dot(filmPath, channelMixerRed),
            dot(filmPath, channelMixerGreen),
            dot(filmPath, channelMixerBlue)
        );
        filmPath = max(mixed, float3(0.0));
        
        // 3.3. [PRINT] Print stage including the final S-curve and contrast logic
        filmPath = applyPrint(filmPath, printContrast, printWarmth, shadowLift);
        
        // 3.4. [MIX] Linear mixing and luminance protection
        // Core idea: keep the film-like hue shift while protecting luminance structure during blending to preserve clarity.
        float lumaOrig = dot(rgb, LUMA_WEIGHTS);
        float lumaFilm = dot(filmPath, LUMA_WEIGHTS);
        
        float3 colorMixed = mix(rgb, filmPath, cineToneIntensity);
        // Apply nonlinear mapping to luminance blending so shadows do not pile up at high intensity.
        float lumaMixed = mix(lumaOrig, lumaFilm, pow(cineToneIntensity, 1.2) * 0.7);
        
        // Normalize luminance so hue shifts do not make the image too dark.
        rgb = colorMixed * (lumaMixed / max(dot(colorMixed, LUMA_WEIGHTS), 0.001));
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 5. [SCAN] Base fog (D-min)
    // Base fog is an intrinsic film property that appears during scanning as a minimum-density lift.
    // Place it before grain so fog-lifted highlights do not make grain too obvious on bright surfaces.
    // ═══════════════════════════════════════════════════════════════════════════
    rgb = applyBaseFog(rgb, fogIntensity, fogColor, fogContrast);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 6. [EXPOSURE] Silver halide grain as the exposure medium
    // Use the original exposure luminance for the response curve so CineTone compression does not affect it.
    // This prevents excessive grain in highlight regions.
    // ═══════════════════════════════════════════════════════════════════════════
    rgb = applyGrainAsExposure(
        rgb, coord,
        grainIntensity,
        grainRms,
        grainCrystalSize,
        grainSeed,
        grainShadowBoost,
        grainMidtonePeak,
        grainHighlightFalloff,
        grainChromaRatio,
        originalLuma
    );
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 7. [OPTICAL] Bloom lens scattering
    // ═══════════════════════════════════════════════════════════════════════════
    rgb = blendBloom(rgb, bloomSample.rgb, bloomIntensity, bloomWarmth);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 8. [DEFECTS] Defect simulation (dust, scratches, and hair)
    // ═══════════════════════════════════════════════════════════════════════════
    uint seedInt = uint(grainSeed * 65536.0);
    rgb = applyDust(rgb, uv, imageSize, dustIntensity, seedInt);
    rgb = applyScratches(rgb, uv, imageSize, scratchesIntensity, seedInt);
    rgb = applyHair(rgb, uv, imageSize, hairIntensity, seedInt);

    return float4(clamp(rgb, 0.0, 1.0), src.a);
}


// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Pyramid blend kernel
// ═══════════════════════════════════════════════════════════════════════════════

/// Four-level pyramid scatter blend used for Bloom/Halation preprocessing.
extern "C" float4 yoyoFilmPyramidBlend(
    coreimage::sample_t layer0,  // 1/2 resolution
    coreimage::sample_t layer1,  // 1/4 resolution
    coreimage::sample_t layer2,  // 1/8 resolution
    coreimage::sample_t layer3,  // 1/16 resolution
    float spread,
    coreimage::destination dest
) {
    // Cauchy-distribution weights
    float gamma = 0.3 + spread * 0.5;
    float w0 = cauchyPDF(0.0, gamma);
    float w1 = cauchyPDF(1.0, gamma);
    float w2 = cauchyPDF(2.0, gamma);
    float w3 = cauchyPDF(3.0, gamma);
    
    float totalWeight = w0 + w1 + w2 + w3;
    w0 /= totalWeight;
    w1 /= totalWeight;
    w2 /= totalWeight;
    w3 /= totalWeight;
    
    float3 blended = layer0.rgb * w0 + layer1.rgb * w1 + layer2.rgb * w2 + layer3.rgb * w3;
    float alpha = layer0.a * w0 + layer1.a * w1 + layer2.a * w2 + layer3.a * w3;
    
    return float4(blended, alpha);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Random light leak kernel
// ═══════════════════════════════════════════════════════════════════════════════

/// Soft domain warping to create organic cloud edges.
/// Use ultra-low-frequency noise to keep the shape soft and free of grid artifacts.
inline float softWarpedShape(float2 p, uint seed) {
    // Ultra-low-frequency domain warping that breaks regularity while staying soft.
    float2 warp = float2(
        softValueNoise(p * 0.5, seed),
        softValueNoise(p * 0.5 + float2(3.7, 2.1), seed + 100u)
    );
    float2 warped = p + (warp - 0.5) * 0.8;
    
    // Stack two layers of ultra-low-frequency noise.
    float n1 = softValueNoise(warped * 0.7, seed + 200u);
    float n2 = softValueNoise(warped * 1.3 + float2(5.0, 3.0), seed + 300u);
    
    return n1 * 0.65 + n2 * 0.35;
}

/// Glow falloff function that simulates natural light decay.
/// Use a mix of exponential and Gaussian falloff to create a soft glow edge.
inline float glowFalloff(float dist, float spread, float softness) {
    // Gaussian falloff for the soft core
    float gaussian = exp(-dist * dist / (spread * spread * 2.0));
    // Exponential falloff for long-tail spread
    float exponential = exp(-dist / spread);
    // Blend them so the core uses Gaussian falloff and the edge uses exponential falloff.
    return mix(gaussian, exponential, softness);
}

/// Random light leak generation
/// Design goal: simulate the aesthetic behavior of real film light leaks.
/// 
/// Behavior of real light leaks:
/// 1. Soft glow diffusion as light scatters through the emulsion.
/// 2. Natural color gradient from deep red-orange to bright yellow-white.
/// 3. Organic edge shapes that are irregular but smooth
/// 4. Gradient from the edges toward the center because light enters through gaps and mainly affects edge regions.
extern "C" float4 yoyoFilmLightLeak(
    coreimage::sample_t src,
    float intensity,
    float threshold,
    float spread,
    float warmth,
    float seed,
    float2 imageSize,
    float3 customColor,      // Custom color (0,0,0 means use the default)
    float position,          // Position preference (0-1: left to right)
    float saturation,        // Saturation (0.5-2.0)
    float contrast,          // Contrast (0-1)
    coreimage::destination dest
) {
    float3 rgb = src.rgb;
    if (intensity <= 0.001) return float4(rgb, src.a);

    float2 uv = dest.coord() / imageSize;
    uint seedInt = uint(seed * 65536.0);
    
    // === 1. Generate random parameters ===
    float rnd1 = fract(sin(seed * 12.9898) * 43758.5453);
    float rnd2 = fract(sin(seed * 78.233 + 0.5) * 43758.5453);
    float rnd3 = fract(sin(seed * 45.164 + 1.0) * 43758.5453);
    float rnd4 = fract(sin(seed * 93.421 + 1.5) * 43758.5453);
    
    // === 2. Compute distances to the edges ===
    // Compute the distance to each edge.
    float distLeft = uv.x;
    float distRight = 1.0 - uv.x;
    float distTop = 1.0 - uv.y;
    float distBottom = uv.y;
    
    // === 3. Configure the light leak region ===
    float totalLeak = 0.0;
    
    // Global shape warping at ultra-low frequency to keep the leak soft.
    float shapeNoise = softWarpedShape(uv * 2.0 + float2(seed * 2.0, 0.0), seedInt);
    float shapeNoise2 = softWarpedShape(uv * 1.5 + float2(0.0, seed * 2.0), seedInt + 500u);
    
    // Light leak penetration depth controlled by the spread parameter
    float maxPenetration = (0.15 + spread * 0.45) * (0.8 + rnd4 * 0.4);
    
    // === Position control: use the position parameter to place the light leak precisely ===
    // position mapping:
    // 0.11 = top-left, 0.22 = top, 0.33 = top-right
    // 0.15 = left, 0.5 = random, 0.85 = right
    // 0.44 = bottom-left, 0.55 = bottom, 0.66 = bottom-right
    
    float positionBias = position;
    
    // Determine the light leak type and position.
    if (abs(positionBias - 0.11) < 0.05) {
        // === top-leftcorner light leak ===
        float cornerDist = length(float2(distLeft * 0.7, distTop));
        float penetration = maxPenetration * 1.1 * (0.8 + shapeNoise * 0.4);
        float edgeFalloff = 1.0 - smoothstep(0.0, penetration, cornerDist);
        float organic = 0.7 + shapeNoise2 * 0.6;
        totalLeak = edgeFalloff * organic;
        
    } else if (abs(positionBias - 0.22) < 0.05) {
        // === toplight leak ===
        float penetration = maxPenetration * (0.8 + shapeNoise * 0.4);
        float edgeFalloff = 1.0 - smoothstep(0.0, penetration, distTop);
        
        // Irregular distribution along the horizontal axis.
        float horizontalPos = 0.2 + rnd2 * 0.6;
        float horizontalSpread = 0.3 + rnd3 * 0.4;
        float horizontalDist = abs(uv.x - horizontalPos);
        float horizontalFalloff = 1.0 - smoothstep(0.0, horizontalSpread, horizontalDist);
        
        float organic = 0.7 + shapeNoise * 0.6;
        totalLeak = edgeFalloff * horizontalFalloff * organic;
        
    } else if (abs(positionBias - 0.33) < 0.05) {
        // === top-rightcorner light leak ===
        float cornerDist = length(float2(distRight, distTop));
        float penetration = maxPenetration * 1.2 * (0.8 + shapeNoise * 0.4);
        float edgeFalloff = 1.0 - smoothstep(0.0, penetration, cornerDist);
        float organic = 0.7 + shapeNoise2 * 0.6;
        totalLeak = edgeFalloff * organic;
        
    } else if (abs(positionBias - 0.15) < 0.05) {
        // === left sidelight leak ===
        float penetration = maxPenetration * (0.8 + shapeNoise * 0.4);
        float edgeFalloff = 1.0 - smoothstep(0.0, penetration, distLeft);
        
        float verticalPos = 0.2 + rnd2 * 0.6;
        float verticalSpread = 0.3 + rnd3 * 0.4;
        float verticalDist = abs(uv.y - verticalPos);
        float verticalFalloff = 1.0 - smoothstep(0.0, verticalSpread, verticalDist);
        
        float organic = 0.7 + shapeNoise * 0.6;
        totalLeak = edgeFalloff * verticalFalloff * organic;
        
    } else if (abs(positionBias - 0.85) < 0.05) {
        // === right sidelight leak ===
        float penetration = maxPenetration * (0.8 + shapeNoise * 0.4);
        float edgeFalloff = 1.0 - smoothstep(0.0, penetration, distRight);
        
        float verticalPos = 0.2 + rnd2 * 0.6;
        float verticalSpread = 0.3 + rnd3 * 0.4;
        float verticalDist = abs(uv.y - verticalPos);
        float verticalFalloff = 1.0 - smoothstep(0.0, verticalSpread, verticalDist);
        
        float organic = 0.7 + shapeNoise * 0.6;
        totalLeak = edgeFalloff * verticalFalloff * organic;
        
    } else if (abs(positionBias - 0.44) < 0.05) {
        // === bottom-leftcorner light leak ===
        float cornerDist = length(float2(distLeft * 0.8, distBottom));
        float penetration = maxPenetration * 0.8;
        float edgeFalloff = 1.0 - smoothstep(0.0, penetration, cornerDist);
        float organic = 0.6 + shapeNoise2 * 0.4;
        totalLeak = edgeFalloff * organic;
        
    } else if (abs(positionBias - 0.55) < 0.05) {
        // === bottomlight leak ===
        float penetration = maxPenetration * (0.8 + shapeNoise * 0.4);
        float edgeFalloff = 1.0 - smoothstep(0.0, penetration, distBottom);
        
        float horizontalPos = 0.2 + rnd2 * 0.6;
        float horizontalSpread = 0.3 + rnd3 * 0.4;
        float horizontalDist = abs(uv.x - horizontalPos);
        float horizontalFalloff = 1.0 - smoothstep(0.0, horizontalSpread, horizontalDist);
        
        float organic = 0.7 + shapeNoise * 0.6;
        totalLeak = edgeFalloff * horizontalFalloff * organic;
        
    } else if (abs(positionBias - 0.66) < 0.05) {
        // === bottom-rightcorner light leak ===
        float cornerDist = length(float2(distRight * 0.8, distBottom));
        float penetration = maxPenetration * 0.8;
        float edgeFalloff = 1.0 - smoothstep(0.0, penetration, cornerDist);
        float organic = 0.6 + shapeNoise2 * 0.4;
        totalLeak = edgeFalloff * organic;
        
    } else {
        // === Random position, which is the default when position = 0.5 ===
        // Use random values to decide the light leak position.
        if (rnd1 < 0.35) {
            // === left sidelight leak ===
            float penetration = maxPenetration * (0.8 + shapeNoise * 0.4);
            float edgeFalloff = 1.0 - smoothstep(0.0, penetration, distLeft);
            
            float verticalPos = 0.2 + rnd2 * 0.6;
            float verticalSpread = 0.3 + rnd3 * 0.4;
            float verticalDist = abs(uv.y - verticalPos);
            float verticalFalloff = 1.0 - smoothstep(0.0, verticalSpread, verticalDist);
            
            float organic = 0.7 + shapeNoise * 0.6;
            totalLeak = edgeFalloff * verticalFalloff * organic;
            
        } else if (rnd1 < 0.7) {
            // === right sidelight leak ===
            float penetration = maxPenetration * (0.8 + shapeNoise * 0.4);
            float edgeFalloff = 1.0 - smoothstep(0.0, penetration, distRight);
            
            float verticalPos = 0.2 + rnd2 * 0.6;
            float verticalSpread = 0.3 + rnd3 * 0.4;
            float verticalDist = abs(uv.y - verticalPos);
            float verticalFalloff = 1.0 - smoothstep(0.0, verticalSpread, verticalDist);
            
            float organic = 0.7 + shapeNoise * 0.6;
            totalLeak = edgeFalloff * verticalFalloff * organic;
            
        } else if (rnd1 < 0.85) {
            // === top-rightcorner light leak ===
            float cornerDist = length(float2(distRight, distTop));
            float penetration = maxPenetration * 1.2 * (0.8 + shapeNoise * 0.4);
            float edgeFalloff = 1.0 - smoothstep(0.0, penetration, cornerDist);
            
            float organic = 0.7 + shapeNoise2 * 0.6;
            totalLeak = edgeFalloff * organic;
            
        } else {
            // === top-leftcorner light leak ===
            float cornerDist = length(float2(distLeft * 0.7, distTop));
            float penetration = maxPenetration * 1.1 * (0.8 + shapeNoise * 0.4);
            float edgeFalloff = 1.0 - smoothstep(0.0, penetration, cornerDist);
            
            float organic = 0.7 + shapeNoise2 * 0.6;
            totalLeak = edgeFalloff * organic;
        }
        
        // === Secondary light leak with 50% probability at the opposite diagonal ===
        if (rnd4 > 0.5) {
            float secondaryStrength = 0.3 + rnd3 * 0.2;
            
            float secondLeak = 0.0;
            if (rnd1 < 0.35) {
                // If the primary light leak is on the left, place the secondary leak at the bottom-right.
                float cornerDist = length(float2(distRight * 0.8, distBottom));
                float penetration = maxPenetration * 0.8;
                secondLeak = (1.0 - smoothstep(0.0, penetration, cornerDist)) * (0.6 + shapeNoise2 * 0.4);
            } else if (rnd1 < 0.7) {
                // If the primary light leak is on the right, place the secondary leak at the bottom-left.
                float cornerDist = length(float2(distLeft * 0.8, distBottom));
                float penetration = maxPenetration * 0.8;
                secondLeak = (1.0 - smoothstep(0.0, penetration, cornerDist)) * (0.6 + shapeNoise2 * 0.4);
            }
            
            totalLeak = max(totalLeak, secondLeak * secondaryStrength);
        }
    }
    
    // === 4. Apply the intensity curve using the threshold and contrast parameters ===
    float leakMask = totalLeak;
    
    // contrast controls how steep the gradient is
    // contrast 0 = soft gradient, contrast 1 = strong contrast
    float contrastPower = mix(2.5, 0.4, threshold);
    float contrastAdjust = mix(1.0, 2.5, contrast);
    leakMask = pow(leakMask, contrastPower / contrastAdjust);
    leakMask = clamp(leakMask * intensity * 2.0, 0.0, 1.0);
    
    // === 6. Generate the color, with support for custom color and saturation control ===
    // Real light leaks tend to move from deep dark red to orange-red and then to warm yellow-white.
    
    // Check whether a custom color is being used.
    bool useCustomColor = length(customColor) > 0.01;
    
    float3 leakColor;
    
    if (useCustomColor) {
        // === Use a custom color ===
        // Create a gradient from dark to bright based on intensity.
        float t = leakMask;
        float3 baseColor = customColor;
        
        // Dark version for the shadows
        float3 colorDeep = baseColor * 0.3;
        // Mid-brightness version
        float3 colorMid = baseColor * 0.7;
        // Bright version for highlights
        float3 colorBright = mix(baseColor, float3(1.0), 0.3);
        // Brightest version, near white
        float3 colorPeak = mix(baseColor, float3(1.0), 0.6);
        
        // Multi-stage smooth interpolation
        if (t < 0.25) {
            leakColor = mix(colorDeep, colorMid, t / 0.25);
        } else if (t < 0.55) {
            leakColor = mix(colorMid, colorBright, (t - 0.25) / 0.30);
        } else {
            leakColor = mix(colorBright, colorPeak, (t - 0.55) / 0.45);
        }
    } else {
        // === Use the default red-orange-yellow gradient ===
        float3 colorDeep   = float3(0.65, 0.05, 0.02);   // Deep dark red
        float3 colorLow    = float3(0.85, 0.15, 0.03);   // Dark red-orange
        float3 colorMid    = float3(1.0, 0.40, 0.08);    // Orange-red
        float3 colorHigh   = float3(1.0, 0.65, 0.25);    // Orange-yellow
        float3 colorBright = float3(1.0, 0.82, 0.50);    // Bright yellow
        float3 colorPeak   = float3(1.0, 0.92, 0.72);    // Warm white
        
        // Multi-stage smooth interpolation
        float t = leakMask;
        if (t < 0.15) {
            leakColor = mix(colorDeep, colorLow, t / 0.15);
        } else if (t < 0.35) {
            leakColor = mix(colorLow, colorMid, (t - 0.15) / 0.20);
        } else if (t < 0.55) {
            leakColor = mix(colorMid, colorHigh, (t - 0.35) / 0.20);
        } else if (t < 0.75) {
            leakColor = mix(colorHigh, colorBright, (t - 0.55) / 0.20);
        } else {
            leakColor = mix(colorBright, colorPeak, (t - 0.75) / 0.25);
        }
        
        // Apply warmth adjustment only to the default color set.
        // warmth 0 -> more red，warmth 1 -> more yellow-white
        float3 coldShift = float3(1.1, 0.8, 0.7);
        float3 warmShift = float3(0.9, 1.1, 1.3);
        leakColor = leakColor * mix(coldShift, warmShift, warmth);
    }
    
    // === Saturation control ===
    float leakLuma = dot(leakColor, LUMA_WEIGHTS);
    leakColor = mix(float3(leakLuma), leakColor, saturation);
    leakColor = clamp(leakColor, 0.0, 1.0);
    
    // Subtle warmth variation based on position.
    float positionTint = softValueNoise(uv * 0.8, seedInt + 2000u);
    leakColor.r *= 0.98 + positionTint * 0.04;
    leakColor.g *= 0.97 + positionTint * 0.03;
    
    // Random global warmth shift
    float tintRnd = fract(sin(seed * 78.233) * 43758.5453);
    if (tintRnd < 0.3) {
        // more red
        leakColor.r *= 1.05;
        leakColor.b *= 0.90;
    } else if (tintRnd > 0.7) {
        // Shift toward orange-yellow
        leakColor.g *= 1.05;
        leakColor.b *= 0.85;
    }
    
    // === 7. Blend modes ===
    // Screen blend - preserve image detail while simulating additive light.
    float3 screened = 1.0 - (1.0 - rgb) * (1.0 - leakColor * leakMask);
    
    // Apply a slight additive boost to bright areas.
    float3 additive = rgb + leakColor * leakMask * 0.15;
    
    // Blend the two modes, with Screen as the main one.
    float3 result = mix(screened, additive, 0.25);
    
    // Optional: slightly reduce saturation in light leak regions to add a faded look.
    float desatAmount = leakMask * 0.1;
    float resultLuma = dot(result, LUMA_WEIGHTS);
    result = mix(result, float3(resultLuma), desatAmount);
    
    return float4(clamp(result, 0.0, 1.0), src.a);
}
