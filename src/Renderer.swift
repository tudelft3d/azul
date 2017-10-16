//
//  Renderer.swift
//  azul
//
//  Created by Adam Nemecek on 10/16/17.
//  Copyright © 2017 Ken Arroyo Ohori. All rights reserved.
//

import MetalKit





//protocol Renderable {
////    associatedtype Descriptor : MTLRenderPipelineDescriptor
//
//}
//
//class Renderer<R : Renderable> : NSObject, MTKViewDelegate {
//
//    override init() {
//
//    }
//    func draw(in view: MTKView) {
//
//    }
//
//    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
//
//    }
//}

//class AzulRenderer : Renderer {
//
//}

class AzulRenderPipelineDescriptor : MTLRenderPipelineDescriptor {
    init(vert: String, frag : String) {
        super.init()
        vertexFunction = GPU.shared.makeFunction(name: vert)
        fragmentFunction = GPU.shared.makeFunction(name: frag)
        colorAttachments[0].pixelFormat = .bgra8Unorm
        colorAttachments[0].isBlendingEnabled = true
        colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        depthAttachmentPixelFormat = .depth32Float

    }
}


class Renderer : NSObject, MTKViewDelegate {
//    let state : MTLRenderPipelineState

    override init() {


    }
    func draw(in view: MTKView) {

    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }
}

