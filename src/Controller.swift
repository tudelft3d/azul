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
import Metal
import MetalKit

struct ViewParameters: Codable {
  var eye: [Float]
  var centre: [Float]
  var fieldOfView: Float
  var scaling: [Float]
  var rotation: [Float]
  var translation: [Float]
  var modelMatrix: [Float]
  var viewMatrix: [Float]
  var projectionMatrix: [Float]
  var viewEdges: Bool
  var viewBoundingBox: Bool
}

class SplitViewController: NSObject, NSSplitViewDelegate {
  func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
    let dividerThickness = splitView.dividerThickness
    var leftRect = splitView.subviews[0].frame
    var rightRect = splitView.subviews[1].frame
    let newFrame = splitView.frame
    
    leftRect.size.height = newFrame.height
    leftRect.origin = .zero
    rightRect.size.width = newFrame.width - leftRect.width - dividerThickness
    rightRect.size.height = newFrame.height
    rightRect.origin.x = leftRect.width + dividerThickness
    
    splitView.subviews[0].frame = leftRect
    splitView.subviews[1].frame = rightRect
  }
}

class LeftSplitViewController: NSObject, NSSplitViewDelegate {
  func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
    if dividerIndex == 0 {
      return .zero
    } else {
      let effectiveRect = NSRect(x: 0, y: splitView.subviews[0].bounds.height+splitView.subviews[1].bounds.height-5, width: splitView.bounds.width, height: 10)
      return effectiveRect
    }
  }
  
  func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
    let dividerThickness = splitView.dividerThickness
    var searchRect = splitView.subviews[0].frame
    var objectsRect = splitView.subviews[1].frame
    var attributesRect = splitView.subviews[2].frame
    let newFrame = splitView.frame

    searchRect.size.width = newFrame.width
    searchRect.origin = .zero
    
    objectsRect.size.width = newFrame.width
    objectsRect.size.height = newFrame.height - searchRect.height - dividerThickness - attributesRect.size.height - dividerThickness
    objectsRect.origin.y = searchRect.height + dividerThickness
    
    attributesRect.size.width = newFrame.width
    attributesRect.origin.y = searchRect.height + dividerThickness + objectsRect.height + dividerThickness

    splitView.subviews[0].frame = searchRect
    splitView.subviews[1].frame = objectsRect
    splitView.subviews[2].frame = attributesRect
  }
}

class SearchFieldDelegate: NSObject, NSSearchFieldDelegate {
  var controller: Controller?
  override func controlTextDidChange(_ obj: Notification) {
    let searchField = obj.object as! NSSearchField
    searchField.stringValue.withCString { pointer in
      controller!.dataManager.setSearchString(pointer)
    }
    controller!.objectsSourceList!.reloadData()
  }
}

@NSApplicationMain
@objc class Controller: NSObject, NSApplicationDelegate {

  @IBOutlet weak var window: NSWindow!
  var splitView: NSSplitView?
  var leftSplitView: NSSplitView?
  @objc var searchField: NSSearchField?
  var objectsScrollView: NSScrollView?
  var objectsClipView: NSClipView?
  @objc var objectsSourceList: NSOutlineView?
  var objectsSourceListColumn: NSTableColumn?
  var attributesScrollView: NSScrollView?
  var attributesClipView: NSClipView?
  @objc var attributesTableView: NSTableView?
  var attributeNamesColumn: NSTableColumn?
  var attributeValuesColumn: NSTableColumn?
  var totalProgress: Double = 0.0
  var progressIndicator: NSProgressIndicator?
  var statusTextField: NSTextField?
  
  @objc var metalView: MetalView?
    var openFiles : Set<URL> = []

  
  @IBOutlet weak var toggleViewEdgesMenuItem: NSMenuItem!
  @IBOutlet weak var toggleViewBoundingBoxMenuItem: NSMenuItem!
  @IBOutlet weak var goHomeMenuItem: NSMenuItem!
  @IBOutlet weak var toggleSideBarMenuItem: NSMenuItem!
  @IBOutlet weak var openFileMenuItem: NSMenuItem!
  @IBOutlet weak var newFileMenuItem: NSMenuItem!
  @IBOutlet weak var copyObjectIdMenuItem: NSMenuItem!
  @IBOutlet weak var findMenuItem: NSMenuItem!
  @IBOutlet weak var loadViewParametersMenuItem: NSMenuItem!
  @IBOutlet weak var saveViewParametersMenuItem: NSMenuItem!
  @IBOutlet weak var toggleFullScreenMenuItem: NSMenuItem!
  
