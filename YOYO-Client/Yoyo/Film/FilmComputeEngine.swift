import CoreImage
import Metal

/// Metal Compute Shader Engine - for high performance Bloom/Halation layer generation
final class FilmComputeEngine {
    static let shared = FilmComputeEngine()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let linearColorSpace: CGColorSpace

    // Compute Pipelines
    private let blurHPipeline: MTLComputePipelineState?
    private let blurVPipeline: MTLComputePipelineState?
    private let downsamplePipeline: MTLComputePipelineState?
    private let upsampleBicubicPipeline: MTLComputePipelineState?
    private let bloomExtractPipeline: MTLComputePipelineState?
    private let halationExtractPipeline: MTLComputePipelineState?
    private let pyramidBlendPipeline: MTLComputePipelineState?

    var isAvailable: Bool {
        blurHPipeline != nil && blurVPipeline != nil && downsamplePipeline != nil && upsampleBicubicPipeline != nil
    }

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }

        self.device = device
        commandQueue = queue
        linearColorSpace =
            CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ??
            CGColorSpace(name: CGColorSpace.linearSRGB) ??
            CGColorSpaceCreateDeviceRGB()
        ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: linearColorSpace,
            .outputColorSpace: linearColorSpace,
            .cacheIntermediates: true,
        ])

        func makePipeline(_ name: String) -> MTLComputePipelineState? {
            guard let fn = library.makeFunction(name: name) else { return nil }
            return try? device.makeComputePipelineState(function: fn)
        }

        blurHPipeline = makePipeline("gaussianBlurHorizontal")
        blurVPipeline = makePipeline("gaussianBlurVertical")
        downsamplePipeline = makePipeline("downsample2x")
        upsampleBicubicPipeline = makePipeline("upsampleBicubic")
        bloomExtractPipeline = makePipeline("bloomExtractCompute")
        halationExtractPipeline = makePipeline("halationExtractCompute")
        pyramidBlendPipeline = makePipeline("pyramidBlendCompute")
    }

    // MARK: - Public API

    func generateBloomLayer(from input: CIImage, intensity: Float, threshold: Float, spread: Float) -> CIImage? {
        guard isAvailable else { return nil }
        let extent = input.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        guard let inputTex = makeTexture(from: input),
              let cmd = commandQueue.makeCommandBuffer() else { return nil }

        let w = Int(extent.width), h = Int(extent.height)
        let baseRadius: Float = 8.0 + spread * 20.0

        // 1. Highlight extraction
        guard let extracted = makeTexture(w, h),
              let extractPipeline = bloomExtractPipeline else { return nil }

        encode(cmd, extractPipeline, [inputTex, extracted]) { enc in
            var p = (threshold, Float(0.2), 1.0 + intensity * 0.5)
            enc.setBytes(&p, length: 12, index: 0)
        }

        // 2. Downsampling Pyramid
        guard let half = makeTexture(w / 2, h / 2),
              let quarter = makeTexture(w / 4, h / 4),
              let eighth = makeTexture(w / 8, h / 8),
              let sixteenth = makeTexture(w / 16, h / 16) else { return nil }

        encodeDownsample(cmd, extracted, half)
        encodeDownsample(cmd, half, quarter)
        encodeDownsample(cmd, quarter, eighth)
        encodeDownsample(cmd, eighth, sixteenth)

        // 3. Blurred layers
        guard let blur0 = makeTexture(w / 2, h / 2),
              let blur1 = makeTexture(w / 4, h / 4),
              let blur2 = makeTexture(w / 8, h / 8),
              let blur3 = makeTexture(w / 16, h / 16) else { return nil }

        encodeBlur(cmd, half, blur0, baseRadius * 0.15 / 2)
        encodeBlur(cmd, quarter, blur1, baseRadius * 0.125 / 4)
        encodeBlur(cmd, eighth, blur2, baseRadius * 0.0875 / 8)
        encodeBlur(cmd, sixteenth, blur3, baseRadius * 0.0625 / 16)

        // 4. Direct upsampling to native resolution (Bicubic interpolation)
        guard let up0 = makeTexture(w, h),
              let up1 = makeTexture(w, h),
              let up2 = makeTexture(w, h),
              let up3 = makeTexture(w, h) else { return nil }

        encodeUpsampleBicubic(cmd, blur0, up0, scaleX: 2.0, scaleY: 2.0)
        encodeUpsampleBicubic(cmd, blur1, up1, scaleX: 4.0, scaleY: 4.0)
        encodeUpsampleBicubic(cmd, blur2, up2, scaleX: 8.0, scaleY: 8.0)
        encodeUpsampleBicubic(cmd, blur3, up3, scaleX: 16.0, scaleY: 16.0)

        // 5. Pyramid Mixing
        guard let result = makeSharedTexture(w, h),
              let blendPipeline = pyramidBlendPipeline else { return nil }

        encode(cmd, blendPipeline, [up0, up1, up2, up3, result]) { enc in
            var p = (spread, Float(0.5))
            enc.setBytes(&p, length: 8, index: 0)
        }

        cmd.commit()
        cmd.waitUntilCompleted()

        return CIImage(mtlTexture: result, options: [.colorSpace: linearColorSpace])?
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
    }

    func generateHalationLayer(
        from input: CIImage,
        intensity: Float,
        threshold: Float,
        spread: Float,
        warmth: Float,
        tintCore: SIMD3<Float> = SIMD3<Float>(1.0, 0.97, 0.93),
        tintMid: SIMD3<Float> = SIMD3<Float>(1.0, 0.32, 0.12),
        tintEdge: SIMD3<Float> = SIMD3<Float>(0.92, 0.45, 0.18),
        strength: Float = 1.0
    ) -> CIImage? {
        guard isAvailable else { return nil }
        let extent = input.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        guard let inputTex = makeTexture(from: input),
              let cmd = commandQueue.makeCommandBuffer() else { return nil }

        let w = Int(extent.width), h = Int(extent.height)
        let minDim = Float(min(w, h))
        let baseRadius = min(minDim / 80.0, 32.0)
        let sf = 0.55 + spread * 0.9 // greater spread
        let rf = 0.7 + 0.45 * intensity // Enhanced scattering radius increases with intensity

        // 1. Halation extraction (with custom color)
        guard let extracted = makeTexture(w, h),
              let extractPipeline = halationExtractPipeline else { return nil }

        encode(cmd, extractPipeline, [inputTex, extracted]) { enc in
            // Basic parameters: threshold, softness, warmth, strength
            let softness = Float(0.16 + spread * 0.12)
            var baseParams = (threshold, softness, warmth, strength)
            enc.setBytes(&baseParams, length: 16, index: 0)
            // Color parameters: tintCore, tintMid, tintEdge (3 floats each)
            var colorParams = (
                tintCore.x, tintCore.y, tintCore.z,
                tintMid.x, tintMid.y, tintMid.z,
                tintEdge.x, tintEdge.y, tintEdge.z
            )
            enc.setBytes(&colorParams, length: 36, index: 1)
        }

        // 2. Four-layer scattering (downsampling)
        guard let half = makeTexture(w / 2, h / 2),
              let quarter = makeTexture(w / 4, h / 4),
              let eighth = makeTexture(w / 8, h / 8),
              let sixteenth = makeTexture(w / 16, h / 16) else { return nil }

        encodeDownsample(cmd, extracted, half)
        encodeDownsample(cmd, half, quarter)
        encodeDownsample(cmd, quarter, eighth)
        encodeDownsample(cmd, eighth, sixteenth)

        // 3. Blurred layers
        guard let l0 = makeTexture(w / 2, h / 2),
              let l1 = makeTexture(w / 4, h / 4),
              let l2 = makeTexture(w / 8, h / 8),
              let l3 = makeTexture(w / 16, h / 16) else { return nil }

        encodeBlur(cmd, half, l0, baseRadius * 0.32 * sf * rf / 2)
        encodeBlur(cmd, quarter, l1, min(baseRadius * 1.9 * sf * rf, 56) / 4)
        encodeBlur(cmd, eighth, l2, min(baseRadius * 6.5 * sf * rf, 160) / 8)
        encodeBlur(cmd, sixteenth, l3, min(baseRadius * 16 * sf * rf, 360) / 16)

        // 4. Direct upsampling to native resolution (Bicubic interpolation)
        guard let l0Full = makeTexture(w, h),
              let l1Full = makeTexture(w, h),
              let l2Full = makeTexture(w, h),
              let l3Full = makeTexture(w, h) else { return nil }

        encodeUpsampleBicubic(cmd, l0, l0Full, scaleX: 2.0, scaleY: 2.0)
        encodeUpsampleBicubic(cmd, l1, l1Full, scaleX: 4.0, scaleY: 4.0)
        encodeUpsampleBicubic(cmd, l2, l2Full, scaleX: 8.0, scaleY: 8.0)
        encodeUpsampleBicubic(cmd, l3, l3Full, scaleX: 16.0, scaleY: 16.0)

        // 5. Pyramid Mixing
        guard let result = makeSharedTexture(w, h),
              let blendPipeline = pyramidBlendPipeline else { return nil }

        encode(cmd, blendPipeline, [l0Full, l1Full, l2Full, l3Full, result]) { enc in
            var p = (spread, warmth)
            enc.setBytes(&p, length: 8, index: 0)
        }

        cmd.commit()
        cmd.waitUntilCompleted()

        return CIImage(mtlTexture: result, options: [.colorSpace: linearColorSpace])?
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
    }

    // MARK: - Private Helpers

    private func makeTexture(_ w: Int, _ h: Int) -> MTLTexture? {
        guard w > 0, h > 0 else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    private func makeSharedTexture(_ w: Int, _ h: Int) -> MTLTexture? {
        guard w > 0, h > 0 else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        return device.makeTexture(descriptor: desc)
    }

    private func makeTexture(from image: CIImage) -> MTLTexture? {
        guard let tex = makeTexture(Int(image.extent.width), Int(image.extent.height)) else { return nil }
        ciContext.render(image, to: tex, commandBuffer: nil, bounds: image.extent, colorSpace: linearColorSpace)
        return tex
    }

    private func encode(_ cmd: MTLCommandBuffer, _ pipeline: MTLComputePipelineState, _ textures: [MTLTexture], setup: ((MTLComputeCommandEncoder) -> Void)? = nil) {
        guard let enc = cmd.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(pipeline)
        for (i, tex) in textures.enumerated() {
            enc.setTexture(tex, index: i)
        }
        setup?(enc)
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let out = textures.last!
        enc.dispatchThreadgroups(MTLSize(width: (out.width + 15) / 16, height: (out.height + 15) / 16, depth: 1), threadsPerThreadgroup: tg)
        enc.endEncoding()
    }

    private func encodeDownsample(_ cmd: MTLCommandBuffer, _ input: MTLTexture, _ output: MTLTexture) {
        guard let p = downsamplePipeline else { return }
        encode(cmd, p, [input, output])
    }

    private func encodeUpsampleBicubic(_ cmd: MTLCommandBuffer, _ input: MTLTexture, _ output: MTLTexture, scaleX: Float, scaleY: Float) {
        guard let p = upsampleBicubicPipeline else { return }
        encode(cmd, p, [input, output]) { enc in
            var params = (scaleX, scaleY)
            enc.setBytes(&params, length: 8, index: 0)
        }
    }

    private func encodeBlur(_ cmd: MTLCommandBuffer, _ input: MTLTexture, _ output: MTLTexture, _ radius: Float) {
        guard let hP = blurHPipeline, let vP = blurVPipeline,
              let temp = makeTexture(input.width, input.height) else { return }

        var r = radius
        encode(cmd, hP, [input, temp]) { $0.setBytes(&r, length: 4, index: 0) }
        encode(cmd, vP, [temp, output]) { $0.setBytes(&r, length: 4, index: 0) }
    }
}
