//
//  Renderer.swift
//  azul
//
//  Created by Adam Nemecek on 10/16/17.
//  Copyright © 2017 Ken Arroyo Ohori. All rights reserved.
//

import MetalKit

class GPU {
    let device : MTLDevice
    let queue : MTLCommandQueue
    let library : MTLLibrary

    static let shared = GPU()

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        library = device.makeDefaultLibrary()!
    }
}

final class Renderer : NSObject, MTKViewDelegate {
    func draw(in view: MTKView) {

    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }
}
