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

struct Constants {
  var modelMatrix = matrix_identity_float4x4
  var modelViewProjectionMatrix = matrix_identity_float4x4
  var modelMatrixInverseTransposed = matrix_identity_float3x3
  var viewMatrixInverse = matrix_identity_float4x4
  var colour = float4(0.0, 0.0, 0.0, 1.0)
}

struct Vertex {
  var position: float3
  var normal: float3
}

class MetalView: MTKView {
  
  var controller: Controller?
  var dataStorage: DataStorage?
  
  var commandQueue: MTLCommandQueue?
  var renderPipelineState: MTLRenderPipelineState?
  var depthStencilState: MTLDepthStencilState?
  
  var renderedTypes = [String: [String: float4]]()

  var faceBuffers = [String: [String: MTLBuffer]]()
  var edgesBuffer: MTLBuffer?
  var boundingBoxBuffer: MTLBuffer?
  var selectedFacesBuffer: MTLBuffer?
  var selectedEdgesBuffer: MTLBuffer?
  
  var viewEdges: Bool = false
  var viewBoundingBox: Bool = false
  
  var multipleSelection: Bool = false
  
  var constants = Constants()

  var eye = float3(0.0, 0.0, 0.0)
  var centre = float3(0.0, 0.0, -1.0)
  var fieldOfView: Float = 3.141519/4.0
  
  var modelTranslationToCentreOfRotationMatrix = matrix_identity_float4x4
  var modelRotationMatrix = matrix_identity_float4x4
  var modelShiftBackMatrix = matrix_identity_float4x4
  
  var modelMatrix = matrix_identity_float4x4
  var viewMatrix = matrix_identity_float4x4
  var projectionMatrix = matrix_identity_float4x4
  
  override init(frame frameRect: CGRect, device: MTLDevice?) {
//    Swift.print("MetalView.init(CGRect, MTLDevice?)")
    
    super.init(frame: frameRect, device: device)
    
    // View
    clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1)
    colorPixelFormat = .bgra8Unorm
    depthStencilPixelFormat = .depth32Float
    
    // Command queue
    commandQueue = device!.makeCommandQueue()
    
    // Render pipeline
    let library = device!.newDefaultLibrary()!
    let vertexFunction = library.makeFunction(name: "vertexTransform")
    let fragmentFunction = library.makeFunction(name: "fragmentLit")
    let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
    renderPipelineDescriptor.vertexFunction = vertexFunction
    renderPipelineDescriptor.fragmentFunction = fragmentFunction
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
    renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
    renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    renderPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    renderPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    renderPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    do {
      renderPipelineState = try device!.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
    } catch {
      Swift.print("Unable to compile render pipeline state")
      return
    }
    
    // Depth stencil
    let depthSencilDescriptor = MTLDepthStencilDescriptor()
    depthSencilDescriptor.depthCompareFunction = .less
    depthSencilDescriptor.isDepthWriteEnabled = true
    depthStencilState = device!.makeDepthStencilState(descriptor: depthSencilDescriptor)
    
