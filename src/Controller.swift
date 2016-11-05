//
//  Controller.swift
//  Azul
//
//  Copyright © 2016 Ken Arroyo Ohori. All rights reserved.
//

import Cocoa
import OpenGL.GL3
import GLKit

class OutlineViewObject {
  var id: String = ""
  var type: UInt32 = 0
}

@NSApplicationMain
class Controller: NSObject, NSApplicationDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate {

  @IBOutlet weak var window: NSWindow!
  @IBOutlet weak var splitView: NSSplitView!
  @IBOutlet weak var outlineView: NSOutlineView!
  @IBOutlet weak var openGLView: OpenGLView!
  @IBOutlet weak var progressIndicator: NSProgressIndicator!
  
  @IBOutlet weak var toggleViewEdgesMenuItem: NSMenuItem!
  @IBOutlet weak var toggleViewBoundingBoxMenuItem: NSMenuItem!
  @IBOutlet weak var goHomeMenuItem: NSMenuItem!
  @IBOutlet weak var toggleSideBarMenuItem: NSMenuItem!
  
  let cityGMLParser = CityGMLParserWrapperWrapper()
  
  var openFiles = Set<URL>()
  var objects = [OutlineViewObject]()
  var selection = Set<String>()
  var loadingData: Bool = false

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    Swift.print("Controller.applicationDidFinishLaunching()")
    openGLView.controller = self
    outlineView.dataSource = self
    outlineView.delegate = self
    outlineView.doubleAction = #selector(outlineViewDoubleClick)
    toggleSideBar(toggleSideBarMenuItem)
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }
  
  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    Swift.print("Controller.application(NSApplication, openFile: String)")
    Swift.print("Open \(filename)")
    let url = URL(fileURLWithPath: filename)
    self.loadData(from: [url])
    return true
  }
  
  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    Swift.print("Controller.application(NSApplication, openFiles: String)")
    Swift.print("Open \(filenames)")
    var urls = [URL]()
    for filename in filenames {
      urls.append(URL(fileURLWithPath: filename))
      
    }
    self.loadData(from: urls)
  }
  
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
  
  @IBAction func new(_ sender: NSMenuItem) {
    Swift.print("Controller.new(NSMenuItem)")
    
    openFiles = Set<URL>()
    self.window.representedURL = nil
    self.window.title = "Azul"
    
    cityGMLParser!.clear()
    objects.removeAll()
    self.outlineView.reloadData()
    
    openGLView.buildingsTriangles.removeAll()
    openGLView.buildingRoofsTriangles.removeAll()
    openGLView.roadsTriangles.removeAll()
    openGLView.terrainTriangles.removeAll()
    openGLView.waterTriangles.removeAll()
    openGLView.plantCoverTriangles.removeAll()
    openGLView.genericTriangles.removeAll()
    openGLView.bridgeTriangles.removeAll()
    openGLView.landUseTriangles.removeAll()
    openGLView.edges.removeAll()
    openGLView.boundingBox.removeAll()
    openGLView.selectionFaces.removeAll()
    openGLView.selectionEdges.removeAll()
    
    openGLView.fieldOfView = GLKMathDegreesToRadians(45.0)
    
    openGLView.modelTranslationToCentreOfRotation = GLKMatrix4Identity
    openGLView.modelRotation = GLKMatrix4Identity
    openGLView.modelShiftBack = GLKMatrix4MakeTranslation(openGLView.centre.x, openGLView.centre.y, openGLView.centre.z)
    openGLView.model = GLKMatrix4Multiply(GLKMatrix4Multiply(openGLView.modelShiftBack, openGLView.modelRotation), openGLView.modelTranslationToCentreOfRotation)
    openGLView.mArray = [openGLView.model.m00, openGLView.model.m01, openGLView.model.m02, openGLView.model.m03,
                         openGLView.model.m10, openGLView.model.m11, openGLView.model.m12, openGLView.model.m13,
                         openGLView.model.m20, openGLView.model.m21, openGLView.model.m22, openGLView.model.m23,
                         openGLView.model.m30, openGLView.model.m31, openGLView.model.m32, openGLView.model.m33]
    var isInvertible: Bool = true
    let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(openGLView.model), &isInvertible))
    openGLView.mitArray = [mit.m00, mit.m01, mit.m02,
                           mit.m10, mit.m11, mit.m12,
                           mit.m20, mit.m21, mit.m22]
    openGLView.view = GLKMatrix4MakeLookAt(openGLView.eye.x, openGLView.eye.y, openGLView.eye.z, openGLView.centre.x, openGLView.centre.y, openGLView.centre.z, 0.0, 1.0, 0.0)
    openGLView.vArray = [openGLView.view.m00, openGLView.view.m01, openGLView.view.m02, openGLView.view.m03,
                         openGLView.view.m10, openGLView.view.m11, openGLView.view.m12, openGLView.view.m13,
                         openGLView.view.m20, openGLView.view.m21, openGLView.view.m22, openGLView.view.m23,
                         openGLView.view.m30, openGLView.view.m31, openGLView.view.m32, openGLView.view.m33]
    openGLView.projection = GLKMatrix4MakePerspective(openGLView.fieldOfView, 1.0/Float(openGLView.bounds.size.height/openGLView.bounds.size.width), 0.001, 100.0)
    openGLView.pArray = [openGLView.projection.m00, openGLView.projection.m01, openGLView.projection.m02, openGLView.projection.m03,
                         openGLView.projection.m10, openGLView.projection.m11, openGLView.projection.m12, openGLView.projection.m13,
                         openGLView.projection.m20, openGLView.projection.m21, openGLView.projection.m22, openGLView.projection.m23,
                         openGLView.projection.m30, openGLView.projection.m31, openGLView.projection.m32, openGLView.projection.m33]
    
    regenerateOpenGLRepresentation()
    
    openGLView.renderFrame()
  }

  @IBAction func openFile(_ sender: NSMenuItem) {
    Swift.print("Controller.openFile(NSMenuItem)")
    
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = true
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
    openPanel.allowedFileTypes = ["gml", "xml"]
    openPanel.begin(completionHandler:{(result: Int) in
      if result == NSFileHandlingPanelOKButton {
        self.loadData(from: openPanel.urls)
      }
    })
  }
  
  func loadData(from urls: [URL]) {
    Swift.print("Controller.loadData(URL)")
    Swift.print("Opening \(urls)")
    
    self.loadingData = true
    progressIndicator.startAnimation(self)
//    let updateProgressTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.updateProgressIndicator), userInfo: nil, repeats: true)
    
    DispatchQueue.global().async(qos: .userInitiated) {
      for url in urls {
    
        if self.openFiles.contains(url) {
          Swift.print("\(url) already open")
          continue
        }
        
//        Swift.print("Loading \(url)")
        url.path.utf8CString.withUnsafeBufferPointer { pointer in
          self.cityGMLParser!.parse(pointer.baseAddress)
        }
  
        self.openFiles.insert(url)
        NSDocumentController.shared().noteNewRecentDocumentURL(url)
        
      }
      
      self.regenerateOpenGLRepresentation()
//      updateProgressTimer.invalidate()
      self.loadingData = false
      
      DispatchQueue.main.async {
        self.progressIndicator.stopAnimation(self)
        self.openGLView.renderFrame()
        self.outlineView.reloadData()
        switch self.openFiles.count {
        case 0:
          self.window.representedURL = nil
          self.window.title = "Azul"
        case 1:
          self.window.representedURL = self.openFiles.first!
          self.window.title = self.openFiles.first!.lastPathComponent
        default:
          self.window.representedURL = nil
          self.window.title = "Azul (\(self.openFiles.count) open files)"
        }
      }
    }
  }
  
  @IBAction func toggleViewEdges(_ sender: NSMenuItem) {
    if openGLView.viewEdges {
      openGLView.viewEdges = false
      sender.state = 0
      openGLView.renderFrame()
    } else {
      openGLView.viewEdges = true
      sender.state = 1
      openGLView.renderFrame()
    }
  }
  
  @IBAction func toggleViewBoundingBox(_ sender: NSMenuItem) {
    if openGLView.viewBoundingBox {
      openGLView.viewBoundingBox = false
      sender.state = 0
      openGLView.renderFrame()
    } else {
      openGLView.viewBoundingBox = true
      sender.state = 1
      openGLView.renderFrame()
    }
  }
  
  @IBAction func goHome(_ sender: NSMenuItem) {
    openGLView.fieldOfView = GLKMathDegreesToRadians(45.0)
    
    openGLView.modelTranslationToCentreOfRotation = GLKMatrix4Identity
    openGLView.modelRotation = GLKMatrix4Identity
    openGLView.modelShiftBack = GLKMatrix4MakeTranslation(openGLView.centre.x, openGLView.centre.y, openGLView.centre.z)
    openGLView.model = GLKMatrix4Multiply(GLKMatrix4Multiply(openGLView.modelShiftBack, openGLView.modelRotation), openGLView.modelTranslationToCentreOfRotation)
    openGLView.mArray = [openGLView.model.m00, openGLView.model.m01, openGLView.model.m02, openGLView.model.m03,
                         openGLView.model.m10, openGLView.model.m11, openGLView.model.m12, openGLView.model.m13,
                         openGLView.model.m20, openGLView.model.m21, openGLView.model.m22, openGLView.model.m23,
                         openGLView.model.m30, openGLView.model.m31, openGLView.model.m32, openGLView.model.m33]
    var isInvertible: Bool = true
    let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(openGLView.model), &isInvertible))
    openGLView.mitArray = [mit.m00, mit.m01, mit.m02,
                           mit.m10, mit.m11, mit.m12,
                           mit.m20, mit.m21, mit.m22]
    openGLView.view = GLKMatrix4MakeLookAt(openGLView.eye.x, openGLView.eye.y, openGLView.eye.z, openGLView.centre.x, openGLView.centre.y, openGLView.centre.z, 0.0, 1.0, 0.0)
    openGLView.vArray = [openGLView.view.m00, openGLView.view.m01, openGLView.view.m02, openGLView.view.m03,
                         openGLView.view.m10, openGLView.view.m11, openGLView.view.m12, openGLView.view.m13,
                         openGLView.view.m20, openGLView.view.m21, openGLView.view.m22, openGLView.view.m23,
                         openGLView.view.m30, openGLView.view.m31, openGLView.view.m32, openGLView.view.m33]
    openGLView.projection = GLKMatrix4MakePerspective(openGLView.fieldOfView, 1.0/Float(openGLView.bounds.size.height/openGLView.bounds.size.width), 0.001, 100.0)
    openGLView.pArray = [openGLView.projection.m00, openGLView.projection.m01, openGLView.projection.m02, openGLView.projection.m03,
                         openGLView.projection.m10, openGLView.projection.m11, openGLView.projection.m12, openGLView.projection.m13,
                         openGLView.projection.m20, openGLView.projection.m21, openGLView.projection.m22, openGLView.projection.m23,
                         openGLView.projection.m30, openGLView.projection.m31, openGLView.projection.m32, openGLView.projection.m33]
    openGLView.renderFrame()
  }
  
  @IBAction func toggleSideBar(_ sender: NSMenuItem) {
    if splitView.subviews[0].bounds.size.width == 0 {
//      Swift.print("Open sidebar")
      splitView.setPosition(200, ofDividerAt: 0)
      sender.title = "Hide Sidebar"
    } else {
//      Swift.print("Close sidebar")
      splitView.setPosition(0, ofDividerAt: 0)
      sender.title = "Show Sidebar"
    }
  }
  
  func regenerateOpenGLRepresentation() {
    openGLView.buildingsTriangles.removeAll(keepingCapacity: true)
    openGLView.buildingRoofsTriangles.removeAll(keepingCapacity: true)
    openGLView.roadsTriangles.removeAll(keepingCapacity: true)
    openGLView.terrainTriangles.removeAll(keepingCapacity: true)
    openGLView.waterTriangles.removeAll(keepingCapacity: true)
    openGLView.plantCoverTriangles.removeAll(keepingCapacity: true)
    openGLView.genericTriangles.removeAll(keepingCapacity: true)
    openGLView.bridgeTriangles.removeAll(keepingCapacity: true)
    openGLView.landUseTriangles.removeAll(keepingCapacity: true)
    openGLView.edges.removeAll(keepingCapacity: true)
    openGLView.boundingBox.removeAll(keepingCapacity: true)
    openGLView.selectionFaces.removeAll(keepingCapacity: true)
    openGLView.selectionEdges.removeAll(keepingCapacity: true)
    
    objects.removeAll(keepingCapacity: true)
    
    cityGMLParser!.initialiseIterator()
    while !cityGMLParser!.iteratorEnded() {
//      Swift.print("Iterating...")
      
      var numberOfEdgeVertices: UInt = 0
      let firstElementOfEdgesBuffer = cityGMLParser!.edgesBuffer(&numberOfEdgeVertices)
      let edgesBuffer = UnsafeBufferPointer(start: firstElementOfEdgesBuffer, count: Int(numberOfEdgeVertices))
      let edges = ContiguousArray(edgesBuffer)
      var numberOfTriangleVertices: UInt = 0
      let firstElementOfTrianglesBuffer = cityGMLParser!.trianglesBuffer(&numberOfTriangleVertices)
      let trianglesBuffer = UnsafeBufferPointer(start: firstElementOfTrianglesBuffer, count: Int(numberOfTriangleVertices))
      let triangles = ContiguousArray(trianglesBuffer)
      var numberOfTriangleVertices2: UInt = 0
      let firstElementOfTrianglesBuffer2 = cityGMLParser!.triangles2Buffer(&numberOfTriangleVertices2)
      let trianglesBuffer2 = UnsafeBufferPointer(start: firstElementOfTrianglesBuffer2, count: Int(numberOfTriangleVertices2))
      let triangles2 = ContiguousArray(trianglesBuffer2)
      
      var idLength: UInt = 0
      let firstElementOfIdBuffer = UnsafeRawPointer(cityGMLParser!.identifier(&idLength))
      let idData = Data(bytes: firstElementOfIdBuffer!, count: Int(idLength)*MemoryLayout<Int8>.size)
      let id = String(data: idData, encoding: String.Encoding.utf8)
//      Swift.print("Added object \(id!)")
      
      objects.append(OutlineViewObject())
      objects.last!.id = id!
      objects.last!.type = cityGMLParser!.type()
      
      if selection.contains(id!) {
        Swift.print("Adding \(edges.count) edge vertices to the selection, \(openGLView.selectionEdges.count) were there before")
        openGLView.selectionEdges.append(contentsOf: edges)
        openGLView.selectionFaces.append(contentsOf: triangles)
        openGLView.selectionFaces.append(contentsOf: triangles2)
      } else {
        openGLView.edges.append(contentsOf: edges)
        switch cityGMLParser!.type() {
        case 1:
          openGLView.buildingsTriangles.append(contentsOf: triangles)
          openGLView.buildingRoofsTriangles.append(contentsOf: triangles2)
        case 2:
          openGLView.roadsTriangles.append(contentsOf: triangles)
        case 3:
          openGLView.terrainTriangles.append(contentsOf: triangles)
        case 4:
          openGLView.waterTriangles.append(contentsOf: triangles)
        case 5:
          openGLView.plantCoverTriangles.append(contentsOf: triangles)
        case 6:
          openGLView.genericTriangles.append(contentsOf: triangles)
        case 7:
          openGLView.bridgeTriangles.append(contentsOf: triangles)
        case 8:
          openGLView.landUseTriangles.append(contentsOf: triangles)
        default:
          break
        }
      }
      
      cityGMLParser!.advanceIterator()
    }
    
    let firstMinCoordinate = cityGMLParser!.minCoordinates()
    let minCoordinatesBuffer = UnsafeBufferPointer(start: firstMinCoordinate, count: 3)
    var minCoordinates = ContiguousArray(minCoordinatesBuffer)
    let firstMidCoordinate = cityGMLParser!.midCoordinates()
    let midCoordinatesBuffer = UnsafeBufferPointer(start: firstMidCoordinate, count: 3)
    let midCoordinates = ContiguousArray(midCoordinatesBuffer)
    let firstMaxCoordinate = cityGMLParser!.maxCoordinates()
    let maxCoordinatesBuffer = UnsafeBufferPointer(start: firstMaxCoordinate, count: 3)
    var maxCoordinates = ContiguousArray(maxCoordinatesBuffer)
    let maxRange = cityGMLParser!.maxRange()
    
    for coordinate in 0..<3 {
      minCoordinates[coordinate] = (minCoordinates[coordinate]-midCoordinates[coordinate])/maxRange
      maxCoordinates[coordinate] = (maxCoordinates[coordinate]-midCoordinates[coordinate])/maxRange
    }
    
    let boundingBoxVertices: [GLfloat] = [minCoordinates[0], minCoordinates[1], minCoordinates[2],  // 000 -> 001
                                          minCoordinates[0], minCoordinates[1], maxCoordinates[2],
                                          minCoordinates[0], minCoordinates[1], minCoordinates[2],  // 000 -> 010
                                          minCoordinates[0], maxCoordinates[1], minCoordinates[2],
                                          minCoordinates[0], minCoordinates[1], minCoordinates[2],  // 000 -> 100
                                          maxCoordinates[0], minCoordinates[1], minCoordinates[2],
                                          minCoordinates[0], minCoordinates[1], maxCoordinates[2],  // 001 -> 011
                                          minCoordinates[0], maxCoordinates[1], maxCoordinates[2],
                                          minCoordinates[0], minCoordinates[1], maxCoordinates[2],  // 001 -> 101
                                          maxCoordinates[0], minCoordinates[1], maxCoordinates[2],
                                          minCoordinates[0], maxCoordinates[1], minCoordinates[2],  // 010 -> 011
                                          minCoordinates[0], maxCoordinates[1], maxCoordinates[2],
                                          minCoordinates[0], maxCoordinates[1], minCoordinates[2],  // 010 -> 110
                                          maxCoordinates[0], maxCoordinates[1], minCoordinates[2],
                                          minCoordinates[0], maxCoordinates[1], maxCoordinates[2],  // 011 -> 111
                                          maxCoordinates[0], maxCoordinates[1], maxCoordinates[2],
                                          maxCoordinates[0], minCoordinates[1], minCoordinates[2],  // 100 -> 101
                                          maxCoordinates[0], minCoordinates[1], maxCoordinates[2],
                                          maxCoordinates[0], minCoordinates[1], minCoordinates[2],  // 100 -> 110
                                          maxCoordinates[0], maxCoordinates[1], minCoordinates[2],
                                          maxCoordinates[0], minCoordinates[1], maxCoordinates[2],  // 101 -> 111
                                          maxCoordinates[0], maxCoordinates[1], maxCoordinates[2],
                                          maxCoordinates[0], maxCoordinates[1], minCoordinates[2],  // 110 -> 111
                                          maxCoordinates[0], maxCoordinates[1], maxCoordinates[2]
    ]
    openGLView.boundingBox.append(contentsOf: boundingBoxVertices)
    
    openGLView.openGLContext!.makeCurrentContext()
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("There's a previous OpenGL error")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboBuildings)
    openGLView.buildingsTriangles.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.buildingsTriangles.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading building triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboBuildingRoofs)
    openGLView.buildingRoofsTriangles.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.buildingRoofsTriangles.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading building roof triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboRoads)
    openGLView.roadsTriangles.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.roadsTriangles.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading road triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboWater)
    openGLView.waterTriangles.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.waterTriangles.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading water body triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboPlantCover)
    openGLView.plantCoverTriangles.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.plantCoverTriangles.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading plant cover triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboTerrain)
    openGLView.terrainTriangles.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.terrainTriangles.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading terrain triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboGeneric)
    openGLView.genericTriangles.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.genericTriangles.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading generic triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboBridges)
    openGLView.bridgeTriangles.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.bridgeTriangles.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading bridge triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboLandUse)
    openGLView.landUseTriangles.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.landUseTriangles.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading land use triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboEdges)
    openGLView.edges.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.edges.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading edges into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboBoundingBox)
    openGLView.boundingBox.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.boundingBox.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading bounding box edges into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboSelectionFaces)
    openGLView.selectionFaces.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.selectionFaces.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading selection triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), openGLView.vboSelectionEdges)
    openGLView.selectionEdges.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), openGLView.selectionEdges.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_DYNAMIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading selection edges into memory: some error occurred!")
    }
    
    Swift.print("Loaded triangles: \(openGLView.buildingsTriangles.count/18) from buildings, \(openGLView.buildingRoofsTriangles.count) from building roofs, \(openGLView.roadsTriangles.count/18) from roads, \(openGLView.waterTriangles.count/18) from water bodies, \(openGLView.plantCoverTriangles.count/18) from plant cover, \(openGLView.genericTriangles.count/18) from generic objects, \(openGLView.bridgeTriangles.count/18) from bridges, \(openGLView.landUseTriangles.count/18) from land use and \(openGLView.selectionFaces.count/18) from selected objects.")
    Swift.print("Loaded \(openGLView.edges.count/6) edges, \(openGLView.boundingBox.count/6) edges from the bounding box and \(openGLView.selectionEdges.count/6) edges from the selection.")
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
    let object = item as! OutlineViewObject
