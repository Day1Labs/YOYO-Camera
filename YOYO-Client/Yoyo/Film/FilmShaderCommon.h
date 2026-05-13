// ═══════════════════════════════════════════════════════════════════════════════
// FilmShaderCommon.h - Shared definitions for film emulation Metal shaders
// ═══════════════════════════════════════════════════════════════════════════════
//
// Contains items shared by FilmEmulation.metal and FilmComputeKernels.metal:
// - Constant definitions
// - Utility functions
// - Physical model functions
//
// ═══════════════════════════════════════════════════════════════════════════════

#ifndef FilmShaderCommon_h
#define FilmShaderCommon_h

#include <metal_stdlib>
using namespace metal;

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Constant Definitions
// ═══════════════════════════════════════════════════════════════════════════════

// Rec. 709 luma weights
constant float3 LUMA_WEIGHTS = float3(0.2126, 0.7152, 0.0722);

// Film emulsion penetration coefficients (based on wavelength penetration)
constant float RED_PENETRATION = 0.88;
constant float GREEN_PENETRATION = 0.10;
constant float BLUE_PENETRATION = 0.02;

// MARK: - Physical Photochemical Model Constants
// Maximum film density (D-max)
constant float FILM_D_MAX = 3.2;
// Minimum film density (D-min/Base Fog)
constant float FILM_D_MIN = 0.08;

// Default halation tint values (fallback only; actual values should come from the film preset)
constant float3 DEFAULT_HALATION_TINT_CORE = float3(1.0, 0.97, 0.93);
constant float3 DEFAULT_HALATION_TINT_MID  = float3(1.0, 0.32, 0.12);
constant float3 DEFAULT_HALATION_TINT_EDGE = float3(0.92, 0.45, 0.18);

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Utility Functions
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - Physical Model Utility Functions

/// Cauchy-Lorentz distribution (real optical scattering)
inline float cauchyPDF(float x, float gamma) {
    return gamma * gamma / (x * x + gamma * gamma);
}

/// Smooth threshold function
inline float smoothThreshold(float x, float threshold, float softness) {
    return smoothstep(threshold - softness * 0.5, threshold + softness * 0.5, x);
}