    // Matrices
    modelShiftBackMatrix = matrix4x4_translation(shift: centre)
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: float3(0.0, 1.0, 0.0))
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: modelMatrix)))
    constants.viewMatrixInverse = matrix_invert(viewMatrix)
    
    // Rendered types
    renderedTypes["Bridge"] = [String: float4]()
    renderedTypes["Bridge"]![""] = float4(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0)
    renderedTypes["Building"] = [String: float4]()
    renderedTypes["Building"]![""] = float4(1.0, 0.956862745098039, 0.690196078431373, 1.0)
    renderedTypes["Building"]!["Door"] = float4(0.482352941176471, 0.376470588235294, 0.231372549019608, 1.0)
    renderedTypes["Building"]!["GroundSurface"] = float4(0.7, 0.7, 0.7, 1.0)
    renderedTypes["Building"]!["RoofSurface"] = float4(0.882352941176471, 0.254901960784314, 0.219607843137255, 1.0)
    renderedTypes["Building"]!["Window"] = float4(0.584313725490196, 0.917647058823529, 1.0, 0.3)
    renderedTypes["CityFurniture"] = [String: float4]()
    renderedTypes["CityFurniture"]![""] = float4(0.7, 0.7, 0.7, 1.0)
    renderedTypes["GenericCityObject"] = [String: float4]()
    renderedTypes["GenericCityObject"]![""] = float4(0.7, 0.7, 0.7, 1.0)
    renderedTypes["LandUse"] = [String: float4]()
    renderedTypes["LandUse"]![""] = float4(0.3, 0.3, 0.3, 1.0)
    renderedTypes["PlantCover"] = [String: float4]()
    renderedTypes["PlantCover"]![""] = float4(0.4, 0.882352941176471, 0.333333333333333, 1.0)
    renderedTypes["Railway"] = [String: float4]()
    renderedTypes["Railway"]![""] = float4(0.7, 0.7, 0.7, 1.0)
    renderedTypes["ReliefFeature"] = [String: float4]()
    renderedTypes["ReliefFeature"]![""] = float4(0.713725490196078, 0.882352941176471, 0.623529411764706, 1.0)
    renderedTypes["Road"] = [String: float4]()
    renderedTypes["Road"]![""] = float4(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0)
    renderedTypes["SolitaryVegetationObject"] = [String: float4]()
    renderedTypes["SolitaryVegetationObject"]![""] = float4(0.4, 0.882352941176471, 0.333333333333333, 1.0)
    renderedTypes["Tunnel"] = [String: float4]()
    renderedTypes["Tunnel"]![""] = float4(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0)
    renderedTypes["Tunnel"]!["GroundSurface"] = float4(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0)
    renderedTypes["Tunnel"]!["RoofSurface"] = float4(0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0)
    renderedTypes["WaterBody"] = [String: float4]()
    renderedTypes["WaterBody"]![""] = float4(0.584313725490196, 0.917647058823529, 1.0, 1.0)
    
    // Allow dragging
    register(forDraggedTypes: [NSFilenamesPboardType])
    
    self.isPaused = true
    self.enableSetNeedsDisplay = true
  }
  
  required init(coder: NSCoder) {
    Swift.print("init(NSCoder)")
    super.init(coder: coder)
  }
  
  override var acceptsFirstResponder: Bool {
    return true
  }
  
  func new() {
    for faceBufferType in faceBuffers {
      for faceBufferSubtype in faceBufferType.value {
        faceBuffers[faceBufferType.key]![faceBufferSubtype.key] = device!.makeBuffer(length: 0, options: [])
      }
    }
    
    edgesBuffer = device!.makeBuffer(length: 0, options: [])
    boundingBoxBuffer = device!.makeBuffer(length: 0, options: [])
    selectedFacesBuffer = device!.makeBuffer(length: 0, options: [])
    selectedEdgesBuffer = device!.makeBuffer(length: 0, options: [])
    
    fieldOfView = 3.141519/4.0
    
    modelTranslationToCentreOfRotationMatrix = matrix_identity_float4x4
    modelRotationMatrix = matrix_identity_float4x4
    modelShiftBackMatrix = matrix4x4_translation(shift: centre)
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: float3(0.0, 1.0, 0.0))
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: modelMatrix)))
    constants.viewMatrixInverse = matrix_invert(viewMatrix)
    
    pullData()
    needsDisplay = true
  }
  
  func goHome() {
    fieldOfView = 3.141519/4.0
    
    modelTranslationToCentreOfRotationMatrix = matrix_identity_float4x4
    modelRotationMatrix = matrix_identity_float4x4
    modelShiftBackMatrix = matrix4x4_translation(shift: centre)
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: float3(0.0, 1.0, 0.0))
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: modelMatrix)))
    constants.viewMatrixInverse = matrix_invert(viewMatrix)
    needsDisplay = true
  }
  
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    //    Swift.print("Dragging entered")
    let filenames: NSArray = sender.draggingPasteboard().propertyList(forType: NSFilenamesPboardType)! as! NSArray
    //    Swift.print(filenames)
    for filename in filenames {
      let filenameString = filename as! String
      //      Swift.print(filenameString)
      if !filenameString.hasSuffix(".gml") && !filenameString.hasSuffix(".xml") {
        return NSDragOperation(rawValue: 0)
      }
    }
    
    return NSDragOperation.copy
  }
  
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    //    Swift.print("Perform drag")
    if controller != nil {
      let filenames: NSArray = sender.draggingPasteboard().propertyList(forType: NSFilenamesPboardType)! as! NSArray
      //      Swift.print(filenames)
      var urls = [URL]()
      for filename in filenames {
        let filenameString = filename as! String
        urls.append(URL(fileURLWithPath: filenameString))
      }
      dataStorage!.loadData(from: urls)
    }
    return true
  }
  
  override func mouseUp(with event: NSEvent) {
    //    Swift.print("MetalView.mouseUp()")
    
    switch event.clickCount {
    case 1:
      click(with: event)
      break
    case 2:
      doubleClick(with: event)
    default:
      break
    }
  }
  
  func click(with event: NSEvent) {
    Swift.print("MetalView.click()")
    let startTime = CACurrentMediaTime()
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    
    // Compute midCoordinates and maxRange
    let minCoordinates = float3(dataStorage!.minCoordinates)
    let maxCoordinates = float3(dataStorage!.maxCoordinates)
    let range = maxCoordinates-minCoordinates
    let midCoordinates = minCoordinates+0.5*range
    var maxRange = range.x
    if range.y > maxRange {
      maxRange = range.y
    }
    if range.z > maxRange {
      maxRange = range.z
    }
    
    // Compute the current mouse position
    let currentX: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
//    Swift.print("Current: X = \(currentX), Y = \(currentY)")
    
    // Compute two points on the ray represented by the mouse position at the near and far planes
    let mvpInverse = matrix_invert(matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix)))
    let pointOnNearPlaneInProjectionCoordinates = float4(currentX, currentY, -1.0, 1.0)
    let pointOnNearPlaneInObjectCoordinates = matrix_multiply(mvpInverse, pointOnNearPlaneInProjectionCoordinates)
    let pointOnFarPlaneInProjectionCoordinates = float4(currentX, currentY, 1.0, 1.0)
    let pointOnFarPlaneInObjectCoordinates = matrix_multiply(mvpInverse, pointOnFarPlaneInProjectionCoordinates)
    
    // Compute ray
    let rayOrigin = float3(pointOnNearPlaneInObjectCoordinates.x/pointOnNearPlaneInObjectCoordinates.w, pointOnNearPlaneInObjectCoordinates.y/pointOnNearPlaneInObjectCoordinates.w, pointOnNearPlaneInObjectCoordinates.z/pointOnNearPlaneInObjectCoordinates.w)
    let rayDestination = float3(pointOnFarPlaneInObjectCoordinates.x/pointOnFarPlaneInObjectCoordinates.w, pointOnFarPlaneInObjectCoordinates.y/pointOnFarPlaneInObjectCoordinates.w, pointOnFarPlaneInObjectCoordinates.z/pointOnFarPlaneInObjectCoordinates.w)
    let rayDirection = rayDestination - rayOrigin
    
    // Test intersections with triangles
    var closestHit: String = ""
    var hitDistance: Float = -1.0
    for object in dataStorage!.objects {
      
      let epsilon: Float = 0.000001
      let objectToCamera = matrix_multiply(viewMatrix, modelMatrix)
      
      // Moller-Trumbore algorithm for triangle-ray intersection (non-culling)
      // u,v are the barycentric coordinates of the intersection point
      // t is the distance from rayOrigin to the intersection point
      for trianglesBuffer in object.triangleBuffersByType {
        let numberOfTriangles = trianglesBuffer.value.count/18
        for triangleIndex in 0..<numberOfTriangles {
          let vertex0 = float3((trianglesBuffer.value[Int(18*triangleIndex)]-midCoordinates.x)/maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+1)]-midCoordinates.y)/maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+2)]-midCoordinates.z)/maxRange)
          let vertex1 = float3((trianglesBuffer.value[Int(18*triangleIndex+6)]-midCoordinates.x)/maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+7)]-midCoordinates.y)/maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+8)]-midCoordinates.z)/maxRange)
          let vertex2 = float3((trianglesBuffer.value[Int(18*triangleIndex+12)]-midCoordinates.x)/maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+13)]-midCoordinates.y)/maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+14)]-midCoordinates.z)/maxRange)
          let edge1 = vertex1 - vertex0
          let edge2 = vertex2 - vertex0
          let pvec = vector_cross(rayDirection, edge2)
          let determinant = vector_dot(edge1, pvec)
          if determinant > -epsilon && determinant < epsilon {
            continue // if determinant is near zero  ray lies in plane of triangle
          }
          let inverseDeterminant = 1.0 / determinant
          let tvec = rayOrigin - vertex0 // distance from vertex0 to rayOrigin
          let u = vector_dot(tvec, pvec) * inverseDeterminant
          if u < 0.0 || u > 1.0 {
            continue
          }
          let qvec = vector_cross(tvec, edge1)
          let v = vector_dot(rayDirection, qvec) * inverseDeterminant
          if v < 0.0 || u + v > 1.0 {
            continue
          }
          let t = vector_dot(edge2, qvec) * inverseDeterminant
          if t > epsilon {
            let intersectionPointInObjectCoordinates = (vertex0 * (1.0-u-v)) + (vertex1 * u) + (vertex2 * v)
            let intersectionPointInCameraCoordinates = matrix_multiply(matrix_upper_left_3x3(matrix: objectToCamera), intersectionPointInObjectCoordinates)
            let distance = intersectionPointInCameraCoordinates.z
//            Swift.print("Hit \(object.id) at distance \(distance)")
            if distance > hitDistance {
              closestHit = object.id
              hitDistance = distance
            }
          }
        }
      }
    }
    
    // (De)select closest hit
    if hitDistance > -1.0 {
      let rowToSelect = dataStorage!.findObjectRow(with: closestHit)
      if multipleSelection {
        if controller!.outlineView.selectedRowIndexes.contains(rowToSelect) {
          controller!.outlineView.deselectRow(rowToSelect)
        } else {
          let rowToSelectIndexes = IndexSet(integer: rowToSelect)
          controller!.outlineView.selectRowIndexes(rowToSelectIndexes, byExtendingSelection: true)
        }
      } else {
        let rowToSelectIndexes = IndexSet(integer: rowToSelect)
        controller!.outlineView.selectRowIndexes(rowToSelectIndexes, byExtendingSelection: false)
      }
      controller!.outlineView.scrollRowToVisible(rowToSelect)
    } else if !multipleSelection {
      controller!.outlineView.deselectAll(self)
    }
    Swift.print("Click computed in \(CACurrentMediaTime()-startTime) seconds.")
  }
  
  func doubleClick(with event: NSEvent) {
    //    Swift.print("MetalView.doubleClick()")
    //    Swift.print("Mouse location X: \(window!.mouseLocationOutsideOfEventStream.x), Y: \(window!.mouseLocationOutsideOfEventStream.y)")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    //    Swift.print("View X: \(viewFrameInWindowCoordinates.origin.x), Y: \(viewFrameInWindowCoordinates.origin.y)")
    
    // Compute the current mouse position
    let currentX: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
    //    Swift.print("currentX: \(currentX), currentY: \(currentY)")
    
    // Compute two points on the ray represented by the mouse position at the near and far planes
    let mvpInverse = matrix_invert(matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix)))
    let pointOnNearPlaneInProjectionCoordinates = float4(currentX, currentY, -1.0, 1.0)
    let pointOnNearPlaneInObjectCoordinates = matrix_multiply(mvpInverse, pointOnNearPlaneInProjectionCoordinates)
    let pointOnFarPlaneInProjectionCoordinates = float4(currentX, currentY, 1.0, 1.0)
    let pointOnFarPlaneInObjectCoordinates = matrix_multiply(mvpInverse, pointOnFarPlaneInProjectionCoordinates)
    
    // Interpolate the points to obtain the intersection with the data plane z = 0
    let alpha: Float = -(pointOnFarPlaneInObjectCoordinates.z/pointOnFarPlaneInObjectCoordinates.w)/((pointOnNearPlaneInObjectCoordinates.z/pointOnNearPlaneInObjectCoordinates.w)-(pointOnFarPlaneInObjectCoordinates.z/pointOnFarPlaneInObjectCoordinates.w))
    let clickedPointInObjectCoordinates = float4(alpha*(pointOnNearPlaneInObjectCoordinates.x/pointOnNearPlaneInObjectCoordinates.w)+(1.0-alpha)*(pointOnFarPlaneInObjectCoordinates.x/pointOnFarPlaneInObjectCoordinates.w), alpha*(pointOnNearPlaneInObjectCoordinates.y/pointOnNearPlaneInObjectCoordinates.w)+(1.0-alpha)*(pointOnFarPlaneInObjectCoordinates.y/pointOnFarPlaneInObjectCoordinates.w), 0.0, 1.0)
    
    // Use the intersection to compute the shift in the view space
    let objectToCamera = matrix_multiply(viewMatrix, modelMatrix)
    let clickedPointInCameraCoordinates = matrix_multiply(objectToCamera, clickedPointInObjectCoordinates)
    
    // Compute shift in object space
    let shiftInCameraCoordinates = float3(-clickedPointInCameraCoordinates.x, -clickedPointInCameraCoordinates.y, 0.0)
    var cameraToObject = matrix_invert(matrix_upper_left_3x3(matrix: objectToCamera))
    let shiftInObjectCoordinates = matrix_multiply(cameraToObject, shiftInCameraCoordinates)
    modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: shiftInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    
    // Correct shift so that the point of rotation remains at the same depth as the data
    cameraToObject = matrix_invert(matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)))
    let depthOffset = 1.0+depthAtCentre()
    let depthOffsetInCameraCoordinates = float3(0.0, 0.0, -depthOffset)
    let depthOffsetInObjectCoordinates = matrix_multiply(cameraToObject, depthOffsetInCameraCoordinates)
    modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: depthOffsetInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    
    // Put model matrix in arrays and render
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: modelMatrix)))
    needsDisplay = true
  }
  
  func outlineViewDoubleClick(_ sender: Any?) {
//    Swift.print("outlineViewDoubleClick()")
    
    // Compute midCoordinates and maxRange
    let minCoordinates = float3(dataStorage!.minCoordinates)
    let maxCoordinates = float3(dataStorage!.maxCoordinates)
    let range = maxCoordinates-minCoordinates
    let midCoordinates = minCoordinates+0.5*range
    var maxRange = range.x
    if range.y > maxRange {
      maxRange = range.y
    }
    if range.z > maxRange {
      maxRange = range.z
    }
    
    // Obtain object at that row
    let rowObject: CityGMLObject
    if let object = controller!.outlineView.item(atRow: controller!.outlineView!.clickedRow) as? CityGMLObject {
      rowObject = object
    } else {
      return
    }
    
    // Iterate through all parsed objects
    for parsedObject in dataStorage!.objects {
      
      // Found
      if parsedObject.id == rowObject.id {
        
        // Compute centroid
        let numberOfVertices = parsedObject.triangleBuffersByType[""]!.count/6
        var sumX: Float = 0.0
        var sumY: Float = 0.0
        var sumZ: Float = 0.0
        for vertexIndex in 0..<numberOfVertices {
          sumX = sumX + (parsedObject.triangleBuffersByType[""]![6*vertexIndex]-midCoordinates.x)/maxRange
          sumY = sumY + (parsedObject.triangleBuffersByType[""]![6*vertexIndex+1]-midCoordinates.y)/maxRange
          sumZ = sumZ + (parsedObject.triangleBuffersByType[""]![6*vertexIndex+2]-midCoordinates.z)/maxRange
        }
        let centroidInObjectCoordinates = float4(sumX/Float(numberOfVertices), sumY/Float(numberOfVertices), sumZ/Float(numberOfVertices), 1.0)
        
        // Use the centroid to compute the shift in the view space
        let objectToCamera = matrix_multiply(viewMatrix, modelMatrix)
        let centroidInCameraCoordinates = matrix_multiply(objectToCamera, centroidInObjectCoordinates)
        
        // Compute shift in object space
        let shiftInCameraCoordinates = float3(-centroidInCameraCoordinates.x, -centroidInCameraCoordinates.y, 0.0)
        var cameraToObject = matrix_invert(matrix_upper_left_3x3(matrix: objectToCamera))
        let shiftInObjectCoordinates = matrix_multiply(cameraToObject, shiftInCameraCoordinates)
        modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: shiftInObjectCoordinates))
        modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
        
        // Correct shift so that the point of rotation remains at the same depth as the data
        cameraToObject = matrix_invert(matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)))
        let depthOffset = 1.0+depthAtCentre()
        let depthOffsetInCameraCoordinates = float3(0.0, 0.0, -depthOffset)
        let depthOffsetInObjectCoordinates = matrix_multiply(cameraToObject, depthOffsetInCameraCoordinates)
        modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: depthOffsetInObjectCoordinates))
        modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
        
        // Put model matrix in arrays and render
        constants.modelMatrix = modelMatrix
        constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
        constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: modelMatrix)))
        needsDisplay = true
      }
    }
  }
  
  override func scrollWheel(with event: NSEvent) {
    //    Swift.print("MetalView.scrollWheel()")
    //    Swift.print("Scrolled X: \(event.scrollingDeltaX) Y: \(event.scrollingDeltaY)")

    // Motion according to trackpad
    let scrollingSensitivity: Float = 0.003*(fieldOfView/(3.141519/4.0))
    let motionInCameraCoordinates = float3(scrollingSensitivity*Float(event.scrollingDeltaX), -scrollingSensitivity*Float(event.scrollingDeltaY), 0.0)
    var cameraToObject = matrix_invert(matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)))
    let motionInObjectCoordinates = matrix_multiply(cameraToObject, motionInCameraCoordinates)
    modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: motionInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)

    // Correct motion so that the point of rotation remains at the same depth as the data
    cameraToObject = matrix_invert(matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)))
    let depthOffset = 1.0+depthAtCentre()
