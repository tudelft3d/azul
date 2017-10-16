//
//  GPU.swift
//  azul
//
//  Created by Adam Nemecek on 10/16/17.
//  Copyright © 2017 Ken Arroyo Ohori. All rights reserved.
//

import MetalKit

extension Dictionary {

}
class GPU {
    let device : MTLDevice
    let queue : MTLCommandQueue
    let library : MTLLibrary

    private var functions:[String: MTLFunction] = [:]

    static let shared = GPU()

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        library = device.makeDefaultLibrary()!
    }

    func makeFunction(name: String) -> MTLFunction {
        return functions[name, default: library.makeFunction(name: name)!]
    }
}
