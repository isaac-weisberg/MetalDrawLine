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

final class LineDrawer {
    private let mtkViewDelegate = LineDrawerMTKViewDelegate()
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let renderPipelineState: MTLRenderPipelineState
    let library: MTLLibrary
    
    let controlPoints: [simd_float2]
    let controlPointsBuffer: MTLBuffer
    var env: Env
    let envBuffer: MTLBuffer
    
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

        let stateDescriptor = MTLRenderPipelineDescriptor()
        stateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        stateDescriptor.vertexDescriptor = nil
        stateDescriptor.vertexFunction = library.makeFunction(name: "calculateVertex")!
        stateDescriptor.fragmentFunction = library.makeFunction(name: "calculateFragment")!
        renderPipelineState = try! device.makeRenderPipelineState(descriptor: stateDescriptor)
    }
    
    func attach(_ view: MTKView) {
        mtkViewDelegate.lineDrawer = self
        view.delegate = mtkViewDelegate
        view.device = device
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    var lastKnownSize: CGSize?
    func draw(in view: MTKView) {
        if lastKnownSize != view.bounds.size {
            lastKnownSize = view.bounds.size
            
            env.canvasSize = simd_float2(
                x: Float(view.bounds.size.width),
                y: Float(view.bounds.height)
            )
            
            memcpy(envBuffer.contents(), &env, MemoryLayout<Env>.stride)
        }

        guard let onscreenDescriptor = view.currentRenderPassDescriptor else {
            assertionFailure()
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        if let onscreenCommandEncoder = commandBuffer
            .makeRenderCommandEncoder(descriptor: onscreenDescriptor) {
            
            onscreenCommandEncoder.setRenderPipelineState(renderPipelineState)
            onscreenCommandEncoder.setVertexBuffer(envBuffer, offset: 0, index: 0)
            onscreenCommandEncoder.setVertexBuffer(controlPointsBuffer, offset: 0, index: 1)

            onscreenCommandEncoder.drawPrimitives(
                type: .lineStrip,
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
