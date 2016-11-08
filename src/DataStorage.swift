// azul
// Copyright © 2016 Ken Arroyo Ohori
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import Metal
import MetalKit

class CityGMLObject {
  var id: String = ""
  var type: UInt32 = 0
  var triangleBuffersByType = [Int32: ContiguousArray<Float>]()
  var edgesBuffer = ContiguousArray<Float>()
}

class DataStorage: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
  
  var controller: Controller?
  var metalView: MetalView?
  
  var openFiles = Set<URL>()
  var objects = [CityGMLObject]()
  
  var selection = Set<String>()
  
  var minCoordinates = float3(0, 0, 0)
  var maxCoordinates = float3(0, 0, 0)
  var midCoordinates = float3(0, 0, 0)
  var maxRange: Float = 0.0
  
  func loadData(from urls: [URL]) {
    Swift.print("DataStorage.loadData(URL)")
    Swift.print("Opening \(urls)")
    
    let startTime = CACurrentMediaTime()
    controller!.progressIndicator.startAnimation(self)
    let cityGMLParser = CityGMLParserWrapperWrapper()!
    
    DispatchQueue.global().async(qos: .userInitiated) {
      for url in urls {
        
        if self.openFiles.contains(url) {
          Swift.print("\(url) already open")
          continue
        }
        
        //        Swift.print("Loading \(url)")
        url.path.utf8CString.withUnsafeBufferPointer { pointer in
          cityGMLParser.parse(pointer.baseAddress)
        }
        
        self.openFiles.insert(url)
        NSDocumentController.shared().noteNewRecentDocumentURL(url)
        
      }
      
      self.pullData(from: cityGMLParser)
      self.pushData()
      
      DispatchQueue.main.async {
        self.controller!.progressIndicator.stopAnimation(self)
        self.controller!.outlineView.reloadData()
        switch self.openFiles.count {
        case 0:
          self.controller!.window.representedURL = nil
          self.controller!.window.title = "Azul"
        case 1:
          self.controller!.window.representedURL = self.openFiles.first!
          self.controller!.window.title = self.openFiles.first!.lastPathComponent
        default:
          self.controller!.window.representedURL = nil
          self.controller!.window.title = "Azul (\(self.openFiles.count) open files)"
        }
        Swift.print("Read files in \(CACurrentMediaTime()-startTime) seconds.")
        self.metalView!.needsDisplay = true
        self.controller!.outlineView.reloadData()
      }
    }
  }
  
  func pullData(from cityGMLParser: CityGMLParserWrapperWrapper) {
    Swift.print("DataStorage.pullData(CityGMLParserWrapperWrapper)")
    
    let firstMinCoordinate = cityGMLParser.minCoordinates()
    let minCoordinatesBuffer = UnsafeBufferPointer(start: firstMinCoordinate, count: 3)
    var minCoordinatesArray = ContiguousArray(minCoordinatesBuffer)
    let firstMaxCoordinate = cityGMLParser.maxCoordinates()
    let maxCoordinatesBuffer = UnsafeBufferPointer(start: firstMaxCoordinate, count: 3)
    var maxCoordinatesArray = ContiguousArray(maxCoordinatesBuffer)
    if objects.count == 0 {
      minCoordinates = float3(minCoordinatesArray[0], minCoordinatesArray[1], minCoordinatesArray[2])
      maxCoordinates = float3(maxCoordinatesArray[0], maxCoordinatesArray[1], maxCoordinatesArray[2])
    } else {
      if minCoordinatesArray[0] < minCoordinates.x {
        minCoordinates.x = minCoordinatesArray[0]
      }
      if minCoordinatesArray[1] < minCoordinates.y {
        minCoordinates.y = minCoordinatesArray[1]
      }
      if minCoordinatesArray[2] < minCoordinates.z {
        minCoordinates.z = minCoordinatesArray[2]
      }
      if maxCoordinatesArray[0] > maxCoordinates.x {
        maxCoordinates.x = maxCoordinatesArray[0]
      }
      if maxCoordinatesArray[1] > maxCoordinates.y {
        maxCoordinates.y = maxCoordinatesArray[1]
      }
      if maxCoordinatesArray[2] > maxCoordinates.y {
        maxCoordinates.z = maxCoordinatesArray[2]
      }
    }
    
    cityGMLParser.initialiseObjectIterator()
    while !cityGMLParser.objectIteratorEnded() {
      
      objects.append(CityGMLObject())
      
      var idLength: UInt = 0
      let firstElementOfIdBuffer = UnsafeRawPointer(cityGMLParser.currentObjectIdentifier(withLength: &idLength))
      let idData = Data(bytes: firstElementOfIdBuffer!, count: Int(idLength)*MemoryLayout<Int8>.size)
      objects.last!.id = String(data: idData, encoding: String.Encoding.utf8)!
      objects.last!.type = cityGMLParser.currentObjectType()
      
      var numberOfEdgeVertices: UInt = 0
      let firstElementOfEdgesBuffer = cityGMLParser.currentObjectEdgesBuffer(withElements: &numberOfEdgeVertices)
      let edgesBuffer = UnsafeBufferPointer(start: firstElementOfEdgesBuffer, count: Int(numberOfEdgeVertices))
      objects.last!.edgesBuffer = ContiguousArray(edgesBuffer)
      
      cityGMLParser.initialiseTriangleBufferIterator()
      while !cityGMLParser.triangleBufferIteratorEnded() {
        var type: Int32 = 0
        var numberOfTriangleVertices: UInt = 0
        let firstElementOfTrianglesBuffer = cityGMLParser.currentTrianglesBuffer(withType: &type, andElements: &numberOfTriangleVertices)
        let trianglesBuffer = UnsafeBufferPointer(start: firstElementOfTrianglesBuffer, count: Int(numberOfTriangleVertices))
        objects.last!.triangleBuffersByType[type] = ContiguousArray(trianglesBuffer)
        cityGMLParser.advanceTriangleBufferIterator()
      }
      
      cityGMLParser.advanceObjectIterator()
    }
  }
  
  func pushData() {
    Swift.print("DataStorage.pushData(Renderer)")
    
    let range = maxCoordinates-minCoordinates
    midCoordinates = minCoordinates+0.5*range
    maxRange = range.x
    if range.y > maxRange {
      maxRange = range.y
    }
    if range.z > maxRange {
      maxRange = range.z
    }
    Swift.print("mid = \(midCoordinates)")
    
    var buildingVertices = [Vertex]()
    var buildingRoofVertices = [Vertex]()
    var roadVertices = [Vertex]()
    var waterVertices = [Vertex]()
    var plantCoverVertices = [Vertex]()
    var terrainVertices = [Vertex]()
    var genericVertices = [Vertex]()
    var bridgeVertices = [Vertex]()
    var landUseVertices = [Vertex]()
    var edgeVertices = [Vertex]()
    var selectionEdgeVertices = [Vertex]()
    var selectionFaceVertices = [Vertex]()
    
    let boundingBoxVertices: [Vertex] = [Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                                                                 (minCoordinates[1]-midCoordinates[1])/maxRange,
                                                                 (minCoordinates[2]-midCoordinates[2])/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 000 -> 001
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 000 -> 010
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 000 -> 100
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 001 -> 011
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 001 -> 101
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 010 -> 011
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 010 -> 110
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((minCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 011 -> 111
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 100 -> 101
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 100 -> 110
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (minCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 101 -> 111
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (minCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0)),  // 110 -> 111
      Vertex(position: float3((maxCoordinates[0]-midCoordinates[0])/maxRange,
                              (maxCoordinates[1]-midCoordinates[1])/maxRange,
                              (maxCoordinates[2]-midCoordinates[2])/maxRange),
             normal: float3(0.0, 0.0, 0.0))]
    
    for object in objects {
      
      if selection.contains(object.id) {
        let numberOfVertices = object.edgesBuffer.count/3
        for vertexIndex in 0..<numberOfVertices {
          selectionEdgeVertices.append(Vertex(position: float3((object.edgesBuffer[3*vertexIndex]-midCoordinates.x)/maxRange,
                                                               (object.edgesBuffer[3*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                               (object.edgesBuffer[3*vertexIndex+2]-midCoordinates.z)/maxRange),
                                              normal: float3(0.0, 0.0, 0.0)))
        }
        if object.triangleBuffersByType.keys.contains(0) {
          let numberOfVertices = object.triangleBuffersByType[0]!.count/6
          for vertexIndex in 0..<numberOfVertices {
            selectionFaceVertices.append(Vertex(position: float3((object.triangleBuffersByType[0]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                                 (object.triangleBuffersByType[0]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                                 (object.triangleBuffersByType[0]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                                normal: float3(object.triangleBuffersByType[0]![6*vertexIndex+3],
                                                               object.triangleBuffersByType[0]![6*vertexIndex+4],
                                                               object.triangleBuffersByType[0]![6*vertexIndex+5])))
          }
        }
        if object.triangleBuffersByType.keys.contains(1) {
          let numberOfVertices = object.triangleBuffersByType[1]!.count/6
          for vertexIndex in 0..<numberOfVertices {
            selectionFaceVertices.append(Vertex(position: float3((object.triangleBuffersByType[1]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                                 (object.triangleBuffersByType[1]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                                 (object.triangleBuffersByType[1]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                                normal: float3(object.triangleBuffersByType[1]![6*vertexIndex+3],
                                                               object.triangleBuffersByType[1]![6*vertexIndex+4],
                                                               object.triangleBuffersByType[1]![6*vertexIndex+5])))
          }
        }
      } else {
        
        let numberOfVertices = object.edgesBuffer.count/3
        for vertexIndex in 0..<numberOfVertices {
          edgeVertices.append(Vertex(position: float3((object.edgesBuffer[3*vertexIndex]-midCoordinates.x)/maxRange,
                                                      (object.edgesBuffer[3*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                      (object.edgesBuffer[3*vertexIndex+2]-midCoordinates.z)/maxRange),
                                     normal: float3(0.0, 0.0, 0.0)))
        }
        
        switch object.type {
        case 1:
          if object.triangleBuffersByType.keys.contains(0) {
            let numberOfVertices = object.triangleBuffersByType[0]!.count/6
            for vertexIndex in 0..<numberOfVertices {
              buildingVertices.append(Vertex(position: float3((object.triangleBuffersByType[0]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                              (object.triangleBuffersByType[0]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                              (object.triangleBuffersByType[0]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                             normal: float3(object.triangleBuffersByType[0]![6*vertexIndex+3],
                                                            object.triangleBuffersByType[0]![6*vertexIndex+4],
                                                            object.triangleBuffersByType[0]![6*vertexIndex+5])))
            }
          }
          if object.triangleBuffersByType.keys.contains(1) {
            let numberOfVertices = object.triangleBuffersByType[1]!.count/6
            for vertexIndex in 0..<numberOfVertices {
              buildingRoofVertices.append(Vertex(position: float3((object.triangleBuffersByType[1]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                                  (object.triangleBuffersByType[1]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                                  (object.triangleBuffersByType[1]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                                 normal: float3(object.triangleBuffersByType[1]![6*vertexIndex+3],
                                                                object.triangleBuffersByType[1]![6*vertexIndex+4],
                                                                object.triangleBuffersByType[1]![6*vertexIndex+5])))
            }
          }
        case 2:
          if object.triangleBuffersByType.keys.contains(0) {
            let numberOfVertices = object.triangleBuffersByType[0]!.count/6
            for vertexIndex in 0..<numberOfVertices {
              roadVertices.append(Vertex(position: float3((object.triangleBuffersByType[0]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                          (object.triangleBuffersByType[0]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                          (object.triangleBuffersByType[0]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                         normal: float3(object.triangleBuffersByType[0]![6*vertexIndex+3],
                                                        object.triangleBuffersByType[0]![6*vertexIndex+4],
                                                        object.triangleBuffersByType[0]![6*vertexIndex+5])))
            }
          }
        case 3:
          if object.triangleBuffersByType.keys.contains(0) {
            let numberOfVertices = object.triangleBuffersByType[0]!.count/6
            for vertexIndex in 0..<numberOfVertices {
              waterVertices.append(Vertex(position: float3((object.triangleBuffersByType[0]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                           (object.triangleBuffersByType[0]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                           (object.triangleBuffersByType[0]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                          normal: float3(object.triangleBuffersByType[0]![6*vertexIndex+3],
                                                         object.triangleBuffersByType[0]![6*vertexIndex+4],
                                                         object.triangleBuffersByType[0]![6*vertexIndex+5])))
            }
          }
        case 4:
          if object.triangleBuffersByType.keys.contains(0) {
            let numberOfVertices = object.triangleBuffersByType[0]!.count/6
            for vertexIndex in 0..<numberOfVertices {
              plantCoverVertices.append(Vertex(position: float3((object.triangleBuffersByType[0]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                                (object.triangleBuffersByType[0]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                                (object.triangleBuffersByType[0]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                               normal: float3(object.triangleBuffersByType[0]![6*vertexIndex+3],
                                                              object.triangleBuffersByType[0]![6*vertexIndex+4],
                                                              object.triangleBuffersByType[0]![6*vertexIndex+5])))
            }
          }
        case 5:
          if object.triangleBuffersByType.keys.contains(0) {
            let numberOfVertices = object.triangleBuffersByType[0]!.count/6
            for vertexIndex in 0..<numberOfVertices {
              terrainVertices.append(Vertex(position: float3((object.triangleBuffersByType[0]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                             (object.triangleBuffersByType[0]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                             (object.triangleBuffersByType[0]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                            normal: float3(object.triangleBuffersByType[0]![6*vertexIndex+3],
                                                           object.triangleBuffersByType[0]![6*vertexIndex+4],
                                                           object.triangleBuffersByType[0]![6*vertexIndex+5])))
            }
          }
        case 6:
          if object.triangleBuffersByType.keys.contains(0) {
            let numberOfVertices = object.triangleBuffersByType[0]!.count/6
            for vertexIndex in 0..<numberOfVertices {
              genericVertices.append(Vertex(position: float3((object.triangleBuffersByType[0]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                             (object.triangleBuffersByType[0]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                             (object.triangleBuffersByType[0]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                            normal: float3(object.triangleBuffersByType[0]![6*vertexIndex+3],
                                                           object.triangleBuffersByType[0]![6*vertexIndex+4],
                                                           object.triangleBuffersByType[0]![6*vertexIndex+5])))
            }
          }
        case 7:
          if object.triangleBuffersByType.keys.contains(0) {
            let numberOfVertices = object.triangleBuffersByType[0]!.count/6
            for vertexIndex in 0..<numberOfVertices {
              bridgeVertices.append(Vertex(position: float3((object.triangleBuffersByType[0]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                            (object.triangleBuffersByType[0]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                            (object.triangleBuffersByType[0]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                           normal: float3(object.triangleBuffersByType[0]![6*vertexIndex+3],
                                                          object.triangleBuffersByType[0]![6*vertexIndex+4],
                                                          object.triangleBuffersByType[0]![6*vertexIndex+5])))
            }
          }
        case 8:
          if object.triangleBuffersByType.keys.contains(0) {
            let numberOfVertices = object.triangleBuffersByType[0]!.count/6
            for vertexIndex in 0..<numberOfVertices {
              landUseVertices.append(Vertex(position: float3((object.triangleBuffersByType[0]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                             (object.triangleBuffersByType[0]![6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                             (object.triangleBuffersByType[0]![6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                            normal: float3(object.triangleBuffersByType[0]![6*vertexIndex+3],
                                                           object.triangleBuffersByType[0]![6*vertexIndex+4],
                                                           object.triangleBuffersByType[0]![6*vertexIndex+5])))
            }
          }
        default:
          break
        }
      }
    }
    
    //    Swift.print("\(buildingVertices.count) building vertices, \(buildingRoofVertices.count) building roof vertices")
    metalView!.edgesBuffer = metalView!.device!.makeBuffer(bytes: edgeVertices, length: MemoryLayout<Vertex>.size*edgeVertices.count, options: [])
    metalView!.buildingsBuffer = metalView!.device!.makeBuffer(bytes: buildingVertices, length: MemoryLayout<Vertex>.size*buildingVertices.count, options: [])
    metalView!.buildingRoofsBuffer = metalView!.device!.makeBuffer(bytes: buildingRoofVertices, length: MemoryLayout<Vertex>.size*buildingRoofVertices.count, options: [])
    metalView!.roadsBuffer = metalView!.device!.makeBuffer(bytes: roadVertices, length: MemoryLayout<Vertex>.size*roadVertices.count, options: [])
    metalView!.waterBuffer = metalView!.device!.makeBuffer(bytes: waterVertices, length: MemoryLayout<Vertex>.size*waterVertices.count, options: [])
    metalView!.plantCoverBuffer = metalView!.device!.makeBuffer(bytes: plantCoverVertices, length: MemoryLayout<Vertex>.size*plantCoverVertices.count, options: [])
    metalView!.terrainBuffer = metalView!.device!.makeBuffer(bytes: terrainVertices, length: MemoryLayout<Vertex>.size*terrainVertices.count, options: [])
    metalView!.genericBuffer = metalView!.device!.makeBuffer(bytes: genericVertices, length: MemoryLayout<Vertex>.size*genericVertices.count, options: [])
    metalView!.bridgesBuffer = metalView!.device!.makeBuffer(bytes: bridgeVertices, length: MemoryLayout<Vertex>.size*bridgeVertices.count, options: [])
    metalView!.landUseBuffer = metalView!.device!.makeBuffer(bytes: roadVertices, length: MemoryLayout<Vertex>.size*landUseVertices.count, options: [])
    metalView!.boundingBoxBuffer = metalView!.device!.makeBuffer(bytes: boundingBoxVertices, length: MemoryLayout<Vertex>.size*boundingBoxVertices.count, options: [])
    metalView!.selectedEdgesBuffer = metalView!.device!.makeBuffer(bytes: selectionEdgeVertices, length: MemoryLayout<Vertex>.size*selectionEdgeVertices.count, options: [])
    metalView!.selectedFacesBuffer = metalView!.device!.makeBuffer(bytes: selectionFaceVertices, length: MemoryLayout<Vertex>.size*selectionFaceVertices.count, options: [])
  }
  
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    Swift.print("numberOfChildrenOfItem of \(item)")
    if item == nil {
      return objects.count
    } else {
      return 0
    }
  }
  
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    //    Swift.print("isItemExpandable of \(item)")
    return false
  }
  
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    //    Swift.print("child \(index) of \(item)")
    return objects[index]
  }
  
  func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
    let object = item as! CityGMLObject
    //    Swift.print("object value for column \(tableColumn!.title) for item \(item) = \(object.id)")
    return object.id
  }
  
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    let object = item as! CityGMLObject
    //    Swift.print("view for column \(tableColumn!.identifier) for item \(item) = \(object.id)")
    let view = outlineView.make(withIdentifier: tableColumn!.identifier, owner: self) as! NSTableCellView
    view.textField?.stringValue = object.id
    switch object.type {
    case 1:
      view.imageView?.image = NSImage(named: "building")
    case 2:
      view.imageView?.image = NSImage(named: "road")
    case 3:
      view.imageView?.image = NSImage(named: "water")
    case 4:
      view.imageView?.image = NSImage(named: "terrain")
    case 5:
      view.imageView?.image = NSImage(named: "plant")
    case 6:
      view.imageView?.image = NSImage(named: "generic")
    case 7:
      view.imageView?.image = NSImage(named: "bridge")
    case 8:
      view.imageView?.image = NSImage(named: "landuse")
    default:
      view.imageView?.image = NSImage(named: "generic")
    }
    
    return view
  }
  
  func outlineViewSelectionDidChange(_ notification: Notification) {
    Swift.print("outlineViewSelectionDidChange")
    selection.removeAll()
    for row in controller!.outlineView.selectedRowIndexes {
      let item = controller!.outlineView.item(atRow: row) as! CityGMLObject
      Swift.print("\tSelected row: \(item.id)")
      selection.insert(item.id)
    }
    pushData()
    metalView!.needsDisplay = true
  }
  
  func outlineViewDoubleClick(_ sender: Any?) {
    Swift.print("outlineViewDoubleClick()")
    
    // Obtain object at that row
    let rowObject = controller!.outlineView.item(atRow: controller!.outlineView!.clickedRow) as! CityGMLObject
    
    // Iterate through all parsed objects
    for parsedObject in objects {
      
      // Found
      if parsedObject.id == rowObject.id {
        
        // Compute centroid
        let numberOfVertices = parsedObject.triangleBuffersByType[0]!.count/6
        var sumX: Float = 0.0
        var sumY: Float = 0.0
        var sumZ: Float = 0.0
        for vertexIndex in 0..<numberOfVertices {
          sumX = sumX + (parsedObject.triangleBuffersByType[0]![6*vertexIndex]-midCoordinates.x)/maxRange
          sumY = sumY + (parsedObject.triangleBuffersByType[0]![6*vertexIndex+1]-midCoordinates.y)/maxRange
          sumZ = sumZ + (parsedObject.triangleBuffersByType[0]![6*vertexIndex+2]-midCoordinates.z)/maxRange
        }
        let centroidInObjectCoordinates = float4(sumX/Float(numberOfVertices), sumY/Float(numberOfVertices), sumZ/Float(numberOfVertices), 1.0)
        
        // Use the centroid to compute the shift in the view space
        let objectToCamera = matrix_multiply(metalView!.viewMatrix, metalView!.modelMatrix)
        let centroidInCameraCoordinates = matrix_multiply(objectToCamera, centroidInObjectCoordinates)
        
        // Compute shift in object space
        let shiftInCameraCoordinates = float3(-centroidInCameraCoordinates.x, -centroidInCameraCoordinates.y, 0.0)
        var cameraToObject = matrix_invert(matrix_upper_left_3x3(matrix: objectToCamera))
        let shiftInObjectCoordinates = matrix_multiply(cameraToObject, shiftInCameraCoordinates)
        metalView!.modelTranslationToCentreOfRotationMatrix = matrix_multiply(metalView!.modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: shiftInObjectCoordinates))
        metalView!.modelMatrix = matrix_multiply(matrix_multiply(metalView!.modelShiftBackMatrix, metalView!.modelRotationMatrix), metalView!.modelTranslationToCentreOfRotationMatrix)
        
        // Correct shift so that the point of rotation remains at the same depth as the data
        cameraToObject = matrix_invert(matrix_upper_left_3x3(matrix: matrix_multiply(metalView!.viewMatrix, metalView!.modelMatrix)))
        let depthOffset = 1.0+metalView!.depthAtCentre()
        let depthOffsetInCameraCoordinates = float3(0.0, 0.0, -depthOffset)
        let depthOffsetInObjectCoordinates = matrix_multiply(cameraToObject, depthOffsetInCameraCoordinates)
        metalView!.modelTranslationToCentreOfRotationMatrix = matrix_multiply(metalView!.modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: depthOffsetInObjectCoordinates))
        metalView!.modelMatrix = matrix_multiply(matrix_multiply(metalView!.modelShiftBackMatrix, metalView!.modelRotationMatrix), metalView!.modelTranslationToCentreOfRotationMatrix)
        
        // Put model matrix in arrays and render
        metalView!.constants.modelMatrix = metalView!.modelMatrix
        metalView!.constants.modelViewProjectionMatrix = matrix_multiply(metalView!.projectionMatrix, matrix_multiply(metalView!.viewMatrix, metalView!.modelMatrix))
        metalView!.constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: metalView!.modelMatrix)))
        metalView!.needsDisplay = true
      }
    }
  }
  
  func findObjectRow(with id: String) -> Int {
    for row in 0..<controller!.outlineView.numberOfRows {
      let object = controller!.outlineView.item(atRow: row) as! CityGMLObject
      if object.id == id {
        return row
      }
    }
    return -1
  }
}
