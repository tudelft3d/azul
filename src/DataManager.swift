//
//  DataManager.swift
//  azul
//
//  Created by Adam Nemecek on 10/16/17.
//  Copyright © 2017 Ken Arroyo Ohori. All rights reserved.
//

import Foundation

extension DataManagerWrapperWrapper {
    func depthAtCentre(viewMatrix : float4x4, modelMatrix: float4x4) -> Float {

        let firstMinCoordinate = self.minCoordinates
        let minCoordinatesBuffer = UnsafeBufferPointer(start: firstMinCoordinate, count: 3)
        let minCoordinates = ContiguousArray(minCoordinatesBuffer)
        //let minCoordinates = [Float](minCoordinatesArray)

        let firstMidCoordinate = self.midCoordinates
        let midCoordinatesBuffer = UnsafeBufferPointer(start: firstMidCoordinate, count: 3)
        let midCoordinates = ContiguousArray(midCoordinatesBuffer)
        //let midCoordinates = [Float](midCoordinatesArray)

        let firstMaxCoordinate = self.maxCoordinates
        let maxCoordinatesBuffer = UnsafeBufferPointer(start: firstMaxCoordinate, count: 3)
        let maxCoordinates = ContiguousArray(maxCoordinatesBuffer)
//        let maxCoordinates = [Float](maxCoordinatesArray)
        let maxRange = self.maxRange

        // Create three points along the data plane
        let y = (maxCoordinates[1]-midCoordinates[1])/maxRange
        let leftUpPointInObjectCoordinates = float4((minCoordinates[0]-midCoordinates[0])/maxRange, y, 0.0, 1.0)
        let rightUpPointInObjectCoordinates = float4((maxCoordinates[0]-midCoordinates[0])/maxRange, y, 0.0, 1.0)
        let centreDownPointInObjectCoordinates = float4(0.0, (minCoordinates[1]-midCoordinates[1])/maxRange, 0.0, 1.0)

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
}
