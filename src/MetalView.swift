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

import Metal
import MetalKit

extension float4x4 {
    static let identity = matrix_identity_float4x4
}

struct Constants {
  var modelMatrix = matrix_identity_float4x4
  var modelViewProjectionMatrix = matrix_identity_float4x4
  var modelMatrixInverseTransposed = matrix_identity_float3x3
  var viewMatrixInverse = matrix_identity_float4x4
  var colour = float4(0.0, 0.0, 0.0, 1.0)
}

extension CGSize {
  var aspectRatio : CGFloat {
    return width / height
  }
}

struct Vertex {
  var position: float3
}

struct VertexWithNormal {
  var position: float3
  var normal: float3
}

struct BufferWithColour {
  var buffer: MTLBuffer
  var type: String
  var colour: float4
}

extension float4 {

  var xyz: float3 {
    @inline(__always)
    get {
      return .init(x: x, y: y, z: z)
    }
  }
}

@objc class MetalView: MTKView {
  
  var controller: Controller?
  var dataManager: DataManagerWrapperWrapper?
  
  var commandQueue: MTLCommandQueue?
  var litRenderPipelineState: MTLRenderPipelineState?
  var unlitRenderPipelineState: MTLRenderPipelineState?
  var depthStencilState: MTLDepthStencilState?
  
  var triangleBuffers = [BufferWithColour]()
  var edgeBuffers = [BufferWithColour]()
  var boundingBoxBuffer: MTLBuffer?
  
  var viewEdges: Bool = false
  var viewBoundingBox: Bool = false
  
  @objc var multipleSelection: Bool = false
  
  var constants = Constants()
  
  var eye = float3(0.0, 0.0, 0.0)
  var centre = float3(0.0, 0.0, -1.0)
  var fieldOfView: Float = 1.047197551196598
  
  @objc var modelTranslationToCentreOfRotationMatrix = matrix_identity_float4x4
  @objc var modelRotationMatrix = matrix_identity_float4x4
  @objc var modelShiftBackMatrix = matrix_identity_float4x4
  
  @objc var modelMatrix = matrix_identity_float4x4
  @objc var viewMatrix = matrix_identity_float4x4
  @objc var projectionMatrix = matrix_identity_float4x4
  
  override init(frame frameRect: CGRect, device: MTLDevice?) {
    Swift.print("MetalView.init(CGRect, MTLDevice)")
    super.init(frame: frameRect, device: device)
    
    // View
    clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0)
    colorPixelFormat = .bgra8Unorm
    depthStencilPixelFormat = .depth32Float
    
    // Command queue
    commandQueue = device!.makeCommandQueue()
    
    // Render pipeline
    let library = device!.makeDefaultLibrary()!
    let litVertexFunction = library.makeFunction(name: "vertexLit")
    let unlitVertexFunction = library.makeFunction(name: "vertexUnlit")
    let fragmentFunction = library.makeFunction(name: "fragmentLit")
    let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
    renderPipelineDescriptor.vertexFunction = litVertexFunction
    renderPipelineDescriptor.fragmentFunction = fragmentFunction
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
    renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
    renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    renderPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    renderPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    renderPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    do {
      litRenderPipelineState = try device!.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
    } catch {
      Swift.print("Unable to compile lit render pipeline state")
      return
    }
    renderPipelineDescriptor.vertexFunction = unlitVertexFunction
    renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
    do {
      unlitRenderPipelineState = try device!.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
    } catch {
      Swift.print("Unable to compile unlit render pipeline state")
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
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.aspectRatio), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    
    // Allow dragging
    registerForDraggedTypes([.fileURL])
    
