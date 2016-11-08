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

@NSApplicationMain
class Controller: NSObject, NSApplicationDelegate {
  
  @IBOutlet weak var window: NSWindow!
  @IBOutlet weak var splitView: NSSplitView!
  @IBOutlet weak var outlineView: NSOutlineView!
  @IBOutlet weak var metalView: MetalView!
  @IBOutlet weak var progressIndicator: NSProgressIndicator!
  
  @IBOutlet weak var toggleViewEdgesMenuItem: NSMenuItem!
  @IBOutlet weak var toggleViewBoundingBoxMenuItem: NSMenuItem!
  @IBOutlet weak var goHomeMenuItem: NSMenuItem!
  @IBOutlet weak var toggleSideBarMenuItem: NSMenuItem!
  
  let dataStorage = DataStorage()
  
  func applicationDidFinishLaunching(_ aNotification: Notification) {
    Swift.print("AppDelegate.applicationDidFinishLaunching(Notification)")
    
    dataStorage.controller = self
    dataStorage.metalView = metalView
    metalView.controller = self
    metalView.dataStorage = dataStorage
    outlineView.delegate = dataStorage
    outlineView.dataSource = dataStorage
    outlineView.doubleAction = #selector(outlineViewDoubleClick)
    toggleSideBar(toggleSideBarMenuItem)
  }
  
  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    Swift.print("AppDelegate.application(NSApplication, openFile: String)")
    Swift.print("Open \(filename)")
    let url = URL(fileURLWithPath: filename)
    self.dataStorage.loadData(from: [url])
    return true
  }
  
  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    Swift.print("AppDelegate.application(NSApplication, openFiles: String)")
    Swift.print("Open \(filenames)")
    var urls = [URL]()
    for filename in filenames {
      urls.append(URL(fileURLWithPath: filename))
      
    }
    self.dataStorage.loadData(from: urls)
  }
  
  func outlineViewDoubleClick(_ sender: Any?) {
    dataStorage.outlineViewDoubleClick(sender)
  }
  
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
  
  @IBAction func new(_ sender: NSMenuItem) {
    Swift.print("Controller.new(NSMenuItem)")
    
    dataStorage.openFiles = Set<URL>()
    self.window.representedURL = nil
    self.window.title = "Azul"
    
    dataStorage.objects.removeAll()
    self.outlineView.reloadData()
    
    metalView.buildingsBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.buildingRoofsBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.roadsBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.terrainBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.waterBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.plantCoverBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.genericBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.bridgesBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.landUseBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.edgesBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.boundingBoxBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.selectedFacesBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    metalView.selectedEdgesBuffer = metalView.device!.makeBuffer(length: 0, options: [])
    
    metalView.fieldOfView = 3.141519/4.0
    
    metalView.modelTranslationToCentreOfRotationMatrix = matrix_identity_float4x4
    metalView.modelRotationMatrix = matrix_identity_float4x4
    metalView.modelShiftBackMatrix = matrix4x4_translation(shift: metalView.centre)
    metalView.modelMatrix = matrix_multiply(matrix_multiply(metalView.modelShiftBackMatrix, metalView.modelRotationMatrix), metalView.modelTranslationToCentreOfRotationMatrix)
    metalView.viewMatrix = matrix4x4_look_at(eye: metalView.eye, centre: metalView.centre, up: float3(0.0, 1.0, 0.0))
    metalView.projectionMatrix = matrix4x4_perspective(fieldOfView: metalView.fieldOfView, aspectRatio: Float(metalView.bounds.size.width / metalView.bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    metalView.constants.modelMatrix = metalView.modelMatrix
    metalView.constants.modelViewProjectionMatrix = matrix_multiply(metalView.projectionMatrix, matrix_multiply(metalView.viewMatrix, metalView.modelMatrix))
    metalView.constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: metalView.modelMatrix)))
    metalView.constants.viewMatrixInverse = matrix_invert(metalView.viewMatrix)
    
    dataStorage.pushData()
    metalView.needsDisplay = true
  }
  
  @IBAction func openFile(_ sender: NSMenuItem) {
    Swift.print("AppDelegate.openFile(NSMenuItem)")
    
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = true
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
    openPanel.allowedFileTypes = ["gml", "xml"]
    openPanel.begin(completionHandler:{(result: Int) in
      if result == NSFileHandlingPanelOKButton {
        self.dataStorage.loadData(from: openPanel.urls)
      }
    })
  }
  
  @IBAction func toggleViewEdges(_ sender: NSMenuItem) {
    if metalView.viewEdges {
      metalView.viewEdges = false
      sender.state = 0
      metalView.needsDisplay = true
    } else {
      metalView.viewEdges = true
      sender.state = 1
      metalView.needsDisplay = true
    }
  }
  
  @IBAction func toggleViewBoundingBox(_ sender: NSMenuItem) {
    if metalView.viewBoundingBox {
      metalView.viewBoundingBox = false
      sender.state = 0
      metalView.needsDisplay = true
    } else {
      metalView.viewBoundingBox = true
      sender.state = 1
      metalView.needsDisplay = true
    }
  }
  
  @IBAction func goHome(_ sender: NSMenuItem) {
    metalView.fieldOfView = 3.141519/4.0
    
    metalView.modelTranslationToCentreOfRotationMatrix = matrix_identity_float4x4
    metalView.modelRotationMatrix = matrix_identity_float4x4
    metalView.modelShiftBackMatrix = matrix4x4_translation(shift: metalView.centre)
    metalView.modelMatrix = matrix_multiply(matrix_multiply(metalView.modelShiftBackMatrix, metalView.modelRotationMatrix), metalView.modelTranslationToCentreOfRotationMatrix)
    metalView.viewMatrix = matrix4x4_look_at(eye: metalView.eye, centre: metalView.centre, up: float3(0.0, 1.0, 0.0))
    metalView.projectionMatrix = matrix4x4_perspective(fieldOfView: metalView.fieldOfView, aspectRatio: Float(metalView.bounds.size.width / metalView.bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    metalView.constants.modelMatrix = metalView.modelMatrix
    metalView.constants.modelViewProjectionMatrix = matrix_multiply(metalView.projectionMatrix, matrix_multiply(metalView.viewMatrix, metalView.modelMatrix))
    metalView.constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: metalView.modelMatrix)))
    metalView.constants.viewMatrixInverse = matrix_invert(metalView.viewMatrix)
    metalView.needsDisplay = true
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
  
  func applicationWillTerminate(_ aNotification: Notification) {
    Swift.print("AppDelegate.applicationWillTerminate()")
  }
  
}
