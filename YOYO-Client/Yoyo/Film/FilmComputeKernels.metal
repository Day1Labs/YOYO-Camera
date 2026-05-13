// ═══════════════════════════════════════════════════════════════════════════════
// FilmComputeKernels.metal - Compute Shader optimized version of Film simulation
// ═══════════════════════════════════════════════════════════════════════════════
//
// Use Compute Shader to replace multiple CIFilter calls and significantly improve performance:
// - Separable Gaussian Blur (horizontal + vertical two passes)
// - Downsampling (Box Filter) / Upsampling (Bicubic Catmull-Rom)
// - Bloom/Halation highlight extraction
// - Pyramid layer blending
//
// ═══════════════════════════════════════════════════════════════════════════════

#include <metal_stdlib>
#include "FilmShaderCommon.h"
using namespace metal;

// MARK: - parameter structure

struct BloomExtractParams {
    float threshold;
    float knee;
    float preGain;
};

struct HalationExtractParams {
    float threshold;
    float softness;
    float warmth;
    float strength;
};

struct HalationColorParams {
    float3 tintCore;
    float3 tintMid;
    float3 tintEdge;
};

struct PyramidBlendParams {
    float spread;
    float warmth;
};

struct UpsampleParams {
    float scaleX;
    float scaleY;
};

// MARK: - Utility function

