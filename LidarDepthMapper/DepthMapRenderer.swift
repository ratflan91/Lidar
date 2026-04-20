import Metal
import MetalKit
import ARKit
import simd

enum VisualizationMode: Int, CaseIterable {
    case gradient   = 0
    case contour    = 1
    case combined   = 2
    case cameraOnly = 3
}

final class DepthMapRenderer: NSObject, MTKViewDelegate {

    // MARK: - Public state

    private(set) var mode: VisualizationMode = .gradient

    // MARK: - Private

    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var uniformBuffer: MTLBuffer!
    private var textureCache: CVMetalTextureCache!

    private var cameraYTexture:    MTLTexture?
    private var cameraCbCrTexture: MTLTexture?
    private var depthTexture:      MTLTexture?

    private var viewportSize: CGSize = .zero

    // Must match the struct layout in Shaders.metal exactly.
    // 4 scalars (16 bytes) + float4x4 (64 bytes) = 80 bytes, naturally aligned.
    private struct Uniforms {
        var mode:             Int32
        var maxDepth:         Float
        var alpha:            Float
        var contourInterval:  Float
        var displayTransform: simd_float4x4
    }

    // MARK: - Init

    init(device metalDevice: MTLDevice, mtkView: MTKView) {
        self.commandQueue = metalDevice.makeCommandQueue()!
        super.init()

        CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &textureCache)
        buildPipeline(device: metalDevice, colorFormat: mtkView.colorPixelFormat)

        var u = Uniforms(
            mode: 0, maxDepth: 5.0, alpha: 0.70, contourInterval: 0.30,
            displayTransform: matrix_identity_float4x4
        )
        uniformBuffer = metalDevice.makeBuffer(
            bytes: &u,
            length: MemoryLayout<Uniforms>.size,
            options: .storageModeShared
        )
    }

    private func buildPipeline(device: MTLDevice, colorFormat: MTLPixelFormat) {
        guard let lib = device.makeDefaultLibrary() else {
            fatalError("No default Metal library — make sure Shaders.metal is in the target.")
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = lib.makeFunction(name: "vertexPassthrough")!
        desc.fragmentFunction = lib.makeFunction(name: "fragmentDepthMap")!
        desc.colorAttachments[0].pixelFormat = colorFormat
        pipelineState = try! device.makeRenderPipelineState(descriptor: desc)
    }

    // MARK: - Frame update

    func update(frame: ARFrame) {
        updateCameraTextures(from: frame.capturedImage)

        let depthBuffer = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
        if let depthBuffer { updateDepthTexture(from: depthBuffer) }

        if viewportSize.width > 0 {
            let t = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
            let m = simd_float4x4(
                SIMD4<Float>(Float(t.a),  Float(t.b),  0, 0),
                SIMD4<Float>(Float(t.c),  Float(t.d),  0, 0),
                SIMD4<Float>(0,           0,            1, 0),
                SIMD4<Float>(Float(t.tx), Float(t.ty), 0, 1)
            )
            let ptr = uniformBuffer.contents().assumingMemoryBound(to: Uniforms.self)
            ptr.pointee.displayTransform = m
        }
    }

    func cycleMode() {
        mode = VisualizationMode(rawValue: (mode.rawValue + 1) % VisualizationMode.allCases.count)!
        uniformBuffer.contents()
            .assumingMemoryBound(to: Uniforms.self)
            .pointee.mode = Int32(mode.rawValue)
    }

    // MARK: - Texture helpers

    private func updateCameraTextures(from pixelBuffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }

        let yW    = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let yH    = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let cbW   = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let cbH   = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)

        var yRef:    CVMetalTexture?
        var cbcrRef: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil, .r8Unorm,   yW,  yH,  0, &yRef)
        CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil, .rg8Unorm,  cbW, cbH, 1, &cbcrRef)

        if let r = yRef    { cameraYTexture    = CVMetalTextureGetTexture(r) }
        if let r = cbcrRef { cameraCbCrTexture = CVMetalTextureGetTexture(r) }
    }

    private func updateDepthTexture(from pixelBuffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        var ref: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil, .r32Float, w, h, 0, &ref)
        if let r = ref { depthTexture = CVMetalTextureGetTexture(r) }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }

    func draw(in view: MTKView) {
        guard
            let drawable        = view.currentDrawable,
            let renderPassDesc  = view.currentRenderPassDescriptor,
            let cmdBuf          = commandQueue.makeCommandBuffer(),
            let encoder         = cmdBuf.makeRenderCommandEncoder(descriptor: renderPassDesc)
        else { return }

        renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        // Full-screen quad: each vertex = (clipX, clipY, uvX, uvY)
        let verts: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0,
        ]

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(verts,
                               length: MemoryLayout<Float>.size * verts.count,
                               index: 0)
        encoder.setFragmentTexture(cameraYTexture,    index: 0)
        encoder.setFragmentTexture(cameraCbCrTexture, index: 1)
        encoder.setFragmentTexture(depthTexture,      index: 2)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }
}
