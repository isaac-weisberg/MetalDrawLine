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
    var vertexCount: UInt32
    var controlPointsCount: UInt32
    var strokeHalfWidth: simd_float1
}

struct VertexOut {
    let pos: simd_float2
    let t: Float
}

final class LineDrawer {
    private let mtkViewDelegate = LineDrawerMTKViewDelegate()
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderPipelineState: MTLRenderPipelineState
    let geometryPipelineState: MTLComputePipelineState
    let library: MTLLibrary
    
    var controlPoints: [simd_float2]
    let controlPointsBuffer: MTLBuffer
    var env: Env
    let envBuffer: MTLBuffer
    let bakedVertexBuffer: MTLBuffer
    
    var bakedVertexBufferDirty = false
    
    init() {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()!
        library = try! device.makeDefaultLibrary(bundle: Bundle.main)
        controlPoints = [
            simd_float2(100, 200),
            simd_float2(100, 100),
            simd_float2(200, 100),
            simd_float2(200, 200),
        ]
        
        controlPointsBuffer = device.makeBuffer(
            bytes: controlPoints,
            length: MemoryLayout<simd_float2>.stride * controlPoints.count
        )!
        
        env = Env(
            canvasSize: simd_float2(x: 0, y: 0),
            vertexCount: 200,
            controlPointsCount: UInt32(controlPoints.count),
            strokeHalfWidth: 4,
        )
        envBuffer = device.makeBuffer(
            bytes: &env,
            length: MemoryLayout<Env>.stride,
            options: .storageModeShared,
        )!

        let rendererStateDescriptor = MTLRenderPipelineDescriptor()
        rendererStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        rendererStateDescriptor.vertexDescriptor = nil
        rendererStateDescriptor.vertexFunction = library.makeFunction(name: "vertexPassthrough")!
        rendererStateDescriptor.fragmentFunction = library.makeFunction(name: "calculateFragment")!
        renderPipelineState = try! device
            .makeRenderPipelineState(descriptor: rendererStateDescriptor)

        self.geometryPipelineState = try! device
            .makeComputePipelineState(function: library.makeFunction(name: "calculateVertex")!)
        
        bakedVertexBuffer = device.makeBuffer(
            length: MemoryLayout<VertexOut>.stride * Int(env.vertexCount),
            options: .storageModeShared,
        )!
    }
    
    func attach(_ view: MTKView) {
        mtkViewDelegate.lineDrawer = self
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        view.delegate = mtkViewDelegate
        view.device = device
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    var lastKnownSize: CGSize?
    func draw(in view: MTKView) {
        if lastKnownSize != view.bounds.size {
            lastKnownSize = view.bounds.size
            
            controlPoints = [
                simd_float2(0.1, 0.1),
                simd_float2(0.12, 0.8),
                simd_float2(0.52, 0.6),
                simd_float2(0.64, 0.3),
                simd_float2(0.9, 0.55),
            ].map { vec in
                simd_float2(
                    vec.x * Float(view.bounds.size.width),
                    vec.y * Float(view.bounds.size.height),
                )
            }
            bakedVertexBufferDirty = true
            
            env.canvasSize = simd_float2(
                x: Float(view.bounds.size.width),
                y: Float(view.bounds.height)
            )
            env.controlPointsCount = UInt32(controlPoints.count)
            
            memcpy(envBuffer.contents(), &env, MemoryLayout<Env>.stride)
            memcpy(
                controlPointsBuffer.contents(),
                controlPoints,
                MemoryLayout<simd_float2>.stride * controlPoints.count,
            )
        }

        guard let onscreenDescriptor = view.currentRenderPassDescriptor else {
            assertionFailure()
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        if bakedVertexBufferDirty {
            bakedVertexBufferDirty = false
            
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.setComputePipelineState(geometryPipelineState)
                
                computeEncoder.setBuffer(envBuffer, offset: 0, index: 0)
                computeEncoder.setBuffer(controlPointsBuffer, offset: 0, index: 1)
                computeEncoder.setBuffer(bakedVertexBuffer, offset: 0, index: 2)
                
                let w = geometryPipelineState.threadExecutionWidth
                
                let threadgroupsPerGrid = MTLSize(width: (Int(env.vertexCount) + w - 1) / w,
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
            onscreenCommandEncoder.setVertexBuffer(bakedVertexBuffer, offset: 0, index: 0)
            
            onscreenCommandEncoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: Int(env.vertexCount)
            )
            
            onscreenCommandEncoder.endEncoding()
            
            if let currentDrawable = view.currentDrawable {
                commandBuffer.present(currentDrawable)
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