/// Calculate Gaussian weights
inline float gaussianWeight(float x, float sigma) {
    return exp(-x * x / (2.0 * sigma * sigma));
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Downsampling Kernel (2x)
// ═══════════════════════════════════════════════════════════════════════════════

kernel void downsample2x(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    // Source coordinates (2x)
    uint2 srcCoord = gid * 2;
    
    // 4-tap box filter
    float4 s00 = input.read(srcCoord);
    float4 s10 = input.read(srcCoord + uint2(1, 0));
    float4 s01 = input.read(srcCoord + uint2(0, 1));
    float4 s11 = input.read(srcCoord + uint2(1, 1));
    
    float4 result = (s00 + s10 + s01 + s11) * 0.25;
    output.write(result, gid);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Bicubic upsampling parameters
// ═══════════════════════════════════════════════════════════════════════════════

// Catmull-Rom spline weight function (Mitchell-Netravali B=0, C=0.5)
inline float catmullRomWeight(float t) {
    float at = abs(t);
    float at2 = at * at;
    float at3 = at2 * at;
    
    if (at < 1.0) {
        return 1.5 * at3 - 2.5 * at2 + 1.0;
    } else if (at < 2.0) {
        return -0.5 * at3 + 2.5 * at2 - 4.0 * at + 2.0;
    }
    return 0.0;
}

// Bilinear interpolation - for smooth blending at large magnifications
inline float4 bilinearSample(texture2d<float, access::read> tex, float2 coord, int width, int height) {
    float x = clamp(coord.x, 0.0f, float(width - 1));
    float y = clamp(coord.y, 0.0f, float(height - 1));
    
    int x0 = int(floor(x));
    int y0 = int(floor(y));
    int x1 = min(x0 + 1, width - 1);
    int y1 = min(y0 + 1, height - 1);
    
    float fx = x - float(x0);
    float fy = y - float(y0);
    
    float4 s00 = tex.read(uint2(x0, y0));
    float4 s10 = tex.read(uint2(x1, y0));
    float4 s01 = tex.read(uint2(x0, y1));
    float4 s11 = tex.read(uint2(x1, y1));
    
    float4 top = mix(s00, s10, fx);
    float4 bottom = mix(s01, s11, fx);
    return mix(top, bottom, fy);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Bicubic upsampling Kernel (any multiple, high quality)
// ═══════════════════════════════════════════════════════════════════════════════

kernel void upsampleBicubic(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant UpsampleParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    int srcWidth = input.get_width();
    int srcHeight = input.get_height();
    
    // Calculate floating point coordinates in the source texture
    // Use center alignment: (gid + 0.5) / outSize * inSize - 0.5
    float srcX = (float(gid.x) + 0.5) / params.scaleX - 0.5;
    float srcY = (float(gid.y) + 0.5) / params.scaleY - 0.5;
    
    // For large magnifications (>4x), use bilinear interpolation to avoid blocking artifacts
    // Bicubic will produce blocks due to boundary clamp when the source image is too small.
    float maxScale = max(params.scaleX, params.scaleY);
    if (maxScale > 6.0 || srcWidth < 24 || srcHeight < 24) {
        float4 result = bilinearSample(input, float2(srcX, srcY), srcWidth, srcHeight);
        output.write(result, gid);
        return;
    }
    
    // Integer part and decimal part
    int ix = int(floor(srcX));
    int iy = int(floor(srcY));
    float fx = srcX - float(ix);
    float fy = srcY - float(iy);
    
    // 4x4 Bicubic sampling
    float4 result = float4(0.0);
    float weightSum = 0.0;
    
    // Precompute Y-direction weights
    float wyArr[4];
    wyArr[0] = catmullRomWeight(fx + 1.0);  // j = -1: t = fx - (-1) = fx + 1
    wyArr[1] = catmullRomWeight(fx);         // j = 0:  t = fx - 0 = fx
    wyArr[2] = catmullRomWeight(fx - 1.0);   // j = 1:  t = fx - 1
    wyArr[3] = catmullRomWeight(fx - 2.0);   // j = 2:  t = fx - 2
    
    for (int j = -1; j <= 2; j++) {
        // Weight: distance = fy - j
        float wy = catmullRomWeight(fy - float(j));
        int sy = clamp(iy + j, 0, srcHeight - 1);
        
        for (int i = -1; i <= 2; i++) {
            // Weight: distance = fx - i
            float wx = catmullRomWeight(fx - float(i));
            int sx = clamp(ix + i, 0, srcWidth - 1);
            
            float weight = wx * wy;
            result += input.read(uint2(sx, sy)) * weight;
            weightSum += weight;
        }
    }
    
    // normalize and clamp against negative values
    result = result / max(weightSum, 1e-6);
    result = max(result, float4(0.0));
    
    output.write(result, gid);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Separable Gaussian Blur - Horizontal direction
// ═══════════════════════════════════════════════════════════════════════════════

kernel void gaussianBlurHorizontal(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float& radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    int width = input.get_width();
    int kernelRadius = int(ceil(radius * 2.5)); // 2.5 sigma covers 99% of Gaussian distributions
    float sigma = max(radius / 2.5, 0.5);
    
    float4 sum = float4(0.0);
    float weightSum = 0.0;
    
    for (int i = -kernelRadius; i <= kernelRadius; i++) {
        int x = clamp(int(gid.x) + i, 0, width - 1);
        float weight = gaussianWeight(float(i), sigma);
        sum += input.read(uint2(x, gid.y)) * weight;
        weightSum += weight;
    }
    
    output.write(sum / weightSum, gid);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Separable Gaussian Blur - Vertical direction
// ═══════════════════════════════════════════════════════════════════════════════

kernel void gaussianBlurVertical(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float& radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    int height = input.get_height();
    int kernelRadius = int(ceil(radius * 2.5));
    float sigma = max(radius / 2.5, 0.5);
    
    float4 sum = float4(0.0);
    float weightSum = 0.0;
    
    for (int i = -kernelRadius; i <= kernelRadius; i++) {
        int y = clamp(int(gid.y) + i, 0, height - 1);
        float weight = gaussianWeight(float(i), sigma);
        sum += input.read(uint2(gid.x, y)) * weight;
        weightSum += weight;
    }
    
    output.write(sum / weightSum, gid);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Bloom highlight extraction Kernel
// ═══════════════════════════════════════════════════════════════════════════════

kernel void bloomExtractCompute(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant BloomExtractParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float4 src = input.read(gid);
    float3 rgb = max(src.rgb * params.preGain, float3(0.0));
    float luma = dot(rgb, LUMA_WEIGHTS);
    
    // Karis averaging: reduce the weight of extremely bright pixels (anti-firefly)
    float karisWeight = 1.0 / (1.0 + luma);
    
    // Soft threshold extraction
    float w = clamp((luma - params.threshold) / max(params.knee, 1e-5), 0.0, 1.0);
    w = w * w * (3.0 - 2.0 * w); // Hermite Smooth
    
    // Keep highlight color and slightly increase saturation (reduce gain to prevent fluorescence)
    float satBoost = 1.0 + 0.05 * w;
    float3 saturated = mix(float3(luma), rgb, satBoost);
    
    float3 bright = saturated * w * karisWeight;
    
    output.write(float4(bright, w), gid);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Halation highlight extraction Kernel (with emulsion layer penetration model and custom color)
// ═══════════════════════════════════════════════════════════════════════════════

kernel void halationExtractCompute(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant HalationExtractParams& params [[buffer(0)]],
    constant HalationColorParams& colorParams [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float4 src = input.read(gid);
    float3 rgb = src.rgb;
    float luma = dot(rgb, LUMA_WEIGHTS);
    
    // === Emulsion layer penetration model ===
    float penetratedEnergy = calculatePenetratedEnergy(rgb, luma, params.threshold);

    // === Rem-Jet fail gating (smoother) ===
    float energyMask = remJetFailure(penetratedEnergy, params.threshold, params.softness);

    // Rebound energy (applied strength coefficient) + rolloff suppresses popping
    float bouncedEnergy = penetratedEnergy * energyMask * params.strength;
    float rolledEnergy = halationEnergyRolloff(bouncedEnergy);
    
    // === Three-stage halo hue (use custom colors) ===
    float3 halationColor = getHalationColorWithTint(
        rolledEnergy,
        colorParams.tintCore,
        colorParams.tintMid,
        colorParams.tintEdge
    );
    halationColor *= rolledEnergy;

    output.write(float4(halationColor, rolledEnergy), gid);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Pyramid Mixing Kernel (Cauchy Distribution Weights)
// ═══════════════════════════════════════════════════════════════════════════════

kernel void pyramidBlendCompute(
    texture2d<float, access::read> layer0 [[texture(0)]],
    texture2d<float, access::read> layer1 [[texture(1)]],
    texture2d<float, access::read> layer2 [[texture(2)]],
    texture2d<float, access::read> layer3 [[texture(3)]],
    texture2d<float, access::write> output [[texture(4)]],
    constant PyramidBlendParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    // Read four layers
    float4 l0 = layer0.read(gid);
    float4 l1 = layer1.read(gid);
    float4 l2 = layer2.read(gid);
    float4 l3 = layer3.read(gid);
    
    // Calculate Cauchy distribution weights
    float4 weights = calculateCauchyWeights(params.spread);
    
    // weighted synthesis
    float3 scattered = l0.rgb * weights.x + l1.rgb * weights.y + l2.rgb * weights.z + l3.rgb * weights.w;
    float energy = l0.a * weights.x + l1.a * weights.y + l2.a * weights.z + l3.a * weights.w;
    
    // Further reduce the convergence ratio and retain the red color
    float3 converged = applySaturationConvergence(scattered, energy, params.warmth);
    scattered = mix(scattered, converged, 0.15);
    
    output.write(float4(scattered, energy), gid);
}
