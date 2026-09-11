import Foundation
import Metal
import MetalKit
import CoreVideo
import simd


/// Draws the latest captured desktop frame as a perspective-tilted, blurred, shaded quad.
final class BendRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let blurPipeline: MTLRenderPipelineState
    private let diffusionPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var textureCache: CVMetalTextureCache?

    private let lock = NSLock()
    private var pending: CVPixelBuffer?
    private var mipTexture: MTLTexture?
    /// Light blur of the desktop at half resolution (the picture near the hinge).
    private var softBlur: MTLTexture?
    /// Heavy blur at quarter resolution (the picture far from the hinge, and the backdrop).
    private var heavyBlur: MTLTexture?
    /// Blur targets and horizontal-pass scratch textures, keyed by mip level.
    private var blurTargets: [String: MTLTexture] = [:]
    private var blurScratch: [Int: MTLTexture] = [:]
    /// A Gaussian scale space for Duo. Built once per captured frame; lid motion only changes LOD.
    private var diffusionTexture: MTLTexture?
    private var diffusionScratch: [Int: MTLTexture] = [:]
    private var diffusionIsCurrent = false
    private(set) var hasFrame = false

    /// Called at the start of every frame to fetch the current tilt/blur/shadow values.
    var uniformsProvider: (() -> BendUniforms)?

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        commandQueue = queue

        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(source: BendShaders.source, options: options),
              let vertex = library.makeFunction(name: "bend_vertex"),
              let fragment = library.makeFunction(name: "bend_fragment")
        else {
            NSLog("OpenBend: failed to compile shaders")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.pipeline = pipeline

        let blurDescriptor = MTLRenderPipelineDescriptor()
        blurDescriptor.vertexFunction = vertex
        blurDescriptor.fragmentFunction = library.makeFunction(name: "blur_fragment")
        blurDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let blurPipeline = try? device.makeRenderPipelineState(descriptor: blurDescriptor) else { return nil }
        self.blurPipeline = blurPipeline

        blurDescriptor.fragmentFunction = library.makeFunction(name: "diffusion_fragment")
        guard let diffusionPipeline = try? device.makeRenderPipelineState(descriptor: blurDescriptor) else { return nil }
        self.diffusionPipeline = diffusionPipeline

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }
        self.sampler = sampler

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        super.init()
    }

    /// Hand over a captured frame. Safe to call from any thread.
    func submit(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        pending = pixelBuffer
        hasFrame = true
        lock.unlock()
    }

    /// Forget the current frame, e.g. when capture stops, so a stale desktop is never shown.
    func reset() {
        lock.lock()
        pending = nil
        hasFrame = false
        diffusionIsCurrent = false
        lock.unlock()
    }

    private func takePending() -> CVPixelBuffer? {
        lock.lock()
        defer { pending = nil; lock.unlock() }
        return pending
    }

    private func ensureMipTexture(width: Int, height: Int) {
        if let mipTexture, mipTexture.width == width, mipTexture.height == height { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: true)
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        mipTexture = device.makeTexture(descriptor: descriptor)
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        var keepAlive: CVMetalTexture?

        if let pixelBuffer = takePending(), let cache = textureCache {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            var cvTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
            if let cvTexture, let source = CVMetalTextureGetTexture(cvTexture) {
                upload(source, using: commandBuffer)
                keepAlive = cvTexture
            }
        }

        guard let passDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            commandBuffer.commit()
            return
        }
        let uniforms = uniformsProvider?() ?? .identity
        encodeBlurs(uniforms, using: commandBuffer)
        encode(uniforms, into: passDescriptor, using: commandBuffer)

        if let cache = textureCache {
            commandBuffer.addCompletedHandler { _ in
                _ = keepAlive
                CVMetalTextureCacheFlush(cache, 0)
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: Encoding

    /// Copies `source` (level 0) into the mipmapped working texture and regenerates its mips.
    private func upload(_ source: MTLTexture, using commandBuffer: MTLCommandBuffer) {
        ensureMipTexture(width: source.width, height: source.height)
        guard let destination = mipTexture, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
                  to: destination, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.generateMipmaps(for: destination)
        blit.endEncoding()
        diffusionIsCurrent = false
        hasFrame = true
    }

    private func makeBlurTexture(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func encodeBlurPass(from source: MTLTexture, to destination: MTLTexture, direction: SIMD2<Float>, sigma: Float, using commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        // 33 taps reach ±3σ when spaced σ/5 apart; the level is chosen so σ ≤ 6 texels,
        // which keeps the spacing near one texel and the result band-free.
        var params = SIMD4<Float>(direction.x, direction.y, sigma, max(1, sigma / 5))
        encoder.setRenderPipelineState(blurPipeline)
        encoder.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    /// Gaussian-blurs the desktop by `screenSigma` on-screen pixels, working at whichever mip level
    /// keeps the radius at 6 texels or less. Returns the blurred texture for that level.
    private func encodeBlur(name: String, sigma screenSigma: Float, using commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let mip = mipTexture else { return nil }
        let wanted = Int(ceil(log2(max(screenSigma / 6, 1))))
        let level = min(max(wanted, 1), mip.mipmapLevelCount - 1)
        let width = max(1, mip.width >> level)
        let height = max(1, mip.height >> level)
        let key = "\(name)-\(level)"
        if blurTargets[key]?.width != width || blurTargets[key]?.height != height {
            blurTargets[key] = makeBlurTexture(width: width, height: height)
        }
        if blurScratch[level]?.width != width || blurScratch[level]?.height != height {
            blurScratch[level] = makeBlurTexture(width: width, height: height)
        }
        guard let destination = blurTargets[key], let scratch = blurScratch[level],
              let source = mip.makeTextureView(pixelFormat: .bgra8Unorm, textureType: .type2D, levels: level..<(level + 1), slices: 0..<1)
        else { return nil }
        let sigma = max(0.4, screenSigma / Float(1 << level))
        encodeBlurPass(from: source, to: scratch, direction: SIMD2(1, 0), sigma: sigma, using: commandBuffer)
        encodeBlurPass(from: scratch, to: destination, direction: SIMD2(0, 1), sigma: sigma, using: commandBuffer)
        return destination
    }

    /// Builds adjacent Gaussian scales instead of cross-fading sharp and broadly blurred images.
    /// Each pass has five taps and the working area quarters at every level. The pyramid does
    /// not depend on lid angle, so a 120 Hz animation can reuse a 60 Hz capture's existing levels.
    private func encodeDiffusion(using commandBuffer: MTLCommandBuffer) {
        guard !diffusionIsCurrent, let source = mipTexture else { return }
        if diffusionTexture?.width != source.width || diffusionTexture?.height != source.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: source.width, height: source.height, mipmapped: true)
            descriptor.mipmapLevelCount = min(source.mipmapLevelCount, 9)
            descriptor.usage = [.shaderRead, .renderTarget, .pixelFormatView]
            descriptor.storageMode = .private
            diffusionTexture = device.makeTexture(descriptor: descriptor)
            diffusionScratch.removeAll()
        }
        guard let pyramid = diffusionTexture, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
                  sourceSize: .init(width: source.width, height: source.height, depth: 1),
                  to: pyramid, destinationSlice: 0, destinationLevel: 0, destinationOrigin: .init(x: 0, y: 0, z: 0))
        blit.endEncoding()
        for level in 1..<pyramid.mipmapLevelCount {
            let width = max(1, source.width >> level)
            if diffusionScratch[level] == nil {
                diffusionScratch[level] = makeBlurTexture(width: width, height: max(1, source.height >> (level - 1)))
            }
            guard let scratch = diffusionScratch[level],
                  let previous = pyramid.makeTextureView(pixelFormat: .bgra8Unorm, textureType: .type2D,
                                                         levels: (level - 1)..<level, slices: 0..<1),
                  let destination = pyramid.makeTextureView(pixelFormat: .bgra8Unorm, textureType: .type2D,
                                                            levels: level..<(level + 1), slices: 0..<1) else { return }
            // Downsample one axis at a time, filtering before reduction in each direction.
            // Keeping the previous height in scratch gives both axes the same Gaussian footprint.
            for (input, output, direction) in [(previous, scratch, SIMD2<Float>(1, 0)),
                                                (scratch, destination, SIMD2<Float>(0, 1))] {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = output
                pass.colorAttachments[0].loadAction = .dontCare
                pass.colorAttachments[0].storeAction = .store
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
                var parameters = SIMD4<Float>(direction.x, direction.y, 0, 0)
                encoder.setRenderPipelineState(diffusionPipeline)
                encoder.setFragmentBytes(&parameters, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.setFragmentTexture(input, index: 0)
                encoder.setFragmentSamplerState(sampler, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
            }
        }
        diffusionIsCurrent = true
    }

    /// Runs the blur passes a frame needs. Nothing runs at the identity (lid at the clear angle).
    private func encodeBlurs(_ uniforms: BendUniforms, using commandBuffer: MTLCommandBuffer) {
        guard hasFrame else { return }
        let blur = uniforms.p2.x
        let ramp = uniforms.p2.w
        guard blur > 0.000001 || ramp > 0.000001 else { return }
        if uniforms.p3.y > 0.5 {
            encodeDiffusion(using: commandBuffer)
            return
        }
        // The heavy end grows with the travel; the soft end follows the style's blur.
        let heavySigma = max(28 + 44 * ramp, blur * 64)
        heavyBlur = encodeBlur(name: "heavy", sigma: heavySigma, using: commandBuffer)
        if blur > 0.001 {
            softBlur = encodeBlur(name: "soft", sigma: max(1.5, blur * 64 * 0.4), using: commandBuffer)
        }
    }

    /// Draws the bent desktop into whatever `passDescriptor` targets.
    private func encode(_ uniforms: BendUniforms, into passDescriptor: MTLRenderPassDescriptor, using commandBuffer: MTLCommandBuffer) {
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        defer { encoder.endEncoding() }
        guard let texture = mipTexture, hasFrame else { return }

        var uniforms = uniforms
        uniforms.p1.x = 1 / Float(texture.width)
        uniforms.p1.y = 1 / Float(texture.height)
        uniforms.p1.z = Float(texture.width) / Float(texture.height)
        uniforms.p1.w = Float(passDescriptor.colorAttachments[0].texture?.height ?? texture.height)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms.p0, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms.p1, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms.p2, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
        encoder.setFragmentBytes(&uniforms.p3, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(softBlur ?? texture, index: 1)
        encoder.setFragmentTexture(heavyBlur ?? texture, index: 2)
        encoder.setFragmentTexture(diffusionIsCurrent ? (diffusionTexture ?? texture) : texture, index: 3)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// Synchronous offscreen render of `source` with `uniforms`. Used by scripts/render-test.swift.
    func renderOffscreen(source: MTLTexture, uniforms: BendUniforms, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        upload(source, using: commandBuffer)
        encodeBlurs(uniforms, using: commandBuffer)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].storeAction = .store
        encode(uniforms, into: pass, using: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            NSLog("OpenBend: offscreen render failed: %@", commandBuffer.error?.localizedDescription ?? "Unknown Metal error")
            return nil
        }
        return target
    }
}
