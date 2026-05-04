// azul
// Copyright © 2016-2026 Ken Arroyo Ohori
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
  var colour = SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
}

struct Vertex {
  var position: SIMD3<Float>
}

struct VertexWithNormal {
  var px, py, pz: Float
  var objectId: Float
  var nx, ny, nz: Float
}

struct BufferWithColour {
  var buffer: MTLBuffer
  var indexBuffer: MTLBuffer
  var indexCount: Int
  var type: String
  var colour: SIMD4<Float>
}

@objc class MetalView: MTKView {
  
  var controller: Controller?
  var dataManager: DataManagerWrapperWrapper?
  
  var commandQueue: MTLCommandQueue?
  var litRenderPipelineState: MTLRenderPipelineState?
  var unlitRenderPipelineState: MTLRenderPipelineState?
  var depthStencilState: MTLDepthStencilState?
  
  var msaaTexture: MTLTexture?
  var msaaDepthTexture: MTLTexture?
  
  var triangleBuffers = [BufferWithColour]()
  var edgeBuffers = [BufferWithColour]()
  var boundingBoxBuffer: MTLBuffer?
  var selectionStateBuffer: MTLBuffer?
  var selectionStateCount: Int = 0
  
  var pickingRenderPipelineState: MTLRenderPipelineState?
  var pickingTexture: MTLTexture?
  var pickingDepthTexture: MTLTexture?
  
  var viewEdges: Bool = false
  var viewBoundingBox: Bool = false
  
  @objc var multipleSelection: Bool = false
  
  var constants = Constants()
  
  var eye = SIMD3<Float>(0.0, 0.0, 0.0)
  var centre = SIMD3<Float>(0.0, 0.0, -1.0)
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
    self.sampleCount = 4
    
    // Command queue
    commandQueue = device!.makeCommandQueue()
    
    // Build pipeline descriptors
    let library = device!.makeDefaultLibrary()!
    
    let litPipelineDescriptor = MTLRenderPipelineDescriptor()
    litPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexLit")
    litPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentLit")
    litPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
    litPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
    litPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    litPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    litPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    litPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    litPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    litPipelineDescriptor.rasterSampleCount = sampleCount
    
    let unlitPipelineDescriptor = MTLRenderPipelineDescriptor()
    unlitPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexUnlit")
    unlitPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentUnlit")
    unlitPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
    unlitPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
    unlitPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    unlitPipelineDescriptor.rasterSampleCount = sampleCount
    
    // Create pipeline states (always compile from the offline-compiled metallib)
    do {
      litRenderPipelineState = try device!.makeRenderPipelineState(descriptor: litPipelineDescriptor)
      unlitRenderPipelineState = try device!.makeRenderPipelineState(descriptor: unlitPipelineDescriptor)
    } catch {
      Swift.print("Unable to compile render pipeline states: \(error)")
      return
    }
    
    // Picking pipeline
    let pickingPipelineDescriptor = MTLRenderPipelineDescriptor()
    pickingPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexPicking")
    pickingPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentPicking")
    pickingPipelineDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
    pickingPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    pickingPipelineDescriptor.rasterSampleCount = 1
    do {
      pickingRenderPipelineState = try device!.makeRenderPipelineState(descriptor: pickingPipelineDescriptor)
    } catch {
      Swift.print("Unable to compile picking pipeline state: \(error)")
    }
    
    // Cache compiled pipeline states as a binary archive for faster launches
    let fileManager = FileManager.default
    let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("azul", isDirectory: true)
    let archiveURL = appSupportURL.appendingPathComponent("azul.metalar")
    try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    
    if !fileManager.fileExists(atPath: archiveURL.path) {
      if let archive = try? device!.makeBinaryArchive(descriptor: MTLBinaryArchiveDescriptor()) {
        try? archive.addRenderPipelineFunctions(descriptor: litPipelineDescriptor)
        try? archive.addRenderPipelineFunctions(descriptor: unlitPipelineDescriptor)
        if let pickFunction = library.makeFunction(name: "pick") {
          let pickDesc = MTLComputePipelineDescriptor()
          pickDesc.computeFunction = pickFunction
          try? archive.addComputePipelineFunctions(descriptor: pickDesc)
        }
        try? archive.serialize(to: archiveURL)
        Swift.print("Cached binary archive to \(archiveURL.path)")
      }
    }
    