//    Swift.print("object value for column \(tableColumn!.title) for item \(item) = \(object.id)")
    return object.id
  }
  
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    let object = item as! OutlineViewObject
//    Swift.print("view for column \(tableColumn!.title) for item \(item) = \(object.id)")
    let view = outlineView.make(withIdentifier: tableColumn!.identifier, owner: self) as! NSTableCellView
    view.textField?.stringValue = object.id
    switch object.type {
    case 1:
      view.imageView?.image = NSImage(named: "building")
    case 2:
      view.imageView?.image = NSImage(named: "road")
    case 4:
      view.imageView?.image = NSImage(named: "water")
    case 5:
      view.imageView?.image = NSImage(named: "plant")
    default:
      view.imageView?.image = NSImage(named: "generic")
    }
    
    return view
  }
  
  func outlineViewSelectionDidChange(_ notification: Notification) {
    Swift.print("outlineViewSelectionDidChange")
    selection.removeAll()
    for row in outlineView.selectedRowIndexes {
      let item = outlineView.item(atRow: row) as! OutlineViewObject
      Swift.print("\tSelected row: \(item.id)")
      selection.insert(item.id)
    }
    regenerateOpenGLRepresentation()
    openGLView.renderFrame()
  }
  
  func outlineViewDoubleClick(_ sender: Any?) {
    Swift.print("outlineViewDoubleClick()")
    
    // Obtain object at that row
    let object = outlineView.item(atRow: outlineView!.clickedRow) as! OutlineViewObject
    
    // Iterate through all parsed objects
    cityGMLParser!.initialiseIterator()
    while !cityGMLParser!.iteratorEnded() {
      
      var idLength: UInt = 0
      let firstElementOfIdBuffer = UnsafeRawPointer(cityGMLParser!.identifier(&idLength))
      let idData = Data(bytes: firstElementOfIdBuffer!, count: Int(idLength)*MemoryLayout<Int8>.size)
      let id = String(data: idData, encoding: String.Encoding.utf8)
      
      // Found
      if id == object.id {
        var numberOfTriangleFloats: UInt = 0
        let firstElementOfTrianglesBuffer = cityGMLParser!.trianglesBuffer(&numberOfTriangleFloats)
        let trianglesBuffer = UnsafeBufferPointer(start: firstElementOfTrianglesBuffer, count: Int(numberOfTriangleFloats))
        let triangles = ContiguousArray(trianglesBuffer)
        
        // Compute centroid
        let numberOfTriangles = numberOfTriangleFloats/18
        var sumX: Float = 0.0
        var sumY: Float = 0.0
        var sumZ: Float = 0.0
        for triangleIndex in 0..<numberOfTriangles {
          sumX = sumX + triangles[Int(18*triangleIndex)] + triangles[Int(18*triangleIndex+6)] + triangles[Int(18*triangleIndex+12)]
          sumY = sumY + triangles[Int(18*triangleIndex+1)] + triangles[Int(18*triangleIndex+7)] + triangles[Int(18*triangleIndex+13)]
          sumZ = sumZ + triangles[Int(18*triangleIndex+2)] + triangles[Int(18*triangleIndex+8)] + triangles[Int(18*triangleIndex+14)]
        }
        let centroidInObjectCoordinates = GLKVector4Make(sumX/Float(numberOfTriangles*3), sumY/Float(numberOfTriangles*3), sumZ/Float(numberOfTriangles*3), 1.0)
        
        // Use the centroid to compute the shift in the view space
        let objectToCamera = GLKMatrix4Multiply(openGLView.model, openGLView.view)
        let centroidInCameraCoordinates = GLKMatrix4MultiplyVector4(objectToCamera, centroidInObjectCoordinates)
        
        // Compute shift in object space
        let shiftInCameraCoordinates: GLKVector3 = GLKVector3Make(-centroidInCameraCoordinates.x, -centroidInCameraCoordinates.y, 0.0)
        var isInvertible: Bool = true
        var cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(objectToCamera), &isInvertible)
        let shiftInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, shiftInCameraCoordinates)
        openGLView.modelTranslationToCentreOfRotation = GLKMatrix4TranslateWithVector3(openGLView.modelTranslationToCentreOfRotation, shiftInObjectCoordinates)
        openGLView.model = GLKMatrix4Multiply(GLKMatrix4Multiply(openGLView.modelShiftBack, openGLView.modelRotation), openGLView.modelTranslationToCentreOfRotation)
        
        // Correct shift so that the point of rotation remains at the same depth as the data
        cameraToObject = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(openGLView.model, openGLView.view)), &isInvertible)
        let depthOffset = 1.0+openGLView.depthAtCentre()
        let depthOffsetInCameraCoordinates: GLKVector3 = GLKVector3Make(0.0, 0.0, -depthOffset)
        let depthOffsetInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, depthOffsetInCameraCoordinates)
        openGLView.modelTranslationToCentreOfRotation = GLKMatrix4TranslateWithVector3(openGLView.modelTranslationToCentreOfRotation, depthOffsetInObjectCoordinates)
        openGLView.model = GLKMatrix4Multiply(GLKMatrix4Multiply(openGLView.modelShiftBack, openGLView.modelRotation), openGLView.modelTranslationToCentreOfRotation)
        
        // Put model matrix in arrays and render
        openGLView.mArray = [openGLView.model.m00, openGLView.model.m01, openGLView.model.m02, openGLView.model.m03,
                             openGLView.model.m10, openGLView.model.m11, openGLView.model.m12, openGLView.model.m13,
                             openGLView.model.m20, openGLView.model.m21, openGLView.model.m22, openGLView.model.m23,
                             openGLView.model.m30, openGLView.model.m31, openGLView.model.m32, openGLView.model.m33]
        let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(openGLView.model), &isInvertible))
        openGLView.mitArray = [mit.m00, mit.m01, mit.m02,
                               mit.m10, mit.m11, mit.m12,
                               mit.m20, mit.m21, mit.m22]
        openGLView.renderFrame()
      }
      
      cityGMLParser!.advanceIterator()
    }
  }
  
  func findObjectRow(with id: String) -> Int {
    for row in 0..<outlineView.numberOfRows {
      let object = outlineView.item(atRow: row) as! OutlineViewObject
      if object.id == id {
        return row
      }
    }
    return -1
  }
}

