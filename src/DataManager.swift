//
//  DataManager.swift
//  azul
//
//  Created by Adam Nemecek on 10/16/17.
//  Copyright © 2017 Ken Arroyo Ohori. All rights reserved.
//

import Foundation

extension DataManager {
    func depthAtCentre(viewMatrix : float4x4, modelMatrix: float4x4) -> Float {

        let minCoordinates = self.minCoordinates
        let midCoordinates = self.midCoordinates
        let maxCoordinates = self.maxCoordinates
        let maxRange = self.maxRange

        // Create three points along the data plane
        let y = (maxCoordinates.y-midCoordinates.y)/maxRange
        let leftUpPointInObjectCoordinates = float4((minCoordinates.x-midCoordinates.x)/maxRange, y, 0.0, 1.0)
        let rightUpPointInObjectCoordinates = float4((maxCoordinates.x-midCoordinates.x)/maxRange, y, 0.0, 1.0)
        let centreDownPointInObjectCoordinates = float4(0.0, (minCoordinates.y-midCoordinates.y)/maxRange, 0.0, 1.0)

        // Obtain their coordinates in eye space
        let modelViewMatrix = viewMatrix * modelMatrix
        let leftUpPoint = (modelViewMatrix * leftUpPointInObjectCoordinates)
        let rightUpPoint = (modelViewMatrix * rightUpPointInObjectCoordinates)
        let centreDownPoint = (modelViewMatrix * centreDownPointInObjectCoordinates)

        // Compute the plane passing through the points.
        // In ax + by + cz + d = 0, abc are given by the cross product, d by evaluating a point in the equation.

        let vector1 = leftUpPoint.xyz - centreDownPoint.xyz
        let vector2 = rightUpPoint.xyz - centreDownPoint.xyz
        let crossProduct = cross(vector1, vector2)
        let point3 = centreDownPoint.xyz/centreDownPoint.w
        let d = -dot(crossProduct, point3)

        // Assuming x = 0 and y = 0, z (i.e. depth at the centre) = -d/c
        //    Swift.print("Depth at centre: \(-d/crossProduct.z)")
        return -d/crossProduct.z
    }

//    func numberOfRows1(in tableView: NSTableView) -> Int {
//        guard let s = controller.objectsSourceList?.selectedRow else { return 0 }
//    }
//
//    func tableView1(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
//        fatalError()
//    }

    func boundingBoxBuffer() -> [Vertex] {

        // Get bounds
        let minCoordinates = self.minCoordinates
        let midCoordinates = self.midCoordinates
        let maxCoordinates = self.maxCoordinates
        let maxRange = self.maxRange

        // Create bounding box vertices
        let v: [float3] = [
            float3(minCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),  // 000 -> 001
            float3(minCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),
            float3(minCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),  // 000 -> 010
            float3(minCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),
            float3(minCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),  // 000 -> 100
            float3(maxCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),
            float3(minCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),  // 001 -> 011
            float3(minCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),
            float3(minCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),  // 001 -> 101
            float3(maxCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),
            float3(minCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),  // 010 -> 011
            float3(minCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),
            float3(minCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),  // 010 -> 110
            float3(maxCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),
            float3(minCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),  // 011 -> 111
            float3(maxCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),
            float3(maxCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),  // 100 -> 101
            float3(maxCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),
            float3(maxCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),  // 100 -> 110
            float3(maxCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),
            float3(maxCoordinates.x-midCoordinates.x,
                   minCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),  // 101 -> 111
            float3(maxCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z),
            float3(maxCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   minCoordinates.z-midCoordinates.z),  // 110 -> 111
            float3(maxCoordinates.x-midCoordinates.x,
                   maxCoordinates.y-midCoordinates.y,
                   maxCoordinates.z-midCoordinates.z)]
        return v.map { Vertex(position: $0/maxRange) }
    }
}
