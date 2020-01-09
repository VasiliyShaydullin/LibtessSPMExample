//
//  Renderer.swift
//  LibtessSPMExample
//
//  Created by Vasiliy Shaydullin on 17.12.2019.
//  Copyright © 2019 Vasiliy Shaydullin. All rights reserved.
//

import MetalKit

class Renderer: NSObject {
    
    static var device: MTLDevice!
    static var commandQueue: MTLCommandQueue!
    var mesh: MTKMesh?
    var vertexBuffer: MTLBuffer!
    var pipelineState: MTLRenderPipelineState!
    var baseColorTexture: MTLTexture!
    var depthStencilState:  MTLDepthStencilState!
    var projectionMatrix: matrix_float4x4 = matrix_perspective_right_hand(65.0 * (Float.pi / 180.0), Float(1), 0.1, 100.0)
    var rotation: Float = 0.0
    var vertexDescriptor: MDLVertexDescriptor!
    var timer: Float = 0
    
    init(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("GPU not available")
        }
        
        metalView.device = device
        Renderer.device = device
        Renderer.commandQueue = device.makeCommandQueue()!
        metalView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<simd_float3>.stride, bufferIndex: 0)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: MemoryLayout<simd_float3>.stride * 2 , bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<MeshVertex>.stride)
        
        self.vertexDescriptor = vertexDescriptor
        
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertex_main")
        let fragmentFunction = library?.makeFunction(name: "fragment_main")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.sampleCount = metalView.sampleCount;
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
        pipelineDescriptor.sampleCount = metalView.sampleCount;
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat;
        pipelineDescriptor.stencilAttachmentPixelFormat = metalView.depthStencilPixelFormat;
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            fatalError(error.localizedDescription)
        }
        
        let depthStateDesc: MTLDepthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStateDesc.depthCompareFunction = MTLCompareFunction.less
        depthStateDesc.isDepthWriteEnabled = true
        
        depthStencilState = device.makeDepthStencilState(descriptor: depthStateDesc)
        
        let textureLoader: MTKTextureLoader = MTKTextureLoader(device: device)
        
        do {
            let baseColorTexture = try textureLoader.newTexture(name: "wood", scaleFactor: 1.0, bundle: nil, options: nil)
            self.baseColorTexture = baseColorTexture
        } catch let error {
            print("Error creating texture", error.localizedDescription)
        }
        
        
        super.init()
        metalView.clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1)
        metalView.delegate = self
        
        mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
        
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = size.width / size.height
        projectionMatrix = matrix_perspective_right_hand(65.0 * (Float.pi / 180.0), Float(aspect), 0.1, 100.0)
    }
    
    func draw(in view: MTKView) {
        guard let mesh = mesh else { return }
        
        guard let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = Renderer.commandQueue.makeCommandBuffer(),
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        
        let timestep: Float = (view.preferredFramesPerSecond > 0) ? 1.0 / Float(view.preferredFramesPerSecond) : 1.0 / 60
        
        var uniforms = Uniforms()
        uniforms.projectionMatrix = self.projectionMatrix
        let axis = simd_float3(1, 1, 0)
        let modelMatrix = simd_mul(matrix4x4_rotation(radians: self.rotation, axis: axis), matrix4x4_scale(s: 0.02))
        let viewMatrix = matrix4x4_translation(tx: 0.0, ty: 0.0, tz: -8.0)
        uniforms.modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix)
        self.rotation += timestep
        
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(MTLCullMode.back)
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: Int(BufferIndexUniforms.rawValue))
        
        for (index, vertexBuffer) in mesh.vertexBuffers.enumerated() {
            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: index)
        }
        
        renderEncoder.setFragmentTexture(self.baseColorTexture, index: 0)
        
        for submesh in mesh.submeshes {
            
            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
        }
        
        renderEncoder.endEncoding()
        guard let drawable = view.currentDrawable else {
            return
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

func matrix_perspective_right_hand(_ fovyRadians: Float, _ aspect: Float, _ nearZ: Float, _ farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovyRadians * 0.5);
    let xs = ys / aspect;
    let zs = farZ / (nearZ - farZ);
    
    return matrix_float4x4(simd_float4(x: xs, y: 0, z: 0, w: 0),
                           simd_float4(x: 0, y: ys, z: 0, w: 0),
                           simd_float4(x: 0, y: 0, z: zs, w: -1),
                           simd_float4(x: 0, y: 0, z: nearZ * zs, w: 0))
    
}

func matrix4x4_rotation(radians: Float, axis: simd_float3) -> matrix_float4x4 {
    
    let axis = simd_normalize(axis)
    let ct = cosf(radians);
    let st = sinf(radians);
    let ci = 1 - ct;
    let x = axis.x, y = axis.y, z = axis.z;
    
    return matrix_float4x4(simd_float4(x: ct + x * x * ci,     y:  y * x * ci + z * st, z: z * x * ci - y * st, w: 0),
                           simd_float4(x: x * y * ci - z * st, y: ct + y * y * ci,      z: z * y * ci + x * st, w: 0),
                           simd_float4(x: x * z * ci + y * st, y: y * z * ci - x * st,  z: ct + z * z * ci,     w: 0),
                           simd_float4(x: 0,                   y: 0,                    z: 0,                   w: 1))
}

func matrix4x4_scale(s: Float) -> matrix_float4x4 {
    
    return matrix_float4x4(simd_float4(x: s, y: 0, z: 0, w: 0),
                           simd_float4(x: 0, y: s, z: 0, w: 0),
                           simd_float4(x: 0, y: 0, z: s, w: 0),
                           simd_float4(x: 0, y: 0, z: 0, w: 1))
}

func matrix4x4_translation(tx: Float, ty: Float, tz: Float) -> matrix_float4x4 {
    
    return matrix_float4x4(simd_float4(x: 1, y: 0, z: 0, w: 0),
                           simd_float4(x: 0, y: 1, z: 0, w: 0),
                           simd_float4(x: 0, y: 0, z: 1, w: 0),
                           simd_float4(x: tx, y: ty, z: tz, w: 1))
}