  let dataManager = DataManager()!
  let performanceHelper = PerformanceHelperWrapperWrapper()!
  let splitViewController = SplitViewController()
  let leftSplitViewController = LeftSplitViewController()
  let searchFieldDelegate = SearchFieldDelegate()

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    Swift.print("Controller.applicationDidFinishLaunching(Notification)")
    
    splitView = NSSplitView(frame: window.contentView!.bounds)
    splitView!.autoresizingMask = [.width, .height]
    splitView!.dividerStyle = .paneSplitter
    splitView!.isVertical = true
    splitView!.addSubview(NSView())
    splitView!.addSubview(NSView())
    splitView!.adjustSubviews()
    splitView!.setPosition(200, ofDividerAt: 0)
    splitView!.delegate = splitViewController
    
    leftSplitView = NSSplitView(frame: splitView!.subviews[0].bounds)
    leftSplitView!.dividerStyle = .thin
    leftSplitView!.addSubview(NSView())
    leftSplitView!.addSubview(NSView())
    leftSplitView!.addSubview(NSView())
    splitView!.subviews[0] = leftSplitView!
    leftSplitView!.adjustSubviews()
    leftSplitView!.setPosition(20, ofDividerAt: 0)
    leftSplitView!.setPosition(450, ofDividerAt: 1)
    leftSplitView!.delegate = leftSplitViewController
    
    searchField = NSSearchField(frame: leftSplitView!.subviews[0].bounds)
    searchField!.delegate = searchFieldDelegate
    searchFieldDelegate.controller = self
    leftSplitView!.subviews[0] = searchField!
    
    objectsScrollView = NSScrollView(frame: leftSplitView!.subviews[1].bounds)
    objectsScrollView!.hasVerticalScroller = true
    objectsScrollView!.hasHorizontalScroller = true
    objectsScrollView!.wantsLayer = true
    objectsScrollView!.identifier = .init(rawValue: "ObjectsScrollView")
    leftSplitView!.subviews[1] = objectsScrollView!
    
    objectsClipView = NSClipView(frame: leftSplitView!.subviews[1].bounds)
    objectsScrollView!.contentView = objectsClipView!
    
    objectsSourceList = NSOutlineView(frame: objectsScrollView!.bounds)
    objectsSourceList!.selectionHighlightStyle = .sourceList
    objectsSourceList!.floatsGroupRows = false
    objectsSourceList!.indentationPerLevel = 16
    objectsSourceList!.indentationMarkerFollowsCell = false
    objectsSourceList!.wantsLayer = true
    objectsSourceList!.layer!.backgroundColor = NSColor.secondarySelectedControlColor.cgColor
    objectsSourceList!.headerView = nil
    objectsSourceList!.allowsMultipleSelection = true
    objectsClipView!.documentView = objectsSourceList!
    
    objectsSourceListColumn = NSTableColumn(identifier: .init("Objects"))
    objectsSourceListColumn!.isEditable = false
    objectsSourceListColumn!.minWidth = 200
    objectsSourceListColumn!.headerCell.stringValue = "Object"
    objectsSourceList!.addTableColumn(objectsSourceListColumn!)
    objectsSourceList!.outlineTableColumn = objectsSourceListColumn
    
    attributesScrollView = NSScrollView(frame: leftSplitView!.subviews[2].bounds)
    attributesScrollView!.hasVerticalScroller = true
    attributesScrollView!.hasHorizontalScroller = true
    attributesScrollView!.wantsLayer = true
    attributesScrollView!.identifier = .init(rawValue: "AttributesScrollView")
    leftSplitView!.subviews[2] = attributesScrollView!
    
    attributesClipView = NSClipView(frame: leftSplitView!.subviews[2].bounds)
    attributesScrollView!.contentView = attributesClipView!
    
    attributesTableView = NSTableView(frame: attributesScrollView!.bounds)
    attributesClipView!.documentView = attributesTableView!
    
    attributeNamesColumn = NSTableColumn(identifier: .init("A"))
    attributeNamesColumn!.title = "Attribute"
    attributeValuesColumn = NSTableColumn(identifier: .init("V"))
    attributeValuesColumn!.title = "Value"
    attributesTableView!.addTableColumn(attributeNamesColumn!)
    attributesTableView!.addTableColumn(attributeValuesColumn!)
    