//    Swift.print("Depth offset: \(depthOffset)")
    let depthOffsetInCameraCoordinates = float3(0.0, 0.0, -depthOffset)
    let depthOffsetInObjectCoordinates = matrix_multiply(cameraToObject, depthOffsetInCameraCoordinates)
    modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: depthOffsetInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    
    // Put model matrix in arrays and render
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: modelMatrix)))
    constants.viewMatrixInverse = matrix_invert(viewMatrix)
    needsDisplay = true
  }
  
  override func mouseDragged(with event: NSEvent) {
//    Swift.print("mouseDragged()")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    
    // Compute the current and last mouse positions and their depth on a sphere
    let currentX: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
    let currentZ: Float = sqrt(1.0 - (currentX*currentX+currentY*currentY))
    let currentPosition = vector_normalize(float3(currentX, currentY, currentZ))
//    Swift.print("Current position \(currentPosition)")
    let lastX: Float = Float(-1.0 + 2.0*((window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x)-event.deltaX) / bounds.size.width)
    let lastY: Float = Float(-1.0 + 2.0*((window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y)+event.deltaY) / bounds.size.height)
    let lastZ: Float = sqrt(1.0 - (lastX*lastX+lastY*lastY))
    let lastPosition = vector_normalize(float3(lastX, lastY, lastZ))
//    Swift.print("Last position \(lastPosition)")
    if currentPosition.x == lastPosition.x && currentPosition.y == lastPosition.y && currentPosition.z == lastPosition.z {
      return
    }
    
    // Compute the angle between the two and use it to move in camera space
    let angle = acos(vector_dot(lastPosition, currentPosition))
    if !angle.isNaN && angle > 0.0 {
      let axisInCameraCoordinates = vector_cross(lastPosition, currentPosition)
      let cameraToObject = matrix_invert(matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)))
      let axisInObjectCoordinates = matrix_multiply(cameraToObject, axisInCameraCoordinates)
      modelRotationMatrix = matrix_multiply(modelRotationMatrix, matrix4x4_rotation(angle: angle, axis: axisInObjectCoordinates))
      modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
      
      constants.modelMatrix = modelMatrix
      constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
      constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: modelMatrix)))
      constants.viewMatrixInverse = matrix_invert(viewMatrix)
      needsDisplay = true
    } else {
//      Swift.print("NaN!")
    }
  }
  
  override func rotate(with event: NSEvent) {
//    Swift.print("MetalView.rotate()")
//    Swift.print("Rotation angle: \(event.rotation)")
    
    let axisInCameraCoordinates = float3(0.0, 0.0, 1.0)
    let cameraToObject = matrix_invert(matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)))
    let axisInObjectCoordinates = matrix_multiply(cameraToObject, axisInCameraCoordinates)
    modelRotationMatrix = matrix_multiply(modelRotationMatrix, matrix4x4_rotation(angle: 3.14159*event.rotation/180.0, axis: axisInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_transpose(matrix_invert(matrix_upper_left_3x3(matrix: modelMatrix)))
    constants.viewMatrixInverse = matrix_invert(viewMatrix)
    needsDisplay = true
  }
  
  override func rightMouseDragged(with event: NSEvent) {
//    Swift.print("MetalView.rightMouseDragged()")
//    Swift.print("Delta: (\(event.deltaX), \(event.deltaY))")
    
    let zoomSensitivity: Float = 0.005
    let magnification: Float = 1.0+zoomSensitivity*Float(event.deltaY)
    fieldOfView = 2.0*atanf(tanf(0.5*fieldOfView)/magnification)
//    Swift.print("Field of view: \(fieldOfView)")
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    needsDisplay = true
  }
  
  override func magnify(with event: NSEvent) {
//    Swift.print("MetalView.magnify()")
//    Swift.print("Pinched: \(event.magnification)")
    let magnification: Float = 1.0+Float(event.magnification)
    fieldOfView = 2.0*atanf(tanf(0.5*fieldOfView)/magnification)
//    Swift.print("Field of view: \(fieldOfView)")
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    needsDisplay = true
  }
  
  override func keyDown(with event: NSEvent) {
//    Swift.print(event.charactersIgnoringModifiers![(event.charactersIgnoringModifiers?.startIndex)!])
    
    switch event.charactersIgnoringModifiers![(event.charactersIgnoringModifiers?.startIndex)!] {
    case "b":
      controller!.toggleViewBoundingBox(controller!.toggleViewBoundingBoxMenuItem)
    case "e":
      controller!.toggleViewEdges(controller!.toggleViewEdgesMenuItem)
    case "g":
      controller!.toggleGraphics(controller!.toggleGraphicsMenuItem)
    case "h":
      controller!.goHome(controller!.goHomeMenuItem)
    case "o":
      controller!.openFile(controller!.openFileMenuItem)
    case "r":
      controller!.goHome(controller!.goHomeMenuItem)
    default:
      break
    }
  }
  
  override func flagsChanged(with event: NSEvent) {
    if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
      multipleSelection = true
    } else {
      multipleSelection = false
    }
  }
  
  func depthAtCentre() -> GLfloat {
    
    // Compute midCoordinates and maxRange
    let minCoordinates = float3(dataStorage!.minCoordinates)
    let maxCoordinates = float3(dataStorage!.maxCoordinates)
    let range = maxCoordinates-minCoordinates
    let midCoordinates = minCoordinates+0.5*range
    var maxRange = range.x
    if range.y > maxRange {
      maxRange = range.y
    }
    if range.z > maxRange {
      maxRange = range.z
    }
    
    // Create three points along the data plane
    let leftUpPointInObjectCoordinates = float4((minCoordinates.x-midCoordinates.x)/maxRange, (maxCoordinates.y-midCoordinates.y)/maxRange, 0.0, 1.0)
    let rightUpPointInObjectCoordinates = float4((maxCoordinates.x-midCoordinates.x)/maxRange, (maxCoordinates.y-midCoordinates.y)/maxRange, 0.0, 1.0)
    let centreDownPointInObjectCoordinates = float4(0.0, (minCoordinates.y-midCoordinates.y)/maxRange, 0.0, 1.0)
    
    // Obtain their coordinates in eye space
    let modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix)
    let leftUpPoint = matrix_multiply(modelViewMatrix, leftUpPointInObjectCoordinates)
    let rightUpPoint = matrix_multiply(modelViewMatrix, rightUpPointInObjectCoordinates)
    let centreDownPoint = matrix_multiply(modelViewMatrix, centreDownPointInObjectCoordinates)
    
    // Compute the plane passing through the points.
    // In ax + by + cz + d = 0, abc are given by the cross product, d by evaluating a point in the equation.
    let vector1 = float3(leftUpPoint.x-centreDownPoint.x, leftUpPoint.y-centreDownPoint.y, leftUpPoint.z-centreDownPoint.z)
    let vector2 = float3(rightUpPoint.x-centreDownPoint.x, rightUpPoint.y-centreDownPoint.y, rightUpPoint.z-centreDownPoint.z)
    let crossProduct = vector_cross(vector1, vector2)
    let point3 = float3(centreDownPoint.x/centreDownPoint.w, centreDownPoint.y/centreDownPoint.w, centreDownPoint.z/centreDownPoint.w)
    let d = -vector_dot(crossProduct, point3)
    
    // Assuming x = 0 and y = 0, z (i.e. depth at the centre) = -d/c