/// ACES tone mapping
inline float3 acesTonemap(float3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Halation Physical Model
// ═══════════════════════════════════════════════════════════════════════════════

/// Computes the light energy that penetrates to the film base
/// Balances skin tone protection with halation from bright light sources such as LEDs and neon lights
inline float calculatePenetratedEnergy(float3 rgb, float luma, float lumaThreshold) {
    // 1. Luminance gating: the threshold is controlled uniformly by the external physical system
    float lumaFactor = max(0.0, luma - lumaThreshold) / (1.0 - lumaThreshold);
    
    // 2. Red dominance: compute the advantage of the red channel over the others
    float redDominance = max(0.0, rgb.r - max(rgb.g, rgb.b));
    
    // 3. Bright white light detection: white sources such as LEDs and fluorescent lights
    float minChannel = min(rgb.r, min(rgb.g, rgb.b));
    float whiteBrightness = minChannel * smoothstep(0.4, 0.8, luma);
    
    // 4. Combined energy computation
    float energy = (rgb.r * RED_PENETRATION) * (0.25 + 0.75 * pow(lumaFactor, 1.2));
    energy += pow(redDominance, 1.3) * 1.0;
    energy += whiteBrightness * 1.0;
    
    return energy;
}

/// Rem-Jet anti-halation layer failure simulation
inline float remJetFailure(float energy, float threshold, float softness) {
    // Smoother Rem-Jet failure gating to avoid abrupt activation that causes white blowout
    float mask = smoothThreshold(energy, threshold, softness);
    // Boost mid-range response while suppressing harsh clipping in highlights
    float mid = pow(mask, 1.1);
    float high = pow(mask, 2.2);
    return mix(mid, high, 0.35);
}

/// Energy rolloff: limits blown highlights in high-energy regions while preserving detail
inline float halationEnergyRolloff(float energy) {
    // Reinhard-like soft shoulder: energy / (1 + k*energy)
    const float k = 1.0;
    return min(energy / (1.0 + k * energy), 1.0);
}

/// Gets the three-band halation color using custom tints
/// tintCore: core region color (high-energy region near the light source)
/// tintMid: middle region color (the most characteristic color band)
/// tintEdge: edge region color (low-energy region, farthest scattering extent)
inline float3 getHalationColorWithTint(
    float bouncedEnergy,
    float3 tintCore,
    float3 tintMid,
    float3 tintEdge
) {
    // Nonlinear segmentation: low energy favors Edge, mid energy strengthens Mid, high energy approaches Core
    float e = clamp(bouncedEnergy, 0.0, 1.0);
    float midMask = smoothstep(0.25, 0.65, e);
    float highMask = smoothstep(0.55, 1.0, e);

    float3 cEdge = tintEdge;
    float3 cMid = mix(tintEdge, tintMid, midMask);
    float3 cCore = mix(tintMid, tintCore, highMask);

    // Let weights transition smoothly with energy to avoid sudden pink or white shifts
    float wEdge = 1.0 - midMask;
    float wMid = midMask * (1.0 - highMask);
    float wCore = highMask;
    float wSum = wEdge + wMid + wCore + 1e-4;

    return (cEdge * wEdge + cMid * wMid + cCore * wCore) / wSum;
}

/// Gets the three-band halation color using default tints
inline float3 getHalationColor(float bouncedEnergy) {
    return getHalationColorWithTint(
        bouncedEnergy,
        DEFAULT_HALATION_TINT_CORE,
        DEFAULT_HALATION_TINT_MID,
        DEFAULT_HALATION_TINT_EDGE
    );
}

/// Saturation convergence for halation color
inline float3 applySaturationConvergence(float3 halationColor, float energyLevel, float warmth) {
    float intensity = max(max(halationColor.r, halationColor.g), halationColor.b);

    // Energy-based core and edge masks, smoother and adaptive to energy
    float coreMask = smoothstep(0.45, 0.9, intensity) * smoothstep(0.25, 0.8, energyLevel);
    float edgeMask = smoothstep(0.0, 0.45, intensity) * (1.0 - coreMask);

    // The core region trends toward warm white, while the edge region keeps red saturation
    float coreDesaturation = 0.45 + warmth * 0.35;
    float3 warmWhite = float3(intensity, intensity * 0.94, intensity * 0.86);
    float3 result = mix(halationColor, warmWhite, coreMask * coreDesaturation * 0.65);

    // Edge saturation reinforcement decreases with energy to avoid an overall pink cast at high energy
    float edgeSaturation = (0.45 + (1.0 - warmth) * 0.45) * (1.0 - coreMask * 0.6);
    result.r *= 1.0 + edgeMask * edgeSaturation * 0.35;
    result.g *= 1.0 - edgeMask * edgeSaturation * 0.12;
    result.b *= 1.0 - edgeMask * edgeSaturation * 0.08;

    return result;
}

/// Computes Cauchy distribution weights (returns normalized four-layer weights)
inline float4 calculateCauchyWeights(float spread) {
    float gamma = 0.3 + spread * 0.5;

    // Relative distances of the four scattering layers
    float d0 = 0.1, d1 = 0.35, d2 = 0.7, d3 = 1.1;

    // Compute and tune Cauchy distribution weights: reduce near-layer bias and increase far-layer presence
    float w0 = cauchyPDF(d0, gamma) * 1.15;
    float w1 = cauchyPDF(d1, gamma) * 1.05;
    float w2 = cauchyPDF(d2, gamma) * 1.00;
    float w3 = cauchyPDF(d3, gamma) * 0.85;

    // Normalize
    float sum = w0 + w1 + w2 + w3 + 1e-6;
    return float4(w0, w1, w2, w3) / sum;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Grain Utility Functions
// ═══════════════════════════════════════════════════════════════════════════════

/// High-quality 2D hash (based on xxHash)
inline uint hash2D_uint(uint2 p, uint seed) {
    uint h = seed;
    h ^= p.x * 374761393u;
    h = (h << 17) | (h >> 15);
    h *= 1103515245u;
    h ^= p.y * 2654435761u;
    h = (h << 13) | (h >> 19);
    h *= 2246822519u;
    h ^= h >> 16;
    h *= 2654435761u;
    h ^= h >> 16;
    return h;
}

/// Floating-point hash (returns [0, 1)) - 1D version
inline float hashFloat(uint seed) {
    uint h = seed;
    h ^= h >> 16;
    h *= 0x85ebca6bu;
    h ^= h >> 13;
    h *= 0xc2b2ae35u;
    h ^= h >> 16;
    return float(h) / 4294967296.0;
}

/// Floating-point hash (returns [0, 1))
inline float hashFloat(uint2 p, uint seed) {
    return float(hash2D_uint(p, seed)) / 4294967296.0;
}

/// Floating-point hash (returns [-0.5, 0.5))
inline float hashFloatSigned(uint2 p, uint seed) {
    return hashFloat(p, seed) - 0.5;
}

/// Soft light leak noise - ultra-low-frequency value noise for organic shapes
/// Core idea: real light leaks are soft light diffusion, not high-frequency noise
inline float softValueNoise(float2 p, uint seed) {
    float2 i = floor(p);
    float2 f = fract(p);
    
    // Quintic interpolation for maximum smoothness
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    
    uint2 pi = uint2(i);
    float a = hashFloat(pi, seed);
    float b = hashFloat(pi + uint2(1, 0), seed);
    float c = hashFloat(pi + uint2(0, 1), seed);
    float d = hashFloat(pi + uint2(1, 1), seed);
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Gradient vector
inline float2 gradientVector(uint2 p, uint seed) {
    uint h = hash2D_uint(p, seed);
    float angle = float(h) * (6.28318530718 / 4294967296.0);
    return float2(cos(angle), sin(angle));
}

/// Gradient noise (more natural organic texture)
inline float gradientNoise(float2 p, uint seed) {
    float2 i = floor(p);
    float2 f = fract(p);
    
    // Quintic interpolation
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    
    uint2 pi = uint2(i);
    
    float2 ga = gradientVector(pi, seed);
    float2 gb = gradientVector(pi + uint2(1, 0), seed);
    float2 gc = gradientVector(pi + uint2(0, 1), seed);
    float2 gd = gradientVector(pi + uint2(1, 1), seed);
    
    float va = dot(ga, f - float2(0, 0));
    float vb = dot(gb, f - float2(1, 0));
    float vc = dot(gc, f - float2(0, 1));
    float vd = dot(gd, f - float2(1, 1));
    
    return mix(mix(va, vb, u.x), mix(vc, vd, u.x), u.y) * 0.7071 + 0.5;
}

/// Soft Light blend mode (W3C standard)
inline float blendSoftLight(float base, float blend) {
    return (blend < 0.5) ?
        (2.0 * base * blend + base * base * (1.0 - 2.0 * blend)) :
        (sqrt(base) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend));
}

inline float3 blendSoftLight3(float3 base, float3 blend) {
    return float3(
        blendSoftLight(base.r, blend.r),
        blendSoftLight(base.g, blend.g),
        blendSoftLight(base.b, blend.b)
    );
}

#endif /* FilmShaderCommon_h */
