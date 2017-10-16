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


class Renderer : NSObject, MTKViewDelegate {
//    let state : MTLRenderPipelineState

    override init() {
        GPU.shared

    }
    func draw(in view: MTKView) {

    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }
}