//    Swift.print("Depth at centre: \(-d/crossProduct.z)")
    return -d/crossProduct.z
  }
  
  func pullData() {
    Swift.print("MetalView.pullData()")
    let startTime = CACurrentMediaTime()
    
    // Compute midCoordinates and maxRange
    let minCoordinates = float3(dataStorage!.minCoordinates)
    let maxCoordinates = float3(dataStorage!.maxCoordinates)
    let range = maxCoordinates-minCoordinates
    let midCoordinates = minCoordinates+0.5*range
    var maxRange = range.x
    if range.y > maxRange {
      maxRange = range.y
    }
    if range.z > maxRange {
      maxRange = range.z
    }
    
    var vertices = [String: [String: [Vertex]]]()
    var edgeVertices = [Vertex]()
    var selectionEdgeVertices = [Vertex]()
    var selectionFaceVertices = [Vertex]()
    
    let boundingBoxVertices: [Vertex] = [Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 000 -> 001
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 000 -> 010
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 000 -> 100
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 001 -> 011
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 001 -> 101
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 010 -> 011
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 010 -> 110
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((minCoordinates.x-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 011 -> 111
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 100 -> 101
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 100 -> 110
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (minCoordinates.y-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 101 -> 111
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (minCoordinates.z-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0)),  // 110 -> 111
                                         Vertex(position: float3((dataStorage!.maxCoordinates[0]-midCoordinates.x)/maxRange,
                                                                 (dataStorage!.maxCoordinates[1]-midCoordinates.y)/maxRange,
                                                                 (dataStorage!.maxCoordinates[2]-midCoordinates.z)/maxRange),
                                                normal: float3(0.0, 0.0, 0.0))]
    
    for object in dataStorage!.objects {
      if !vertices.keys.contains(object.type) {
        vertices[object.type] = [String: [Vertex]]()
      }
      
      if dataStorage!.selection.contains(object.id) {
        let numberOfVertices = object.edgesBuffer.count/3
        for vertexIndex in 0..<numberOfVertices {
          selectionEdgeVertices.append(Vertex(position: float3((object.edgesBuffer[3*vertexIndex]-midCoordinates.x)/maxRange,
                                                               (object.edgesBuffer[3*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                               (object.edgesBuffer[3*vertexIndex+2]-midCoordinates.z)/maxRange),
                                              normal: float3(0.0, 0.0, 0.0)))
        }
        for triangleBufferType in object.triangleBuffersByType.keys {
          let numberOfVertices = object.triangleBuffersByType[triangleBufferType]!.count/6
          let currentTriangleBuffer = object.triangleBuffersByType[triangleBufferType]!
          for vertexIndex in 0..<numberOfVertices {
            selectionFaceVertices.append(Vertex(position: float3((currentTriangleBuffer[6*vertexIndex]-midCoordinates.x)/maxRange,
                                                                 (currentTriangleBuffer[6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                                 (currentTriangleBuffer[6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                                normal: float3(currentTriangleBuffer[6*vertexIndex+3],
                                                               currentTriangleBuffer[6*vertexIndex+4],
                                                               currentTriangleBuffer[6*vertexIndex+5])))
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
        for triangleBufferType in object.triangleBuffersByType.keys {
          if !vertices[object.type]!.keys.contains(triangleBufferType) {
            vertices[object.type]![triangleBufferType] = [Vertex]()
          }
          let numberOfVertices = object.triangleBuffersByType[triangleBufferType]!.count/6
          var temporaryBuffer = [Vertex]()
          temporaryBuffer.reserveCapacity(numberOfVertices)
          let currentTriangleBuffer = object.triangleBuffersByType[triangleBufferType]!
          for vertexIndex in 0..<numberOfVertices {
            temporaryBuffer.append(Vertex(position: float3((currentTriangleBuffer[6*vertexIndex]-midCoordinates.x)/maxRange,
                                                           (currentTriangleBuffer[6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                           (currentTriangleBuffer[6*vertexIndex+2]-midCoordinates.z)/maxRange),
                                          normal: float3(currentTriangleBuffer[6*vertexIndex+3],
                                                         currentTriangleBuffer[6*vertexIndex+4],
                                                         currentTriangleBuffer[6*vertexIndex+5])))
          }
          vertices[object.type]![triangleBufferType]!.append(contentsOf: temporaryBuffer)
        }
      }
    }
    
    faceBuffers.removeAll()
    edgesBuffer = device!.makeBuffer(bytes: edgeVertices, length: MemoryLayout<Vertex>.size*edgeVertices.count, options: [])
    for vertexType in vertices {
      if !faceBuffers.keys.contains(vertexType.key) {
        faceBuffers[vertexType.key] = [String: MTLBuffer]()
      }
      for vertexSubtype in vertexType.value {
        faceBuffers[vertexType.key]![vertexSubtype.key] = device!.makeBuffer(bytes: vertices[vertexType.key]![vertexSubtype.key]!, length: MemoryLayout<Vertex>.size*vertices[vertexType.key]![vertexSubtype.key]!.count, options: [])
      }
    }
    boundingBoxBuffer = device!.makeBuffer(bytes: boundingBoxVertices, length: MemoryLayout<Vertex>.size*boundingBoxVertices.count, options: [])
    if (selectionEdgeVertices.count > 0) {
      selectedEdgesBuffer = device!.makeBuffer(bytes: selectionEdgeVertices, length: MemoryLayout<Vertex>.size*selectionEdgeVertices.count, options: [])
    }
    if (selectionFaceVertices.count > 0) {
      selectedFacesBuffer = device!.makeBuffer(bytes: selectionFaceVertices, length: MemoryLayout<Vertex>.size*selectionFaceVertices.count, options: [])
    }
    
    Swift.print("Loaded triangles: ", separator: "", terminator: "")
    for vertexType in vertices {
      for vertexSubtype in vertexType.value {
        Swift.print("\(vertexSubtype.value.count/3) from \(vertexType.key) \(vertexSubtype.key)", separator: "", terminator: ", ")
      }
    }
    Swift.print("and \(selectionFaceVertices.count/3) from selected objects.")
    Swift.print("Loaded \(edgeVertices.count/2) edges, \(boundingBoxVertices.count/2) edges from the bounding box and \(selectionEdgeVertices.count/2) edges from the selection.")
    Swift.print("\t3. Pulled data in \(CACurrentMediaTime()-startTime) seconds.")
  }
  
  override func draw(_ dirtyRect: NSRect) {
//    Swift.print("MetalView.draw(NSRect)")
    
    if dirtyRect.width == 0 {
      return
    }
    
    let commandBuffer = commandQueue!.makeCommandBuffer()
    let renderPassDescriptor = currentRenderPassDescriptor!
    let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setRenderPipelineState(renderPipelineState!)
    
    for bufferType in faceBuffers {
      if !renderedTypes.keys.contains(bufferType.key) {
        Swift.print("Render type for \(bufferType.key) not set")
        continue
      }
      for bufferSubtype in bufferType.value {
        if !renderedTypes[bufferType.key]!.keys.contains(bufferSubtype.key) {
          Swift.print("Render type for \(bufferType.key) \(bufferSubtype.key) not set")
          continue
        }
        if faceBuffers[bufferType.key]![bufferSubtype.key]!.length > 0 {
          renderEncoder.setVertexBuffer(faceBuffers[bufferType.key]![bufferSubtype.key]!, offset:0, at:0)
          constants.colour = renderedTypes[bufferType.key]![bufferSubtype.key]!
          renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
          renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: faceBuffers[bufferType.key]![bufferSubtype.key]!.length/MemoryLayout<Vertex>.size)
        }
      }
    }
    
    if viewEdges && edgesBuffer != nil && edgesBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(edgesBuffer, offset:0, at:0)
      constants.colour = float4(0.0, 0.0, 0.0, 1.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: edgesBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if viewBoundingBox && boundingBoxBuffer != nil && boundingBoxBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(boundingBoxBuffer, offset:0, at:0)
      constants.colour = float4(0.0, 0.0, 0.0, 1.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: boundingBoxBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if selectedFacesBuffer != nil && selectedFacesBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(selectedFacesBuffer, offset:0, at:0)
      constants.colour = float4(1.0, 1.0, 0.0, 1.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: selectedFacesBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if viewEdges && selectedEdgesBuffer != nil && selectedEdgesBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(selectedEdgesBuffer, offset:0, at:0)
      constants.colour = float4(1.0, 0.0, 0.0, 1.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: selectedEdgesBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    renderEncoder.endEncoding()
    let drawable = currentDrawable!
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
  
  override func setFrameSize(_ newSize: NSSize) {
//    Swift.print("setFrameSize(NSSize)")
    super.setFrameSize(newSize)
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    needsDisplay = true
  }
  
}