    let defaultDevice = MTLCreateSystemDefaultDevice()
    metalView = MetalView(frame: splitView!.subviews[1].frame, device: defaultDevice)
    metalView!.controller = self
    metalView!.dataManager = dataManager
    splitView!.subviews[1] = metalView!
    
    progressIndicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: metalView!.frame.width/4, height: 12))
    progressIndicator!.isIndeterminate = false
    metalView!.addSubview(progressIndicator!)
    progressIndicator!.isHidden = true
    statusTextField = NSTextField(frame: NSRect(x: metalView!.frame.width/4, y: 0, width: 3*metalView!.frame.width/4, height: 16))
    statusTextField!.stringValue = "Ready"
    statusTextField!.isBordered = false
    metalView!.addSubview(statusTextField!)
    statusTextField!.isHidden = true
    
    dataManager.controller = self
    
    window.contentView!.addSubview(splitView!)
    window.makeFirstResponder(metalView)
    window.minSize = NSSize(width: 400, height: 300)
    
    objectsSourceList!.dataSource = dataManager
    objectsSourceList!.delegate = dataManager
    objectsSourceList!.doubleAction = #selector(sourceListDoubleClick)
    attributesTableView!.dataSource = dataManager
  }
  
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
  
  @IBAction func new(_ sender: NSMenuItem) {
    Swift.print("Controller.new(NSMenuItem)")
    dataManager.clear()
    regenerateBoundingBoxBuffer()
    metalView!.new()
    objectsSourceList!.reloadData()
    attributesTableView!.reloadData()
    openFiles = []
    self.window.representedURL = nil
    self.window.title = "azul"
  }
  
  @IBAction func openFile(_ sender: NSMenuItem) {
    Swift.print("Controller.openFile(NSMenuItem)")
    
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = true
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
    openPanel.allowedFileTypes = ["gml", "xml", "json", "obj", "off", "poly"]
    
    openPanel.beginSheetModal(for: window) { (result: NSApplication.ModalResponse) in
      if result == .OK {
        self.loadData(from: openPanel.urls)
      }
    }
  }
  
  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    Swift.print("Controller.application(NSApplication, openFile: String)")
    Swift.print("Open \(filename)")
    let url = URL(fileURLWithPath: filename)
    loadData(from: [url])
    return true
  }
  
  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    Swift.print("Controller.application(NSApplication, openFiles: String)")
    Swift.print("Open \(filenames)")
    var urls = [URL]()
    for filename in filenames {
      urls.append(URL(fileURLWithPath: filename))
    }
    loadData(from: urls)
  }
  
  @IBAction func toggleViewEdges(_ sender: NSMenuItem) {
    if metalView!.viewEdges {
      metalView!.viewEdges = false
      sender.state = .off
    } else {
      metalView!.viewEdges = true
      sender.state = .on
    }
    metalView!.needsDisplay = true
  }
  
  @IBAction func toggleViewBoundingBox(_ sender: NSMenuItem) {
    if metalView!.viewBoundingBox {
      metalView!.viewBoundingBox = false
      sender.state = .off
    } else {
      metalView!.viewBoundingBox = true
      sender.state = .on
    }
    metalView!.needsDisplay = true
  }
  
  @IBAction func goHome(_ sender: NSMenuItem) {
    metalView!.goHome()
  }
  
  @IBAction func toggleSideBar(_ sender: NSMenuItem) {
    if splitView!.subviews[0].bounds.width == 0 {
      //      Swift.print("Open sidebar")
      NSAnimationContext.runAnimationGroup({ (context) -> Void in
        context.allowsImplicitAnimation = true
        splitView!.setPosition(200, ofDividerAt: 0)
      }, completionHandler: nil)
      sender.title = "Hide Sidebar"
    } else {
      //      Swift.print("Close sidebar")
      NSAnimationContext.runAnimationGroup({ (context) -> Void in
        context.allowsImplicitAnimation = true
        splitView!.setPosition(0, ofDividerAt: 0)
      }, completionHandler: nil)
      sender.title = "Show Sidebar"
    }
  }
  
  @IBAction func focusOnSearchBar(_ sender: NSMenuItem) {
    if splitView!.subviews[0].bounds.size.width == 0 {
      toggleSideBar(sender)
    }
    window.makeFirstResponder(searchField!)
  }
  
  func loadData(from urls: [URL]) {
    self.performanceHelper.startTimer()
    
    let progressPerFile = 100.0/Double(urls.count)
    totalProgress = 0.0
    progressIndicator?.doubleValue = totalProgress
    progressIndicator?.isHidden = false
    statusTextField?.isHidden = false
    DispatchQueue.global().async(qos: .userInitiated) {
      for url in urls {
        
        if url.pathExtension == "azulview" {
          Swift.print("View url: \(url)")
          DispatchQueue.main.async {
            self.loadViewParameters(url: url)
            self.totalProgress += progressPerFile
            self.progressIndicator?.doubleValue = self.totalProgress
            if urls.last == url {
              self.progressIndicator!.isHidden = true
              self.statusTextField!.isHidden = true
            }
          }
          continue
        }
        
        if self.openFiles.contains(url) {
          Swift.print("\(url) already open")
          DispatchQueue.main.async {
            self.totalProgress += progressPerFile
            self.progressIndicator?.doubleValue = self.totalProgress
            if urls.last == url {
              self.progressIndicator!.isHidden = true
              self.statusTextField!.isHidden = true
            }
          }
          continue
        }
        
        Swift.print("Loading \(url.path) ...")
        DispatchQueue.main.async {
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
          self.statusTextField?.stringValue = "Loading \(url.path) ..."
        }
        url.path.utf8CString.withUnsafeBufferPointer { pointer in
          self.dataManager.parse(pointer.baseAddress)
        }
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*20.071734/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }
        
        Swift.print("Clearing helpers...")
        self.dataManager.clearHelpers()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*0.51605/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }

        Swift.print("Updating bounds...")
        self.dataManager.updateBoundsWithLastFile()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*0.158675/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }

        Swift.print("Triangulating...")
        self.dataManager.triangulateLastFile()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*45.400172/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }

        Swift.print("Generating edges...")
        self.dataManager.generateEdgesForLastFile()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*1.150533/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }

        Swift.print("Clearing polygons...")
        self.dataManager.clearPolygonsOfLastFile()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*0.359982/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }

        Swift.print("Making triangle buffers...")
        self.dataManager.regenerateTriangleBuffers(withMaximumSize: 16*1024*1024)
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*3.535023/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }

        Swift.print("Making edge buffers...")
        self.dataManager.regenerateEdgeBuffers(withMaximumSize: 16*1024*1024)
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*2.085606/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }

        Swift.print("Loading triangle buffers...")
        while self.metalView == nil {
          Thread.sleep(forTimeInterval: 0.01)
        }
        self.reloadTriangleBuffers()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*1.31523/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }

        Swift.print("Loading edge buffers...")
        self.reloadEdgeBuffers()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*0.572072/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }

        Swift.print("Regenerating bounding box buffer...")
        self.regenerateBoundingBoxBuffer()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*0.000162/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusTextField?.isHidden = false
          self.progressIndicator?.isHidden = false
        }

        self.openFiles.insert(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)

        DispatchQueue.main.async {
          self.metalView!.needsDisplay = true
          self.objectsSourceList!.reloadData()
          switch self.openFiles.count {
          case 0:
            self.window.representedURL = nil
            self.window.title = "azul"
          case 1:
            self.window.representedURL = self.openFiles.first!
            self.window.title = self.openFiles.first!.lastPathComponent
          default:
            self.window.representedURL = nil
            self.window.title = "azul (\(self.openFiles.count) open files)"
          }
          if urls.last == url {
            self.progressIndicator!.isHidden = true
            self.statusTextField!.isHidden = true
          }
        }
      }
    }
  }

  func regenerateBoundingBoxBuffer() {
    
    // Get bounds
    let firstMinCoordinate = dataManager.minCoordinates
    let minCoordinatesBuffer = UnsafeBufferPointer(start: firstMinCoordinate, count: 3)
    let minCoordinatesArray = ContiguousArray(minCoordinatesBuffer)
    let minCoordinates = [Float](minCoordinatesArray)
    let firstMidCoordinate = dataManager.midCoordinates
    let midCoordinatesBuffer = UnsafeBufferPointer(start: firstMidCoordinate, count: 3)
    let midCoordinatesArray = ContiguousArray(midCoordinatesBuffer)
    let midCoordinates = [Float](midCoordinatesArray)
    let firstMaxCoordinate = dataManager.maxCoordinates
    let maxCoordinatesBuffer = UnsafeBufferPointer(start: firstMaxCoordinate, count: 3)
    let maxCoordinatesArray = ContiguousArray(maxCoordinatesBuffer)
    let maxCoordinates = [Float](maxCoordinatesArray)
    let maxRange = dataManager.maxRange

    // Create bounding box vertices
    let boundingBoxVertices: [Vertex] = [Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),  // 000 -> 001
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),  // 000 -> 010
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),  // 000 -> 100
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),  // 001 -> 011
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),  // 001 -> 101
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),  // 010 -> 011
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),  // 010 -> 110
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(minCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),  // 011 -> 111
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),  // 100 -> 101
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),  // 100 -> 110
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 minCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),  // 101 -> 111
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange),
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 minCoordinates[2]-midCoordinates[2])/maxRange),  // 110 -> 111
                                         Vertex(position: float3(maxCoordinates[0]-midCoordinates[0],
                                                                 maxCoordinates[1]-midCoordinates[1],
                                                                 maxCoordinates[2]-midCoordinates[2])/maxRange)]
    metalView!.boundingBoxBuffer = metalView!.device!.makeBuffer(bytes: boundingBoxVertices, length: MemoryLayout<Vertex>.size*boundingBoxVertices.count, options: [])
  }

  @objc func reloadTriangleBuffers() {
    self.metalView!.triangleBuffers.removeAll()
    self.dataManager.initialiseTriangleBufferIterator()
    while !self.dataManager.triangleBufferIteratorEnded() {
      var bufferTypeLength: Int = 0
      let firstCharacterOfBufferType = UnsafeRawPointer(self.dataManager.currentTriangleBufferType(withLength: &bufferTypeLength))
      let bufferTypeData = Data(bytes: firstCharacterOfBufferType!, count: bufferTypeLength*MemoryLayout<Int8>.size)
      let bufferType = String(data: bufferTypeData, encoding: .utf8)!
      
      let firstBufferColourComponent = self.dataManager.currentTriangleBufferColour()
      let bufferColourBuffer = UnsafeBufferPointer(start: firstBufferColourComponent, count: 4)
      var bufferColourArray = ContiguousArray(bufferColourBuffer)
      let bufferColour = float4(bufferColourArray[0], bufferColourArray[1], bufferColourArray[2], bufferColourArray[3])
      
      var bufferSize: Int = 0
      let buffer = self.dataManager.currentTriangleBuffer(withSize: &bufferSize)
      if buffer != nil {
        self.metalView!.triangleBuffers.append(BufferWithColour(buffer: self.metalView!.device!.makeBuffer(bytes: buffer!, length: bufferSize, options: [])!, type: bufferType, colour: bufferColour))
      }
      self.dataManager.advanceTriangleBufferIterator()
    }
  }

  @objc func reloadEdgeBuffers() {
    self.metalView!.edgeBuffers.removeAll()
    self.dataManager.initialiseEdgeBufferIterator()
    while !self.dataManager.edgeBufferIteratorEnded() {
      let firstBufferColourComponent = self.dataManager.currentEdgeBufferColour()
      let bufferColourBuffer = UnsafeBufferPointer(start: firstBufferColourComponent, count: 4)
      var bufferColourArray = ContiguousArray(bufferColourBuffer)
      let bufferColour = float4(bufferColourArray[0], bufferColourArray[1], bufferColourArray[2], bufferColourArray[3])
      
      var bufferSize: Int = 0
      let buffer = self.dataManager.currentEdgeBuffer(withSize: &bufferSize)
      if buffer != nil {
        self.metalView!.edgeBuffers.append(BufferWithColour(buffer: self.metalView!.device!.makeBuffer(bytes: buffer!, length: bufferSize, options: [])!, type: "", colour: bufferColour))
      }
      self.dataManager.advanceEdgeBufferIterator()
    }
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    Swift.print("Controller.applicationWillTerminate(Notification)")
  }
  
  @objc func sourceListDoubleClick(_ sender: Any?) {
    dataManager.sourceListDoubleClick()
    
    // Put model matrix in arrays and render
    metalView!.constants.modelMatrix = metalView!.modelMatrix
    metalView!.constants.modelViewProjectionMatrix = (metalView!.projectionMatrix * (metalView!.viewMatrix * metalView!.modelMatrix))
    metalView!.constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: metalView!.modelMatrix).inverse.transpose
    metalView!.needsDisplay = true
  }
  
  @IBAction func copyObjectId(_ sender: NSMenuItem) {
    let pasteboard : NSPasteboard = .general
    pasteboard.clearContents()
    pasteboard.declareTypes([.string], owner: self)
    var selectionString = String()
    for row in objectsSourceList!.selectedRowIndexes {
      if let view = objectsSourceList!.view(atColumn: 0, row: row, makeIfNecessary: false)! as? TableCellView {
        Swift.print("\(view.textField!.stringValue)")
        if !selectionString.isEmpty {
          selectionString.append("\n")
        }
        selectionString.append(view.textField!.stringValue)
      }
    }
    pasteboard.setString(selectionString, forType: .string)
  }
  
  func loadViewParameters(url: URL) {
    do {
      let jsonDecoder = JSONDecoder()
      let jsonData = try Data(contentsOf: url)
      let viewParameters = try jsonDecoder.decode(ViewParameters.self, from: jsonData)
      self.metalView!.eye = deserialiseToFloat3(vector: viewParameters.eye)
      self.metalView!.centre = deserialiseToFloat3(vector: viewParameters.centre)
      self.metalView!.fieldOfView = viewParameters.fieldOfView
      self.metalView!.scaling = .init(array: viewParameters.scaling)
      self.metalView!.rotation = .init(array: viewParameters.rotation)
      self.metalView!.translation = .init(array: viewParameters.translation)
      self.metalView!.modelMatrix = .init(array: viewParameters.modelMatrix)
      self.metalView!.viewMatrix = .init(array: viewParameters.viewMatrix)
      self.metalView!.projectionMatrix = .init(array: viewParameters.projectionMatrix)
      self.metalView!.viewEdges = viewParameters.viewEdges
      self.metalView!.viewBoundingBox = viewParameters.viewBoundingBox
      
      self.metalView!.constants.modelMatrix = self.metalView!.modelMatrix
      self.metalView!.constants.modelViewProjectionMatrix = (self.metalView!.projectionMatrix * (self.metalView!.viewMatrix * self.metalView!.modelMatrix))
      self.metalView!.constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: self.metalView!.modelMatrix).inverse.transpose
      self.metalView!.needsDisplay = true
    } catch {
      Swift.print("Couldn't load view parameters...")
    }
  }
  
  @IBAction func loadViewParameters(_ sender: NSMenuItem) {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
    openPanel.allowedFileTypes = ["azulview"]
    openPanel.beginSheetModal(for: window) { (result: NSApplication.ModalResponse) in
      if result == .OK {
        self.loadViewParameters(url: openPanel.url!)
      }
    }
  }
  
  @IBAction func saveViewParameters(_ sender: NSMenuItem) {
    let jsonEncoder = JSONEncoder()
    let viewParameters = ViewParameters(eye: serialise(vector: metalView!.eye),
                                        centre: serialise(vector: metalView!.centre),
                                        fieldOfView: metalView!.fieldOfView,
                                        scaling: serialise(matrix: metalView!.scaling),
                                        rotation: serialise(matrix: metalView!.rotation),
                                        translation: serialise(matrix: metalView!.translation),
                                        modelMatrix: serialise(matrix: metalView!.modelMatrix),
                                        viewMatrix: serialise(matrix: metalView!.viewMatrix),
                                        projectionMatrix: serialise(matrix: metalView!.projectionMatrix),
                                        viewEdges: metalView!.viewEdges,
                                        viewBoundingBox: metalView!.viewBoundingBox)
    do {
      let jsonData = try jsonEncoder.encode(viewParameters)
      let savePanel = NSSavePanel()
      savePanel.allowedFileTypes = ["azulview"]
      savePanel.beginSheetModal(for: window, completionHandler: { (result: NSApplication.ModalResponse) in
        if result == .OK {
          do {
            try jsonData.write(to: savePanel.url!, options: [])
          } catch {
            Swift.print("Couldn't write file...")
          }
        }
      })
    } catch {
      Swift.print("Couldn't encode...")
    }
  }
}
