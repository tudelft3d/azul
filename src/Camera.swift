//
//  Camera.swift
//  azul
//
//  Created by Adam Nemecek on 10/17/17.
//  Copyright © 2017 Ken Arroyo Ohori. All rights reserved.
//

import MetalKit


class Camera {
    let eye : float3
    let center : float3
    let fov : Float

    private(set) var shiftBack : float4x4
    private(set) var rotation : float4x4
    let uniforms : Constants

    init(eye : float3, center : float3) {
        self.eye = eye
        self.center = center
        self.shiftBack = .init(translation: center)
        fatalError()
    }

    func rotate(by angle : Float) {

    }


}