    // Depth stencil
    let depthSencilDescriptor = MTLDepthStencilDescriptor()
    depthSencilDescriptor.depthCompareFunction = .less
    depthSencilDescriptor.isDepthWriteEnabled = true
    depthStencilState = device!.makeDepthStencilState(descriptor: depthSencilDescriptor)
    
    // MSAA textures
    createMSAATextures(size: drawableSize)
    createPickingTextures()
    
    // Matrices
    modelShiftBackMatrix = matrix4x4_translation(shift: centre)
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: SIMD3<Float>(0.0, 1.0, 0.0))
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    
    // Allow dragging
    registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
    
    self.isPaused = true
    self.enableSetNeedsDisplay = true
  }
  
  func createPickingTextures() {
    let w = Int(drawableSize.width)
    let h = Int(drawableSize.height)
    guard w > 0, h > 0 else { return }
    
    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
    desc.usage = [.renderTarget, .shaderRead]
    pickingTexture = device!.makeTexture(descriptor: desc)
    
    let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthStencilPixelFormat, width: w, height: h, mipmapped: false)
    depthDesc.usage = .renderTarget
    pickingDepthTexture = device!.makeTexture(descriptor: depthDesc)
  }
  
  required init(coder: NSCoder) {
    Swift.print("MetalView.init(NSCoder)")
    super.init(coder: coder)
  }
  
  override var acceptsFirstResponder: Bool {
    return true
  }
  
  func createMSAATextures(size: CGSize) {
    let w = Int(size.width)
    let h = Int(size.height)
    guard w > 0, h > 0 else { return }
    
    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: colorPixelFormat, width: w, height: h, mipmapped: false)
    desc.textureType = .type2DMultisample
    desc.sampleCount = sampleCount
    desc.usage = .renderTarget
    msaaTexture = device!.makeTexture(descriptor: desc)
    
    let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthStencilPixelFormat, width: w, height: h, mipmapped: false)
    depthDesc.textureType = .type2DMultisample
    depthDesc.sampleCount = sampleCount
    depthDesc.usage = .renderTarget
    msaaDepthTexture = device!.makeTexture(descriptor: depthDesc)
  }
  
  override func draw(_ dirtyRect: NSRect) {
//    Swift.print("MetalView.draw(NSRect)")
    
    if dirtyRect.width == 0 {
      return
    }
    
    guard let msaaTexture = msaaTexture, let msaaDepthTexture = msaaDepthTexture else { return }
    
    let commandBuffer = commandQueue!.makeCommandBuffer()!
    let renderPassDescriptor = MTLRenderPassDescriptor()
    renderPassDescriptor.colorAttachments[0].texture = msaaTexture
    renderPassDescriptor.colorAttachments[0].resolveTexture = currentDrawable!.texture
    renderPassDescriptor.colorAttachments[0].storeAction = .multisampleResolve
    renderPassDescriptor.colorAttachments[0].clearColor = clearColor
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    renderPassDescriptor.depthAttachment.texture = msaaDepthTexture
    renderPassDescriptor.depthAttachment.clearDepth = 1.0
    renderPassDescriptor.depthAttachment.loadAction = .clear
    renderPassDescriptor.depthAttachment.storeAction = .dontCare
    let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    
    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setRenderPipelineState(litRenderPipelineState!)
    
    if let selBuffer = selectionStateBuffer, selectionStateCount > 0 {
      renderEncoder.setFragmentBuffer(selBuffer, offset: 0, index: 2)
    } else {
      var zero: Float = 0
      renderEncoder.setFragmentBytes(&zero, length: MemoryLayout<Float>.size, index: 2)
    }

    for triangleBuffer in triangleBuffers {
      if triangleBuffer.colour.w == 1.0 {
        renderEncoder.setVertexBuffer(triangleBuffer.buffer, offset:0, index:0)
        constants.colour = triangleBuffer.colour
        renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
        renderEncoder.setFragmentBytes(&constants, length: MemoryLayout<Constants>.size, index: 0)
        renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: triangleBuffer.indexCount, indexType: .uint32, indexBuffer: triangleBuffer.indexBuffer, indexBufferOffset: 0)
      }
    }
    
    for triangleBuffer in triangleBuffers {
      if triangleBuffer.colour.w != 1.0 {
        renderEncoder.setVertexBuffer(triangleBuffer.buffer, offset:0, index:0)
        constants.colour = triangleBuffer.colour
        renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
        renderEncoder.setFragmentBytes(&constants, length: MemoryLayout<Constants>.size, index: 0)
        renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: triangleBuffer.indexCount, indexType: .uint32, indexBuffer: triangleBuffer.indexBuffer, indexBufferOffset: 0)
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
      constants.colour = SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
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
    createMSAATextures(size: drawableSize)
    createPickingTextures()
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    needsDisplay = true
    controller!.progressIndicator!.setFrameSize(NSSize(width: self.frame.width/4, height: 12))
    controller!.statusTextField!.setFrameOrigin(NSPoint(x: self.frame.width/4, y: 0))
    controller!.statusTextField!.setFrameSize(NSSize(width: 3*self.frame.width/4, height: 16))
  }
  
  @objc func depthAtCentre() -> Float {
    
    let firstMinCoordinate = dataManager!.minCoordinates()
    let minCoordinatesBuffer = UnsafeBufferPointer(start: firstMinCoordinate, count: 3)
    let minCoordinatesArray = ContiguousArray(minCoordinatesBuffer)
    let minCoordinates = [Float](minCoordinatesArray)
    let firstMidCoordinate = dataManager!.midCoordinates()
    let midCoordinatesBuffer = UnsafeBufferPointer(start: firstMidCoordinate, count: 3)
    let midCoordinatesArray = ContiguousArray(midCoordinatesBuffer)
    let midCoordinates = [Float](midCoordinatesArray)
    let firstMaxCoordinate = dataManager!.maxCoordinates()
    let maxCoordinatesBuffer = UnsafeBufferPointer(start: firstMaxCoordinate, count: 3)
    let maxCoordinatesArray = ContiguousArray(maxCoordinatesBuffer)
    let maxCoordinates = [Float](maxCoordinatesArray)
    let maxRange = dataManager!.maxRange()

    // Create three points along the data plane
    let leftUpPointInObjectCoordinates = SIMD4<Float>((minCoordinates[0]-midCoordinates[0])/maxRange, (maxCoordinates[1]-midCoordinates[1])/maxRange, 0.0, 1.0)
    let rightUpPointInObjectCoordinates = SIMD4<Float>((maxCoordinates[0]-midCoordinates[0])/maxRange, (maxCoordinates[1]-midCoordinates[1])/maxRange, 0.0, 1.0)
    let centreDownPointInObjectCoordinates = SIMD4<Float>(0.0, (minCoordinates[1]-midCoordinates[1])/maxRange, 0.0, 1.0)

    // Obtain their coordinates in eye space
    let modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix)
    let leftUpPoint = matrix_multiply(modelViewMatrix, leftUpPointInObjectCoordinates)
    let rightUpPoint = matrix_multiply(modelViewMatrix, rightUpPointInObjectCoordinates)
    let centreDownPoint = matrix_multiply(modelViewMatrix, centreDownPointInObjectCoordinates)

    // Compute the plane passing through the points.
    // In ax + by + cz + d = 0, abc are given by the cross product, d by evaluating a point in the equation.
    let vector1 = SIMD3<Float>(leftUpPoint.x-centreDownPoint.x, leftUpPoint.y-centreDownPoint.y, leftUpPoint.z-centreDownPoint.z)
    let vector2 = SIMD3<Float>(rightUpPoint.x-centreDownPoint.x, rightUpPoint.y-centreDownPoint.y, rightUpPoint.z-centreDownPoint.z)
    let crossProduct = cross(vector1, vector2)
    let point3 = SIMD3<Float>(centreDownPoint.x/centreDownPoint.w, centreDownPoint.y/centreDownPoint.w, centreDownPoint.z/centreDownPoint.w)
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
    let motionInCameraCoordinates = SIMD3<Float>(scrollingSensitivity*Float(event.scrollingDeltaX), -scrollingSensitivity*Float(event.scrollingDeltaY), 0.0)
    var cameraToObject = matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)).inverse
    let motionInObjectCoordinates = matrix_multiply(cameraToObject, motionInCameraCoordinates)
    modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: motionInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)

    // Correct motion so that the point of rotation remains at the same depth as the data
    cameraToObject = matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)).inverse
    let depthOffset = 1.0+depthAtCentre()
    //    Swift.print("Depth offset: \(depthOffset)")
    let depthOffsetInCameraCoordinates = SIMD3<Float>(0.0, 0.0, -depthOffset)
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
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    needsDisplay = true
  }
  
  override func rotate(with event: NSEvent) {
    //    Swift.print("MetalView.rotate()")
    //    Swift.print("Rotation angle: \(event.rotation)")
    
    let axisInCameraCoordinates = SIMD3<Float>(0.0, 0.0, 1.0)
    let cameraToObject = matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)).inverse
    let axisInObjectCoordinates = matrix_multiply(cameraToObject, axisInCameraCoordinates)
    modelRotationMatrix = matrix_multiply(modelRotationMatrix, matrix4x4_rotation(angle: 3.14159*event.rotation/180.0, axis: axisInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    needsDisplay = true
  }
  
  override func mouseDragged(with event: NSEvent) {
    //    Swift.print("mouseDragged()")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    
    // Compute the current and last mouse positions and their depth on a sphere
    let currentX: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
    let currentZ: Float = sqrt(1.0 - (currentX*currentX+currentY*currentY))
    let currentPosition = normalize(SIMD3<Float>(currentX, currentY, currentZ))
    //    Swift.print("Current position \(currentPosition)")
    let lastX: Float = Float(-1.0 + 2.0*((window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x)-event.deltaX) / bounds.size.width)
    let lastY: Float = Float(-1.0 + 2.0*((window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y)+event.deltaY) / bounds.size.height)
    let lastZ: Float = sqrt(1.0 - (lastX*lastX+lastY*lastY))
    let lastPosition = normalize(SIMD3<Float>(lastX, lastY, lastZ))
    //    Swift.print("Last position \(lastPosition)")
    if currentPosition.x == lastPosition.x && currentPosition.y == lastPosition.y && currentPosition.z == lastPosition.z {
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
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
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
    //    Swift.print("Mouse location X: \(window!.mouseLocationOutsideOfEventStream.x), Y: \(window!.mouseLocationOutsideOfEventStream.y)")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    //    Swift.print("View X: \(viewFrameInWindowCoordinates.origin.x), Y: \(viewFrameInWindowCoordinates.origin.y)")
    
    // Compute the current mouse position
    let currentX: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
    //    Swift.print("currentX: \(currentX), currentY: \(currentY)")
    
    // Compute two points on the ray represented by the mouse position at the near and far planes
    let mvpInverse = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix)).inverse
    let pointOnNearPlaneInProjectionCoordinates = SIMD4<Float>(currentX, currentY, -1.0, 1.0)
    let pointOnNearPlaneInObjectCoordinates = matrix_multiply(mvpInverse, pointOnNearPlaneInProjectionCoordinates)
    let pointOnFarPlaneInProjectionCoordinates = SIMD4<Float>(currentX, currentY, 1.0, 1.0)
    let pointOnFarPlaneInObjectCoordinates = matrix_multiply(mvpInverse, pointOnFarPlaneInProjectionCoordinates)
    
    // Interpolate the points to obtain the intersection with the data plane z = 0
    let alpha: Float = -(pointOnFarPlaneInObjectCoordinates.z/pointOnFarPlaneInObjectCoordinates.w)/((pointOnNearPlaneInObjectCoordinates.z/pointOnNearPlaneInObjectCoordinates.w)-(pointOnFarPlaneInObjectCoordinates.z/pointOnFarPlaneInObjectCoordinates.w))
    let clickedPointInObjectCoordinates = SIMD4<Float>(alpha*(pointOnNearPlaneInObjectCoordinates.x/pointOnNearPlaneInObjectCoordinates.w)+(1.0-alpha)*(pointOnFarPlaneInObjectCoordinates.x/pointOnFarPlaneInObjectCoordinates.w), alpha*(pointOnNearPlaneInObjectCoordinates.y/pointOnNearPlaneInObjectCoordinates.w)+(1.0-alpha)*(pointOnFarPlaneInObjectCoordinates.y/pointOnFarPlaneInObjectCoordinates.w), 0.0, 1.0)
    
    // Use the intersection to compute the shift in the view space
    let objectToCamera = matrix_multiply(viewMatrix, modelMatrix)
    let clickedPointInCameraCoordinates = matrix_multiply(objectToCamera, clickedPointInObjectCoordinates)
    
    // Compute shift in object space
    let shiftInCameraCoordinates = SIMD3<Float>(-clickedPointInCameraCoordinates.x, -clickedPointInCameraCoordinates.y, 0.0)
    var cameraToObject = matrix_upper_left_3x3(matrix: objectToCamera).inverse
    let shiftInObjectCoordinates = matrix_multiply(cameraToObject, shiftInCameraCoordinates)
    modelTranslationToCentreOfRotationMatrix = matrix_multiply(modelTranslationToCentreOfRotationMatrix, matrix4x4_translation(shift: shiftInObjectCoordinates))
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    
    // Correct shift so that the point of rotation remains at the same depth as the data
    cameraToObject = matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)).inverse
    let depthOffset = 1.0+depthAtCentre()
    let depthOffsetInCameraCoordinates = SIMD3<Float>(0.0, 0.0, -depthOffset)
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
    
    modelTranslationToCentreOfRotationMatrix = matrix_identity_float4x4
    modelRotationMatrix = matrix_identity_float4x4
    modelShiftBackMatrix = matrix4x4_translation(shift: centre)
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: SIMD3<Float>(0.0, 1.0, 0.0))
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    needsDisplay = true
  }
  
  @objc func pickObjectAtX(_ windowX: CGFloat, y windowY: CGFloat) -> Int32 {
    guard let pipeline = pickingRenderPipelineState else {
      Swift.print("pickObject: no pipeline")
      return -1
    }
    guard let colorTex = pickingTexture else {
      Swift.print("pickObject: no color texture")
      return -1
    }
    guard let depthTex = pickingDepthTexture else {
      Swift.print("pickObject: no depth texture")
      return -1
    }
    guard !triangleBuffers.isEmpty else {
      Swift.print("pickObject: no triangle buffers")
      return -1
    }
    
    let viewFrameInWindow = convert(bounds, to: nil)
    let viewX = windowX - viewFrameInWindow.origin.x
    let viewY = windowY - viewFrameInWindow.origin.y
    let scale = window?.backingScaleFactor ?? 1.0
    let pixelX = Int(viewX * scale)
    let pixelY = Int(bounds.height * scale - viewY * scale)
    guard pixelX >= 0, pixelX < colorTex.width,
          pixelY >= 0, pixelY < colorTex.height else {
      Swift.print("pickObject: pixel out of bounds: \(pixelX), \(pixelY) (tex: \(colorTex.width)x\(colorTex.height))")
      return -1
    }
    
    let commandBuffer = commandQueue!.makeCommandBuffer()!
    
    let passDescriptor = MTLRenderPassDescriptor()
    passDescriptor.colorAttachments[0].texture = colorTex
    passDescriptor.colorAttachments[0].loadAction = .clear
    passDescriptor.colorAttachments[0].storeAction = .store
    passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    passDescriptor.depthAttachment.texture = depthTex
    passDescriptor.depthAttachment.loadAction = .clear
    passDescriptor.depthAttachment.storeAction = .dontCare
    passDescriptor.depthAttachment.clearDepth = 1.0
    
    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
    encoder.setRenderPipelineState(pipeline)
    encoder.setFrontFacing(.counterClockwise)
    encoder.setDepthStencilState(depthStencilState)
    encoder.setViewport(MTLViewport(originX: 0, originY: 0,
                                    width: Double(colorTex.width),
                                    height: Double(colorTex.height),
                                    znear: 0, zfar: 1))
    encoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
    
    for triangleBuffer in triangleBuffers {
      encoder.setVertexBuffer(triangleBuffer.buffer, offset: 0, index: 0)
      encoder.drawIndexedPrimitives(type: .triangle, indexCount: triangleBuffer.indexCount, indexType: .uint32, indexBuffer: triangleBuffer.indexBuffer, indexBufferOffset: 0)
    }
    
    encoder.endEncoding()
    
    let stagingBuffer = device!.makeBuffer(length: 4, options: .storageModeShared)!
    let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
    blitEncoder.copy(from: colorTex, sourceSlice: 0, sourceLevel: 0,
                     sourceOrigin: MTLOrigin(x: pixelX, y: pixelY, z: 0),
                     sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                     to: stagingBuffer, destinationOffset: 0,
                     destinationBytesPerRow: 4, destinationBytesPerImage: 4)
    blitEncoder.endEncoding()
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    let pixelValue = stagingBuffer.contents().load(as: UInt32.self)
    let result: Int32 = pixelValue == 0 ? -1 : Int32(bitPattern: pixelValue) - 1
    Swift.print("pickObject: pixelValue=\(pixelValue) result=\(result)")
    return result
  }
  
  @objc func updateSelectionStateBuffer(_ data: Data) {
    selectionStateCount = data.count / MemoryLayout<Float>.size
    guard selectionStateCount > 0 else {
      selectionStateBuffer = nil
      return
    }
    if selectionStateBuffer?.length ?? 0 >= data.count {
      data.withUnsafeBytes { ptr in
        selectionStateBuffer!.contents().copyMemory(from: ptr.baseAddress!, byteCount: data.count)
      }
    } else {
      selectionStateBuffer = data.withUnsafeBytes { ptr in
        device!.makeBuffer(bytes: ptr.baseAddress!, length: data.count, options: [])
      }
    }
  }
  
  func new() {
    
    triangleBuffers.removeAll()
    edgeBuffers.removeAll()
    
    fieldOfView = 1.047197551196598
    
    modelTranslationToCentreOfRotationMatrix = matrix_identity_float4x4
    modelRotationMatrix = matrix_identity_float4x4
    modelShiftBackMatrix = matrix4x4_translation(shift: centre)
    modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
    viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: SIMD3<Float>(0.0, 1.0, 0.0))
    projectionMatrix = matrix4x4_perspective(fieldOfView: fieldOfView, aspectRatio: Float(bounds.size.width / bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    
    needsDisplay = true
  }
  
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let acceptedFileTypes: Set = ["gml", "xml", "json", "jsonl", "obj", "off", "poly"]
    if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL] {
      for url in urls {
        if acceptedFileTypes.contains(url.pathExtension) {
          return .copy
        }
      }
    }
    return [];
  }
  
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL] {
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
