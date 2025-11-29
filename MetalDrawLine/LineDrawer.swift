import MetalKit
import UIKit
import simd

private final class LineDrawerMTKViewDelegate: NSObject, MTKViewDelegate {
    unowned var lineDrawer: LineDrawer!

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lineDrawer.mtkView(view, drawableSizeWillChange: size)
    }
    
    func draw(in view: MTKView) {
        lineDrawer.draw(in: view)
    }
}

struct Env {
    var canvasSize: simd_float2
    var strokeHalfWidth: simd_float1
    var totalVertexCount: UInt32
}

struct VertexOut {
    var pos: simd_float4 = .zero
    var t: Float = 0
    
    #if DEBUG
    var vertexType: UInt8 = 0
    var unscaledTailDirectionVector: simd_float2 = .zero
    var tailDirectionVector: simd_float2 = .zero
    var normalVector: simd_float2 = .zero
    var angleToRotateBy: Float = 0
    var subdivisionIndex: Int32 = 0
    var subdivisionArc: Float = 0
    var subdivisionArcDividend: Float = 0;
    var subdivisionArcDivisor: Float = 0;
    var rotatedVector: simd_float2 = .zero
    var pointAttachedToTheEnd: simd_float2 = .zero
    #endif
}

struct BezierGeometry {
    var vertexCount: UInt32
    var controlPointsCount: UInt32
    var roundedEndResolution: UInt32
}

struct Shading {
    let colorsCount: UInt32
    var colors: [simd_half4]
    var stops: [Float]
    
    init(colors: [simd_half4], stops: [Float]) {
        assert(colors.count == stops.count)
        colorsCount = UInt32(min(colors.count, stops.count))
        self.colors = colors
        self.stops = stops
    }
}

struct ColorsCount {
    var value: UInt32
}

final class LineDrawer {
    private let mtkViewDelegate = LineDrawerMTKViewDelegate()
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderPipelineState: MTLRenderPipelineState
    let geometryPipelineState: MTLComputePipelineState
    let library: MTLLibrary
    
    var controlPoints: MetalArrayVariable<simd_float2>
    var env: MetalVariable<Env>
    var bakedVertices: MetalArrayVariable<VertexOut>
    var bakedVertexBufferDirty = false
    
    var shading: Shading
    var colorsBuffer: MTLBuffer
    var animatedColorsStops: MetalArrayVariable<Float>
    var colorStopsAnimation: VariableAnimation<[Float]>
    var bezierGeometry: MetalVariable<BezierGeometry>
    
    init() {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()!
        library = try! device.makeDefaultLibrary(bundle: Bundle.main)
        controlPoints = MetalArrayVariable(
            value: [
//                simd_float2.zero,
//                simd_float2.zero,
//                simd_float2.zero,
//                simd_float2.zero,
//                simd_float2.zero,
                
                simd_float2.zero,
                simd_float2.zero,
            ],
            device: device
        )!
        
        bezierGeometry = MetalVariable(
            value: BezierGeometry(
                vertexCount: 200,
                controlPointsCount: UInt32(controlPoints.value.count),
                roundedEndResolution: 5,
            ),
            device: device
        )!
        let totalVertexCount: UInt32 = bezierGeometry.value.roundedEndResolution
            + bezierGeometry.value.vertexCount
            + bezierGeometry.value.roundedEndResolution;
        
        env = MetalVariable(
            value: Env(
                canvasSize: simd_float2(x: 0, y: 0),
                strokeHalfWidth: 16,
                totalVertexCount: totalVertexCount
            ),
            device: device
        )!

        let rendererStateDescriptor = MTLRenderPipelineDescriptor()
        
        let attachment = rendererStateDescriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.sourceAlphaBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        rendererStateDescriptor.vertexDescriptor = nil
        rendererStateDescriptor.vertexFunction = library.makeFunction(name: "vertexPassthrough")!
        rendererStateDescriptor.fragmentFunction = library.makeFunction(name: "calculateFragment")!
        renderPipelineState = try! device
            .makeRenderPipelineState(descriptor: rendererStateDescriptor)

        self.geometryPipelineState = try! device
            .makeComputePipelineState(function: library.makeFunction(name: "calculateVertex")!)

        bakedVertices = MetalArrayVariable(
            value: Array(
                repeating: VertexOut(),
                count: Int(totalVertexCount),
            ),
            device: device
        )!
        
        let shading = Shading(
            colors: [
                simd_half4(rgba: 0x28E07400), // offscreen, transparent
                
                simd_half4(rgba: 0x28E074FF), // repeat to fill range
                simd_half4(rgba: 0x28E074FF),
                simd_half4(rgba: 0xFECC2CFF),
                simd_half4(rgba: 0xFA601CFF),
                simd_half4(rgba: 0xF7393DFF),
                simd_half4(rgba: 0xF43BD5FF),
                simd_half4(rgba: 0x385DE3FF),
                simd_half4(rgba: 0x385DE3FF), // repeat to fill range
                
                simd_half4(rgba: 0x385DE300), // offscreen, transparent
            ],
            stops: [
                -0.1, // offscreen
                 
                 0.00, // repeat to fill range
                 0.08,
                 0.28,
                 0.43,
                 0.60,
                 0.75,
                 0.97,
                 0.1, // repeat to fill range
                 
                 1.1, // offscreen
            ]
        )
        self.shading = shading
        
        colorsBuffer = device.makeBuffer(
            bytes: shading.colors,
            length: MemoryLayout<simd_half4>.stride * shading.colors.count,
        )!
        animatedColorsStops = MetalArrayVariable(
            value: shading.stops,
            device: device
        )!
        
        let totalStopsRange = shading.stops.last! - shading.stops.first!
        colorStopsAnimation = VariableAnimation(
            startTime: CACurrentMediaTime(),
            duration: 3,
            from: shading.stops.map { val in
                val - totalStopsRange
            },
            to: shading.stops.map { val in
                val + totalStopsRange
            },
            curve: .easeInEaseOut
        )
    }
    