    self.isPaused = true
    self.enableSetNeedsDisplay = true
  }
  
  required init(coder: NSCoder) {
    Swift.print("MetalView.init(NSCoder)")
    super.init(coder: coder)
  }
  
  override var acceptsFirstResponder: Bool {
    return true
  }
  
  override func draw(_ dirtyRect: NSRect) {
//    Swift.print("MetalView.draw(NSRect)")
    
    if dirtyRect.width == 0 {
      return
    }
    
    let commandBuffer = commandQueue!.makeCommandBuffer()!
    let renderPassDescriptor = currentRenderPassDescriptor!
    let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    
    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setRenderPipelineState(litRenderPipelineState!)

    for triangleBuffer in triangleBuffers {
      if triangleBuffer.colour.w == 1.0 {
        renderEncoder.setVertexBuffer(triangleBuffer.buffer, offset:0, index:0)
        constants.colour = triangleBuffer.colour
        renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triangleBuffer.buffer.length/MemoryLayout<VertexWithNormal>.size)
      }
    }
    
    for triangleBuffer in triangleBuffers {
      if triangleBuffer.colour.w != 1.0 {
        renderEncoder.setVertexBuffer(triangleBuffer.buffer, offset:0, index:0)
        constants.colour = triangleBuffer.colour
        renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triangleBuffer.buffer.length/MemoryLayout<VertexWithNormal>.size)
      }
    }
    
    renderEncoder.setRenderPipelineState(unlitRenderPipelineState!)
    
    if viewEdges {
      for edgeBuffer in edgeBuffers {
        renderEncoder.setVertexBuffer(edgeBuffer.buffer, offset:0, index:0)
        constants.colour = edgeBuffer.colour
        renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: edgeBuffer.buffer.length/MemoryLayout<Vertex>.size)
      }
    }
    
    if viewBoundingBox && boundingBoxBuffer != nil {
      renderEncoder.setVertexBuffer(boundingBoxBuffer, offset:0, index:0)
      constants.colour = float4(0.0, 0.0, 0.0, 1.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
      renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: boundingBoxBuffer!.length/MemoryLayout<Vertex>.size)
    }
   
    renderEncoder.endEncoding()
    let drawable = currentDrawable!
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
  
  override func setFrameSize(_ newSize: NSSize) {
//    Swift.print("MetalView.setFrameSize(NSSize)")
    super.setFrameSize(newSize)
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.aspectRatio), nearZ: 0.001, farZ: 100.0)
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    needsDisplay = true
    controller!.progressIndicator!.setFrameSize(NSSize(width: self.frame.width/4, height: 12))
    controller!.statusTextField!.setFrameOrigin(NSPoint(x: self.frame.width/4, y: 0))
    controller!.statusTextField!.setFrameSize(NSSize(width: 3*self.frame.width/4, height: 16))
  }
  
  @objc func depthAtCentre() -> Float {
    
    let firstMinCoordinate = dataManager!.minCoordinates
    let minCoordinatesBuffer = UnsafeBufferPointer(start: firstMinCoordinate, count: 3)
    let minCoordinatesArray = ContiguousArray(minCoordinatesBuffer)
    let minCoordinates = [Float](minCoordinatesArray)
    let firstMidCoordinate = dataManager!.midCoordinates
    let midCoordinatesBuffer = UnsafeBufferPointer(start: firstMidCoordinate, count: 3)
    let midCoordinatesArray = ContiguousArray(midCoordinatesBuffer)
    let midCoordinates = [Float](midCoordinatesArray)
    let firstMaxCoordinate = dataManager!.maxCoordinates
    let maxCoordinatesBuffer = UnsafeBufferPointer(start: firstMaxCoordinate, count: 3)
    let maxCoordinatesArray = ContiguousArray(maxCoordinatesBuffer)
    let maxCoordinates = [Float](maxCoordinatesArray)
    let maxRange = dataManager!.maxRange

    // Create three points along the data plane
    let leftUpPointInObjectCoordinates = float4((minCoordinates[0]-midCoordinates[0])/maxRange, (maxCoordinates[1]-midCoordinates[1])/maxRange, 0.0, 1.0)
    let rightUpPointInObjectCoordinates = float4((maxCoordinates[0]-midCoordinates[0])/maxRange, (maxCoordinates[1]-midCoordinates[1])/maxRange, 0.0, 1.0)
    let centreDownPointInObjectCoordinates = float4(0.0, (minCoordinates[1]-midCoordinates[1])/maxRange, 0.0, 1.0)

    // Obtain their coordinates in eye space
    let modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix)
    let leftUpPoint = matrix_multiply(modelViewMatrix, leftUpPointInObjectCoordinates)
    let rightUpPoint = matrix_multiply(modelViewMatrix, rightUpPointInObjectCoordinates)
    let centreDownPoint = matrix_multiply(modelViewMatrix, centreDownPointInObjectCoordinates)

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

  override func scrollWheel(with event: NSEvent) {
    //    Swift.print("MetalView.scrollWheel()")
    //    Swift.print("Scrolled X: \(event.scrollingDeltaX) Y: \(event.scrollingDeltaY)")

    // Motion according to trackpad
    let scrollingSensitivity: Float = 0.003*(fieldOfView/(3.141519/4.0))
    let motionInCameraCoordinates = float3(Float(event.scrollingDeltaX), -Float(event.scrollingDeltaY), 0.0) * scrollingSensitivity
    var cameraToObject = matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)).inverse
    let motionInObjectCoordinates = matrix_multiply(cameraToObject, motionInCameraCoordinates)
    modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: motionInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)

    // Correct motion so that the point of rotation remains at the same depth as the data
    cameraToObject = matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)).inverse
    let depthOffset = 1.0+depthAtCentre()
    //    Swift.print("Depth offset: \(depthOffset)")
    let depthOffsetInCameraCoordinates = float3(0.0, 0.0, -depthOffset)
    let depthOffsetInObjectCoordinates = matrix_multiply(cameraToObject, depthOffsetInCameraCoordinates)
    modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: depthOffsetInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)

    // Put model matrix in arrays and render
    constants.modelMatrix = modelMatrix
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    needsDisplay = true
  }
  
  override func magnify(with event: NSEvent) {
    //    Swift.print("MetalView.magnify()")
    //    Swift.print("Pinched: \(event.magnification)")
    let magnification: Float = 1.0+Float(event.magnification)
    fieldOfView = 2.0*atanf(tanf(0.5*fieldOfView)/magnification)
    //    Swift.print("Field of view: \(fieldOfView)")
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.aspectRatio), nearZ: 0.001, farZ: 100.0)
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    needsDisplay = true
  }
  
  override func rotate(with event: NSEvent) {
    //    Swift.print("MetalView.rotate()")
    //    Swift.print("Rotation angle: \(event.rotation)")
    
    let axisInCameraCoordinates = float3(0.0, 0.0, 1.0)
    let cameraToObject = matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)).inverse
    let axisInObjectCoordinates = matrix_multiply(cameraToObject, axisInCameraCoordinates)
    modelRotationMatrix = matrix_multiply(modelRotationMatrix, matrix4x4_rotation(angle: 3.14159*event.rotation/180.0, axis: axisInObjectCoordinates))
    modelMatrix = matrix_multiply(modelShiftBackMatrix, modelRotationMatrix) * modelTranslationToCentreOfRotationMatrix
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    needsDisplay = true
  }
  
  override func mouseDragged(with event: NSEvent) {
    let point = window!.mouseLocationOutsideOfEventStream
    //    Swift.print("mouseDragged()")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    
    // Compute the current and last mouse positions and their depth on a sphere
    let currentX: Float = Float(-1.0 + 2.0*(point.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(point.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
    let currentZ: Float = sqrt(1.0 - (currentX*currentX+currentY*currentY))
    let currentPosition = normalize(float3(currentX, currentY, currentZ))
    //    Swift.print("Current position \(currentPosition)")
    let lastX: Float = Float(-1.0 + 2.0*((point.x-viewFrameInWindowCoordinates.origin.x)-event.deltaX) / bounds.size.width)
    let lastY: Float = Float(-1.0 + 2.0*((point.y-viewFrameInWindowCoordinates.origin.y)+event.deltaY) / bounds.size.height)
    let lastZ: Float = sqrt(1.0 - (lastX*lastX+lastY*lastY))
    let lastPosition = normalize(float3(lastX, lastY, lastZ))
    //    Swift.print("Last position \(lastPosition)")
    if currentPosition == lastPosition {
      return
    }
    
    // Compute the angle between the two and use it to move in camera space
    let angle = acos(dot(lastPosition, currentPosition))
    if !angle.isNaN && angle > 0.0 {
      let axisInCameraCoordinates = cross(lastPosition, currentPosition)
      let cameraToObject = matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)).inverse
      let axisInObjectCoordinates = matrix_multiply(cameraToObject, axisInCameraCoordinates)
      modelRotationMatrix = matrix_multiply(modelRotationMatrix, matrix4x4_rotation(angle: angle, axis: axisInObjectCoordinates))
      modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
      
      constants.modelMatrix = modelMatrix
      constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
      constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
      constants.viewMatrixInverse = viewMatrix.inverse
      needsDisplay = true
    } else {
      //      Swift.print("NaN!")
    }
  }
  
  override func rightMouseDragged(with event: NSEvent) {
    //    Swift.print("MetalView.rightMouseDragged()")
    //    Swift.print("Delta: (\(event.deltaX), \(event.deltaY))")
    
    let zoomSensitivity: Float = 0.005
    let magnification: Float = 1.0+zoomSensitivity*Float(event.deltaY)
    fieldOfView = 2.0*atanf(tanf(0.5*fieldOfView)/magnification)
    //    Swift.print("Field of view: \(fieldOfView)")
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.aspectRatio), nearZ: 0.001, farZ: 100.0)
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    needsDisplay = true
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
    dataManager!.click()
    Swift.print("Click computed in \(CACurrentMediaTime()-startTime) seconds.")
  }
  
  func doubleClick(with event: NSEvent) {
        Swift.print("MetalView.doubleClick()")
    let point = window!.mouseLocationOutsideOfEventStream
    //    Swift.print("Mouse location X: \(window!.mouseLocationOutsideOfEventStream.x), Y: \(window!.mouseLocationOutsideOfEventStream.y)")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    //    Swift.print("View X: \(viewFrameInWindowCoordinates.origin.x), Y: \(viewFrameInWindowCoordinates.origin.y)")
    
    // Compute the current mouse position
    let currentX: Float = Float(-1.0 + 2.0*(point.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(point.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
    //    Swift.print("currentX: \(currentX), currentY: \(currentY)")
    
    // Compute two points on the ray represented by the mouse position at the near and far planes
    let mvpInverse = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix)).inverse
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
    var cameraToObject = matrix_upper_left_3x3(matrix: objectToCamera).inverse
    let shiftInObjectCoordinates = matrix_multiply(cameraToObject, shiftInCameraCoordinates)
    modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: shiftInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    
    // Correct shift so that the point of rotation remains at the same depth as the data
    cameraToObject = matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)).inverse
    let depthOffset = 1.0+depthAtCentre()
    let depthOffsetInCameraCoordinates = float3(0.0, 0.0, -depthOffset)
    let depthOffsetInObjectCoordinates = matrix_multiply(cameraToObject, depthOffsetInCameraCoordinates)
    modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: depthOffsetInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    
    // Put model matrix in arrays and render
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    needsDisplay = true
  }
  
  func goHome() {
    
    fieldOfView = 1.047197551196598
    
    modelTranslationToCentreOfRotationMatrix = .identity
    modelRotationMatrix = .identity
    modelShiftBackMatrix = matrix4x4_translation(shift: centre)
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: float3(0.0, 1.0, 0.0))
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.aspectRatio), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    needsDisplay = true
  }
  
  func new() {
    
    triangleBuffers.removeAll()
    edgeBuffers.removeAll()
    
    fieldOfView = 1.047197551196598
    
    modelTranslationToCentreOfRotationMatrix = .identity
    modelRotationMatrix = .identity
    modelShiftBackMatrix = matrix4x4_translation(shift: centre)
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: float3(0.0, 1.0, 0.0))
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.aspectRatio), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    
    needsDisplay = true
  }
  
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let acceptedFileTypes: Set = ["gml", "xml", "json", "obj", "off", "poly"]
    if let urls = sender.draggingPasteboard().readObjects(forClasses: [NSURL.self], options: [:]) as? [URL] {
      for url in urls {
        if acceptedFileTypes.contains(url.pathExtension) {
          return .copy
        }
      }
    }
    return []
  }
  
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if let urls = sender.draggingPasteboard().readObjects(forClasses: [NSURL.self], options: [:]) as? [URL] {
      controller!.loadData(from: urls)
    }
    return true
  }
  
  override func keyDown(with event: NSEvent) {
    //    Swift.print(event.charactersIgnoringModifiers![(event.charactersIgnoringModifiers?.startIndex)!])
    
    switch event.charactersIgnoringModifiers![(event.charactersIgnoringModifiers?.startIndex)!] {
    case "b":
      controller!.toggleViewBoundingBox(controller!.toggleViewBoundingBoxMenuItem)
    case "c":
      controller!.copyObjectId(controller!.copyObjectIdMenuItem)
    case "e":
      controller!.toggleViewEdges(controller!.toggleViewEdgesMenuItem)
    case "f":
      controller!.focusOnSearchBar(controller!.findMenuItem)
    case "l":
      controller!.loadViewParameters(controller!.loadViewParametersMenuItem)
    case "h":
      controller!.goHome(controller!.goHomeMenuItem)
    case "n":
      controller!.new(controller!.newFileMenuItem)
    case "o":
      controller!.openFile(controller!.openFileMenuItem)
    case "s":
      controller!.saveViewParameters(controller!.saveViewParametersMenuItem)
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
}
