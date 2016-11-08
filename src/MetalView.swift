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
  var colour = float3(0.0, 0.0, 0.0)
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
  
  var buildingsBuffer: MTLBuffer?
  var buildingRoofsBuffer: MTLBuffer?
  var roadsBuffer: MTLBuffer?
  var waterBuffer: MTLBuffer?
  var plantCoverBuffer: MTLBuffer?
  var terrainBuffer: MTLBuffer?
  var genericBuffer: MTLBuffer?
  var bridgesBuffer: MTLBuffer?
  var landUseBuffer: MTLBuffer?
  var edgesBuffer: MTLBuffer?
  var boundingBoxBuffer: MTLBuffer?
  var selectedFacesBuffer: MTLBuffer?
  var selectedEdgesBuffer: MTLBuffer?
  
  var viewEdges: Bool = true
  var viewBoundingBox: Bool = false
  
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
  
  override init(frame frameRect: CGRect,
       device: MTLDevice?) {
    Swift.print("MetalView.init(CGRect, MTLDevice?)")
    
    super.init(frame: frameRect, device: device)
    
    self.isPaused = true
    self.enableSetNeedsDisplay = true
  }
  
  required init(coder: NSCoder) {
    Swift.print("MetalView.init(NSCoder)")
    
    super.init(coder: coder)
    
    self.isPaused = true
    self.enableSetNeedsDisplay = true
  }
  
  override var acceptsFirstResponder: Bool {
    return true
  }
  
  override func awakeFromNib() {
    super.awakeFromNib()
    
    // View
    clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1)
    colorPixelFormat = .bgra8Unorm
    depthStencilPixelFormat = .depth32Float
    
    // Device
    if let defaultDevice = MTLCreateSystemDefaultDevice() {
      device = defaultDevice
    } else {
      Swift.print("Metal is not supported")
      return
    }
    
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
    
    // Allow dragging
    register(forDraggedTypes: [NSFilenamesPboardType])
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
    //    Swift.print("OpenGLView.mouseUp()")
    
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
        Swift.print("OpenGLView.click()")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    
    // Compute the current mouse position
    let currentX: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
    
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
          let vertex0 = float3((trianglesBuffer.value[Int(18*triangleIndex)]-dataStorage!.midCoordinates[0])/dataStorage!.maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+1)]-dataStorage!.midCoordinates[1])/dataStorage!.maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+2)]-dataStorage!.midCoordinates[2])/dataStorage!.maxRange)
          let vertex1 = float3((trianglesBuffer.value[Int(18*triangleIndex+6)]-dataStorage!.midCoordinates[0])/dataStorage!.maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+7)]-dataStorage!.midCoordinates[1])/dataStorage!.maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+8)]-dataStorage!.midCoordinates[2])/dataStorage!.maxRange)
          let vertex2 = float3((trianglesBuffer.value[Int(18*triangleIndex+12)]-dataStorage!.midCoordinates[0])/dataStorage!.maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+13)]-dataStorage!.midCoordinates[1])/dataStorage!.maxRange,
                               (trianglesBuffer.value[Int(18*triangleIndex+14)]-dataStorage!.midCoordinates[2])/dataStorage!.maxRange)
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
    
    // Select closest hit
    if hitDistance > -1.0 {
      let selectedRow = dataStorage!.findObjectRow(with: closestHit)
      let rowIndexes = IndexSet(integer: selectedRow)
      controller!.outlineView.selectRowIndexes(rowIndexes, byExtendingSelection: false)
      controller!.outlineView.scrollRowToVisible(selectedRow)
    } else {
      controller!.outlineView.deselectAll(self)
    }
    dataStorage!.pushData()
  }
  
  func doubleClick(with event: NSEvent) {
    //    Swift.print("OpenGLView.doubleClick()")
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
  
  override func scrollWheel(with event: NSEvent) {
    //    Swift.print("OpenGLView.scrollWheel()")
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
//    Swift.print("MetalView.mouseDragged()")
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
//    Swift.print("OpenGLView.rotate()")
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
//    Swift.print("OpenGLView.rightMouseDragged()")
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
//    Swift.print("OpenGLView.magnify()")
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
    case "r":
      controller!.goHome(controller!.goHomeMenuItem)
    default:
      break
    }
  }
  
  func depthAtCentre() -> GLfloat {
    
    // Create three points along the data plane
    let leftUpPointInObjectCoordinates = float4((dataStorage!.minCoordinates[0]-dataStorage!.midCoordinates[0])/dataStorage!.maxRange, (dataStorage!.maxCoordinates[1]-dataStorage!.midCoordinates[1])/dataStorage!.maxRange, 0.0, 1.0)
    let rightUpPointInObjectCoordinates = float4((dataStorage!.maxCoordinates[0]-dataStorage!.midCoordinates[0])/dataStorage!.maxRange, (dataStorage!.maxCoordinates[1]-dataStorage!.midCoordinates[1])/dataStorage!.maxRange, 0.0, 1.0)
    let centreDownPointInObjectCoordinates = float4(0.0, (dataStorage!.minCoordinates[1]-dataStorage!.midCoordinates[1])/dataStorage!.maxRange, 0.0, 1.0)
    
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
  
  override func draw(_ dirtyRect: NSRect) {
//    Swift.print("Renderer.draw()")
    
    let commandBuffer = commandQueue!.makeCommandBuffer()
    let renderPassDescriptor = currentRenderPassDescriptor!
    let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setRenderPipelineState(renderPipelineState!)
    
    if buildingsBuffer != nil && buildingsBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(buildingsBuffer, offset:0, at:0)
      constants.colour = float3(1.0, 0.956862745098039, 0.690196078431373)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: buildingsBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if buildingRoofsBuffer != nil && buildingRoofsBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(buildingRoofsBuffer, offset:0, at:0)
      constants.colour = float3(0.882352941176471, 0.254901960784314, 0.219607843137255)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: buildingRoofsBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if roadsBuffer != nil && roadsBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(roadsBuffer, offset:0, at:0)
      constants.colour = float3(0.458823529411765, 0.458823529411765, 0.458823529411765)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: roadsBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if waterBuffer != nil && waterBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(waterBuffer, offset:0, at:0)
      constants.colour = float3(0.584313725490196, 0.917647058823529, 1.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: waterBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if plantCoverBuffer != nil && plantCoverBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(plantCoverBuffer, offset:0, at:0)
      constants.colour = float3(0.4, 0.882352941176471, 0.333333333333333)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: plantCoverBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if terrainBuffer != nil && terrainBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(terrainBuffer, offset:0, at:0)
      constants.colour = float3(0.713725490196078, 0.882352941176471, 0.623529411764706)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: terrainBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if genericBuffer != nil && genericBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(genericBuffer, offset:0, at:0)
      constants.colour = float3(0.7, 0.7, 0.7)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: genericBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if bridgesBuffer != nil && bridgesBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(bridgesBuffer, offset:0, at:0)
      constants.colour = float3(0.247058823529412, 0.247058823529412, 0.247058823529412)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: bridgesBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if landUseBuffer != nil && landUseBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(landUseBuffer, offset:0, at:0)
      constants.colour = float3(1.0, 0.0, 0.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: landUseBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if viewEdges && edgesBuffer != nil && edgesBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(edgesBuffer, offset:0, at:0)
      constants.colour = float3(0.0, 0.0, 0.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: edgesBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if viewBoundingBox && boundingBoxBuffer != nil && boundingBoxBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(boundingBoxBuffer, offset:0, at:0)
      constants.colour = float3(0.0, 0.0, 0.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: boundingBoxBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if selectedFacesBuffer != nil && selectedFacesBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(selectedFacesBuffer, offset:0, at:0)
      constants.colour = float3(1.0, 1.0, 0.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: selectedFacesBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    if viewEdges && selectedEdgesBuffer != nil && selectedEdgesBuffer!.length > 0 {
      renderEncoder.setVertexBuffer(selectedEdgesBuffer, offset:0, at:0)
      constants.colour = float3(1.0, 0.0, 0.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, at: 1)
      renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: selectedEdgesBuffer!.length/MemoryLayout<Vertex>.size)
    }
    
    renderEncoder.endEncoding()
    let drawable = currentDrawable!
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
  
  override func setFrameSize(_ newSize: NSSize) {
//    Swift.print("MetalView.setFrameSize(NSSize)")
    super.setFrameSize(newSize)
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    needsDisplay = true
  }
  
}