    func attach(_ view: MTKView) {
        mtkViewDelegate.lineDrawer = self
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        view.delegate = mtkViewDelegate
        view.device = device
        
        view.isPaused = false
        view.enableSetNeedsDisplay = false // THere's an anim running
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    var lastKnownSize: CGSize?
    func draw(in view: MTKView) {
        if lastKnownSize != view.bounds.size {
            lastKnownSize = view.bounds.size
            
            controlPoints.value = [
//                simd_float2(0.1, 0.1),
//                simd_float2(0.12, 0.8),
//                simd_float2(0.52, 0.6),
//                simd_float2(0.64, 0.3),
//                simd_float2(0.9, 0.55),
                
                simd_float2(0.5, 0.25),
                simd_float2(0.5, 0.75),
            ].map { vec in
                simd_float2(
                    vec.x * Float(view.bounds.size.width),
                    vec.y * Float(view.bounds.size.height),
                )
            }
            bakedVertexBufferDirty = true
            
            env.value.canvasSize = simd_float2(
                x: Float(view.bounds.size.width),
                y: Float(view.bounds.size.height)
            )
            bezierGeometry.value.controlPointsCount = UInt32(controlPoints.value.count)
        }
        
        let time = CACurrentMediaTime()
    
        if !view.enableSetNeedsDisplay, time > colorStopsAnimation.endTime {
//            view.enableSetNeedsDisplay = true
//            view.isPaused = true
        }
        
        let value = colorStopsAnimation.value(at: time)
//        animatedColorsStops.value = value
        

        guard let onscreenDescriptor = view.currentRenderPassDescriptor else {
            assertionFailure()
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        var bakedVertexBufferUpdated = false
        if bakedVertexBufferDirty {
            bakedVertexBufferDirty = false
            bakedVertexBufferUpdated = true
            
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.setComputePipelineState(geometryPipelineState)

                env.flushIfNeeded()
                computeEncoder.setBuffer(env.buffer, offset: 0, index: 0)
                bezierGeometry.flushIfNeeded()
                computeEncoder.setBuffer(bezierGeometry.buffer, offset: 0, index: 1)
                controlPoints.flushIfNeeded()
                computeEncoder.setBuffer(controlPoints.buffer, offset: 0, index: 2)
                computeEncoder.setBuffer(bakedVertices.buffer, offset: 0, index: 3)
                
                let w = geometryPipelineState.threadExecutionWidth
                
                let threadgroupsPerGrid = MTLSize(width: (Int(env.value.totalVertexCount) + w - 1) / w,
                                                  height: 1,
                                                  depth: 1)
                let threadsPerThreadgroup = MTLSizeMake(w, 1, 1)
                
                computeEncoder.dispatchThreadgroups(
                    threadgroupsPerGrid,
                    threadsPerThreadgroup: threadsPerThreadgroup
                )
                
                computeEncoder.endEncoding()
            }
        }
        
        if let onscreenCommandEncoder = commandBuffer
            .makeRenderCommandEncoder(descriptor: onscreenDescriptor) {
            
            onscreenCommandEncoder.setRenderPipelineState(renderPipelineState)
            onscreenCommandEncoder.setVertexBuffer(bakedVertices.buffer, offset: 0, index: 0)
            
            onscreenCommandEncoder.setFragmentBuffer(colorsBuffer, offset: 0, index: 0)
            animatedColorsStops.flushIfNeeded()
            onscreenCommandEncoder.setFragmentBuffer(animatedColorsStops.buffer, offset: 0, index: 1)
            var colorsCount = ColorsCount(value: shading.colorsCount)
            onscreenCommandEncoder.setFragmentBytes(
                &colorsCount,
                length: MemoryLayout<ColorsCount>.stride,
                index: 2
            )
            
            onscreenCommandEncoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: Int(env.value.totalVertexCount)
            )
            
            onscreenCommandEncoder.endEncoding()
            
            if let currentDrawable = view.currentDrawable {
                commandBuffer.present(currentDrawable)
            }
        }
        
        if bakedVertexBufferUpdated {
            commandBuffer.addCompletedHandler { [weak self] _ in
                self?.bakedVertices.reverseFlush()
            }
        }
        
        commandBuffer.commit()
    }
}


extension Optional {
    func assertNonNil() -> Optional {
        Swift.assert(self != nil)
        return self
    }
}

extension simd_half4 {
    init(rgba: UInt32) {
        let red = Float16((rgba >> 24) & 0xFF) / 255.0
        let green = Float16((rgba >> 16) & 0xFF) / 255.0
        let blue = Float16((rgba >> 8) & 0xFF) / 255.0
        let alpha = Float16(rgba & 0xFF) / 255.0

        self.init(red, green, blue, alpha)
    }
}
