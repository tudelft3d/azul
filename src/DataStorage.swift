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

class CityGMLObject {
  var id: String = ""
  var type: String = ""
  var attributes = [String: String]()
  var triangleBuffersByType = [String: ContiguousArray<Float>]()
  var edgesBuffer = ContiguousArray<Float>()
}

class DataStorage: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
  
  var controller: Controller?
  var view: NSView?
  
  var openFiles = Set<URL>()
  var objects = [CityGMLObject]()
  
  var selection = Set<String>()
  
  var minCoordinates: [Float] = [0, 0, 0]
  var maxCoordinates: [Float] = [0, 0, 0]
  
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
      
      self.storeData(in: cityGMLParser)
      if let metalView = self.view as? MetalView {
        metalView.pullData()
      } else {
        let openGLView = self.view as! OpenGLView
        openGLView.pullData()
      }
      
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
        if let metalView = self.view as? MetalView {
          metalView.needsDisplay = true
        } else {
          let openGLView = self.view as! OpenGLView
          openGLView.renderFrame()
        }
        self.controller!.outlineView.reloadData()
      }
    }
  }
  
  func storeData(in cityGMLParser: CityGMLParserWrapperWrapper) {
    Swift.print("DataStorage.storeData(CityGMLParserWrapperWrapper)")
    
    let firstMinCoordinate = cityGMLParser.minCoordinates()
    let minCoordinatesBuffer = UnsafeBufferPointer(start: firstMinCoordinate, count: 3)
    var minCoordinatesArray = ContiguousArray(minCoordinatesBuffer)
    let firstMaxCoordinate = cityGMLParser.maxCoordinates()
    let maxCoordinatesBuffer = UnsafeBufferPointer(start: firstMaxCoordinate, count: 3)
    var maxCoordinatesArray = ContiguousArray(maxCoordinatesBuffer)
    if objects.count == 0 {
      minCoordinates = [Float](minCoordinatesArray)
      maxCoordinates = [Float](maxCoordinatesArray)
    } else {
      for currentCoordinate in 0..<3 {
        if minCoordinatesArray[currentCoordinate] < minCoordinates[currentCoordinate] {
          minCoordinates[currentCoordinate] = minCoordinatesArray[currentCoordinate]
        }
        if maxCoordinatesArray[currentCoordinate] > maxCoordinates[currentCoordinate] {
          maxCoordinates[currentCoordinate] = maxCoordinatesArray[currentCoordinate]
        }
      }
    }
    
    cityGMLParser.initialiseObjectIterator()
    while !cityGMLParser.objectIteratorEnded() {
      
      objects.append(CityGMLObject())
      
      var idLength: UInt = 0
      let firstElementOfIdBuffer = UnsafeRawPointer(cityGMLParser.currentObjectIdentifier(withLength: &idLength))
      let idData = Data(bytes: firstElementOfIdBuffer!, count: Int(idLength)*MemoryLayout<Int8>.size)
      objects.last!.id = String(data: idData, encoding: .utf8)!
      
      var objectTypeLength: UInt = 0
      let firstElementOfObjectTypeBuffer = UnsafeRawPointer(cityGMLParser.currentObjectType(withLength: &objectTypeLength))
      let objectTypeData = Data(bytes: firstElementOfObjectTypeBuffer!, count: Int(objectTypeLength)*MemoryLayout<Int8>.size)
      objects.last!.type = String(data: objectTypeData, encoding: .utf8)!
      
      var numberOfEdgeVertices: UInt = 0
      let firstElementOfEdgesBuffer = cityGMLParser.currentObjectEdgesBuffer(withElements: &numberOfEdgeVertices)
      let edgesBuffer = UnsafeBufferPointer(start: firstElementOfEdgesBuffer, count: Int(numberOfEdgeVertices))
      objects.last!.edgesBuffer = ContiguousArray(edgesBuffer)
      
      cityGMLParser.initialiseTriangleBufferIterator()
      while !cityGMLParser.triangleBufferIteratorEnded() {
        var trianglesBufferTypeLength: UInt = 0
        let firstElementOfTrianglesBufferTypeBuffer = UnsafeRawPointer(cityGMLParser.currentTrianglesBufferType(withLength: &trianglesBufferTypeLength))
        let trianglesBufferTypeData = Data(bytes: firstElementOfTrianglesBufferTypeBuffer!, count: Int(trianglesBufferTypeLength)*MemoryLayout<Int8>.size)
        let trianglesBufferType = String(data: trianglesBufferTypeData, encoding: .utf8)!
        
        var numberOfTriangleVertices: UInt = 0
        let firstElementOfTrianglesBuffer = cityGMLParser.currentTrianglesBuffer(withElements: &numberOfTriangleVertices)
        let trianglesBuffer = UnsafeBufferPointer(start: firstElementOfTrianglesBuffer, count: Int(numberOfTriangleVertices))
        
        objects.last!.triangleBuffersByType[trianglesBufferType] = ContiguousArray(trianglesBuffer)
        cityGMLParser.advanceTriangleBufferIterator()
      }
      
      cityGMLParser.advanceObjectIterator()
    }
  }
  
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
//    Swift.print("numberOfChildrenOfItem of \(item)")
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
    case "Building":
      view.imageView?.image = NSImage(named: "building")
    case "Road":
      view.imageView?.image = NSImage(named: "road")
    case "ReliefFeature":
      view.imageView?.image = NSImage(named: "terrain")
    case "WaterBody":
      view.imageView?.image = NSImage(named: "water")
    case "PlantCover":
      view.imageView?.image = NSImage(named: "plant")
    case "GenericCityObject":
      view.imageView?.image = NSImage(named: "generic")
    case "Bridge":
      view.imageView?.image = NSImage(named: "bridge")
    case "LandUse":
      view.imageView?.image = NSImage(named: "landuse")
    case "SolitaryVegetationObject":
      view.imageView?.image = NSImage(named: "tree")
    case "Railway":
      view.imageView?.image = NSImage(named: "railway")
    case "CityFurniture":
      view.imageView?.image = NSImage(named: "bench")
    default:
      view.imageView?.image = NSImage(named: "generic")
    }
    
    return view
  }
  
  func outlineViewSelectionDidChange(_ notification: Notification) {
//    Swift.print("outlineViewSelectionDidChange")
    selection.removeAll()
    for row in controller!.outlineView.selectedRowIndexes {
      let item = controller!.outlineView.item(atRow: row) as! CityGMLObject
//      Swift.print("\tSelected row: \(item.id)")
      selection.insert(item.id)
    }
    if let metalView = view as? MetalView {
      metalView.pullData()
      metalView.needsDisplay = true
    } else {
      let openGLView = view as! OpenGLView
      openGLView.pullData()
      openGLView.renderFrame()
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
