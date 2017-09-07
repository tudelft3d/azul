// azul
// Copyright © 2016-2017 Ken Arroyo Ohori
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

import Cocoa

class CityGMLObject {
  var id: String = ""
  var type: String = ""
  var attributes = [CityGMLObjectAttribute]()
  var triangleBuffersByType = [String: ContiguousArray<Float>]()
  var edgesBuffer = ContiguousArray<Float>()
}

struct CityGMLObjectAttribute {
  var name: String
  var value: String
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
    let parser = ParserWrapperWrapper()!
    controller?.progressIndicator.startAnimation(self)
    
    DispatchQueue.global().async(qos: .userInitiated) {
      for url in urls {
        
        if self.openFiles.contains(url) {
          Swift.print("\(url) already open")
          continue
        }
        
        Swift.print("Loading \(url)")
        let parsingStartTime = CACurrentMediaTime()
        url.path.utf8CString.withUnsafeBufferPointer { pointer in
          if url.path.hasSuffix(".gml") || url.path.hasSuffix(".xml") {
            parser.parseCityGML(pointer.baseAddress)
          } else if url.path.hasSuffix(".json") {
            parser.parseCityJSON(pointer.baseAddress)
          }
        }
        Swift.print("\t1. Parsed data in \(CACurrentMediaTime()-parsingStartTime) seconds.")
        
        self.openFiles.insert(url)
        NSDocumentController.shared().noteNewRecentDocumentURL(url)
        
      }
      
      self.storeData(in: parser)
      parser.clear()
      
      while self.view == nil {
        Thread.sleep(forTimeInterval: 0.01)
      }
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
          self.controller!.window.title = "azul"
        case 1:
          self.controller!.window.representedURL = self.openFiles.first!
          self.controller!.window.title = self.openFiles.first!.lastPathComponent
        default:
          self.controller!.window.representedURL = nil
          self.controller!.window.title = "azul (\(self.openFiles.count) open files)"
        }
        if let metalView = self.view as? MetalView {
          metalView.needsDisplay = true
        } else {
          let openGLView = self.view as! OpenGLView
          openGLView.renderFrame()
        }
        self.controller!.outlineView.reloadData()
        Swift.print("Total: Loaded data in \(CACurrentMediaTime()-startTime) seconds.")
      }
    }
  }
  
  func storeData(in cityGMLParser: ParserWrapperWrapper) {
    Swift.print("DataStorage.storeData(ParserWrapperWrapper)")
    let startTime = CACurrentMediaTime()
    
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
//      Swift.print("Object with id \(objects.last!.id)")
      
      var objectTypeLength: UInt = 0
      let firstElementOfObjectTypeBuffer = UnsafeRawPointer(cityGMLParser.currentObjectType(withLength: &objectTypeLength))
      let objectTypeData = Data(bytes: firstElementOfObjectTypeBuffer!, count: Int(objectTypeLength)*MemoryLayout<Int8>.size)
      objects.last!.type = String(data: objectTypeData, encoding: .utf8)!
      
      cityGMLParser.initialiseAttributeIterator()
      while !cityGMLParser.attributeIteratorEnded() {
        
        var attributeNameLength: UInt = 0
        let firstElementOfAttributeNameBuffer = UnsafeRawPointer(cityGMLParser.currentAttributeName(withLength: &attributeNameLength))
        let attributeNameData = Data(bytes: firstElementOfAttributeNameBuffer!, count: Int(attributeNameLength)*MemoryLayout<Int8>.size)
        let attributeName = String(data: attributeNameData, encoding: .utf8)
        if attributeName == nil {
          Swift.print("Couldn't parse attribute name with \(attributeNameData)")
          cityGMLParser.advanceAttributeIterator()
          continue
        }
        
        var attributeValueLength: UInt = 0
        let firstElementOfAttributeValueBuffer = UnsafeRawPointer(cityGMLParser.currentAttributeValue(withLength: &attributeValueLength))
        let attributeValueData = Data(bytes: firstElementOfAttributeValueBuffer!, count: Int(attributeValueLength)*MemoryLayout<Int8>.size)
        let attributeValue = String(data: attributeValueData, encoding: .utf8)
        if attributeValue == nil {
          Swift.print("Couldn't parse attribute value with \(attributeValueData.base64EncodedString())")
          cityGMLParser.advanceAttributeIterator()
          continue
        }
        
        objects.last!.attributes.append(CityGMLObjectAttribute(name: attributeName!, value: attributeValue!))
        cityGMLParser.advanceAttributeIterator()
      }
      
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
    Swift.print("\t2. Stored data in \(CACurrentMediaTime()-startTime) seconds.")
  }
  
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
//    Swift.print("numberOfChildrenOfItem of \(item)")
    if item == nil {
      return objects.count
    } else if let object = item as? CityGMLObject {
      return object.attributes.count
    } else if (item as? CityGMLObjectAttribute) != nil {
      return 0
    } else {
      Swift.print("Unsupported item is \(item!)")
      return 0
    }
  }
  
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    //    Swift.print("isItemExpandable of \(item)")
    if let object = item as? CityGMLObject {
      if object.attributes.count > 0 {
        return true
      }
    }
    return false
  }
  
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    //    Swift.print("child \(index) of \(item)")
    if item == nil {
      return objects[index]
    } else if let object = item as? CityGMLObject {
      return object.attributes[index]
    } else {
      return 0
    }
  }
  
  func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
    //    Swift.print("object value for column \(tableColumn!.title) for item \(item) = \(object.id)")
    if let object = item as? CityGMLObject {
      return object.id
    } else if let attribute = item as? CityGMLObjectAttribute {
      return attribute.name + ": " + attribute.value
    } else {
      return nil
    }
  }
  
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    //    Swift.print("view for column \(tableColumn!.identifier) for item \(item) = \(object.id)")
    let view = outlineView.make(withIdentifier: tableColumn!.identifier, owner: self) as! NSTableCellView
    if let object = item as? CityGMLObject {
      view.textField!.stringValue = object.id
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
    } else if let attribute = item as? CityGMLObjectAttribute {
      view.textField!.stringValue = String(attribute.name + ": " + attribute.value)
      view.imageView?.image = nil
    } else {
      Swift.print("Unsupported item is \(item)")
    }
    return view
  }
  
  func outlineViewSelectionDidChange(_ notification: Notification) {
//    Swift.print("outlineViewSelectionDidChange")
    selection.removeAll()
    for row in controller!.outlineView.selectedRowIndexes {
      if let item = controller!.outlineView.item(atRow: row) as? CityGMLObject {
//      Swift.print("\tSelected row: \(item.id)")
        selection.insert(item.id)
      }
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
