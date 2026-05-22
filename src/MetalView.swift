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

@objc class MetalView: MTKView {
  
  var controller: Controller?
  var dataManager: DataManagerWrapperWrapper?
  
  var commandQueue: MTLCommandQueue?
  var litRenderPipelineState: MTLRenderPipelineState?
  var texturedRenderPipelineState: MTLRenderPipelineState?
  var unlitRenderPipelineState: MTLRenderPipelineState?
  var edgeRenderPipelineState: MTLRenderPipelineState?
  var depthStencilState: MTLDepthStencilState?
  var textureSamplerState: MTLSamplerState?
  var textureLoader: MTKTextureLoader?
  var loadedTextures = [String: MTLTexture]()
  var failedTexturePaths = Set<String>()
  var permissionDeniedTextureDirectories = Set<String>()
  var loggedTextureFailureCount: Int = 0
  let maxLoggedTextureFailures: Int = 40
  
  var msaaTexture: MTLTexture?
  var msaaDepthTexture: MTLTexture?
  
  var triangleBuffers = [BufferWithColour]()
  var edgeBuffers = [BufferWithColour]()
  var boundingBoxBuffer: MTLBuffer?
  var selectionStateBuffer: MTLBuffer?
  var selectionStateCount: Int = 0
  var visibleStateBuffer: MTLBuffer?
  var visibleStateCount: Int = 0
  
  var pickingRenderPipelineState: MTLRenderPipelineState?
  var pickingTexture: MTLTexture?
  var pickingDepthTexture: MTLTexture?

  var exportLitRenderPipelineState: MTLRenderPipelineState?
  var exportTexturedRenderPipelineState: MTLRenderPipelineState?
  var exportUnlitRenderPipelineState: MTLRenderPipelineState?
  var exportEdgeRenderPipelineState: MTLRenderPipelineState?
  
  @objc var showTextures: Bool = false {
    didSet { needsDisplay = true }
  }
  
  var viewEdges: Bool = true
  var viewBoundingBox: Bool = false
  var selectionColour: SIMD4<Float> = SIMD4<Float>(1.0, 1.0, 0.0, 0.7) {
    didSet {
      constants.selectionColour = selectionColour
      needsDisplay = true
    }
  }
  var library: MTLLibrary?
  var customLightClearColor: NSColor? {
    didSet { updateAppearance() }
  }
  var customDarkClearColor: NSColor? {
    didSet { updateAppearance() }
  }
  @objc var msaaSampleCount: Int = 4 {
    didSet {
      guard msaaSampleCount != oldValue else { return }
      sampleCount = msaaSampleCount
      createMSAATextures(size: drawableSize)
      recreatePipelines()
      needsDisplay = true
    }
  }
  
  @objc var multipleSelection: Bool {
    NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift)
  }
  var dragOverlay: CAShapeLayer?
  
  var isDarkMode: Bool {
    effectiveAppearance.name.rawValue.contains("Dark")
  }
  
  func updateAppearance() {
    if isDarkMode {
      if let custom = customDarkClearColor, let srgb = custom.usingColorSpace(.sRGB) {
        clearColor = MTLClearColorMake(Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent), 1.0)
      } else {
        let bg = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
        clearColor = MTLClearColorMake(Double(bg.redComponent), Double(bg.greenComponent), Double(bg.blueComponent), 1.0)
      }
    } else {
      if let custom = customLightClearColor, let srgb = custom.usingColorSpace(.sRGB) {
        clearColor = MTLClearColorMake(Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent), 1.0)
      } else {
        clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0)
      }
    }
    needsDisplay = true
  }
  
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
    colorPixelFormat = .bgra8Unorm
    depthStencilPixelFormat = .depth32Float
    self.sampleCount = 4
    
    // Command queue
    commandQueue = device!.makeCommandQueue()
    
    // Store library
    library = device!.makeDefaultLibrary()
    textureLoader = MTKTextureLoader(device: device!)
    textureSamplerState = buildTextureSamplerState()
    
    // Build pipelines
    recreatePipelines()
    
    // Cache compiled pipeline states as a binary archive for faster launches
    cachePipelineArchive()
    
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
    projectionMatrix = matrix4x4_perspective_shorter_dim(fieldOfView: fieldOfView, width: Float(bounds.size.width), height: Float(bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    
    // Initial appearance
    updateAppearance()
    
    // Allow dragging
    registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
    
    // Drag-and-drop visual overlay
    let overlay = CAShapeLayer()
    overlay.frame = bounds
    overlay.path = CGPath(rect: bounds, transform: nil)
    overlay.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.4).cgColor
    overlay.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.05).cgColor
    overlay.lineWidth = 3
    overlay.lineDashPattern = [10, 8]
    overlay.isHidden = true
    layer?.addSublayer(overlay)
    dragOverlay = overlay
    
    self.isPaused = true
    self.enableSetNeedsDisplay = true
  }
  
  func recreatePipelines() {
    guard let library = library, let device = device else { return }

    let fileManager = FileManager.default
    let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("azul", isDirectory: true)
    let archiveURL = appSupportURL.appendingPathComponent("azul.metalar")
    let archive: MTLBinaryArchive?
    if fileManager.fileExists(atPath: archiveURL.path) {
      let archiveDescriptor = MTLBinaryArchiveDescriptor()
      archiveDescriptor.url = archiveURL
      archive = try? device.makeBinaryArchive(descriptor: archiveDescriptor)
      if archive != nil {
        Swift.print("Loaded binary archive from \(archiveURL.path)")
      }
    } else {
      archive = nil
    }

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
    litPipelineDescriptor.rasterSampleCount = msaaSampleCount

    let texturedPipelineDescriptor = MTLRenderPipelineDescriptor()
    texturedPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexLitTextured")
    texturedPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentLitTextured")
    texturedPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
    texturedPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
    texturedPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    texturedPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    texturedPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    texturedPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    texturedPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    texturedPipelineDescriptor.rasterSampleCount = msaaSampleCount

    let unlitPipelineDescriptor = MTLRenderPipelineDescriptor()
    unlitPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexUnlit")
    unlitPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentUnlit")
    unlitPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
    unlitPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
    unlitPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    unlitPipelineDescriptor.rasterSampleCount = msaaSampleCount

    let edgePipelineDescriptor = MTLRenderPipelineDescriptor()
    edgePipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexEdge")
    edgePipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentEdge")
    edgePipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
    edgePipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
    edgePipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    edgePipelineDescriptor.rasterSampleCount = msaaSampleCount

    if let archive = archive {
      litPipelineDescriptor.binaryArchives = [archive]
      texturedPipelineDescriptor.binaryArchives = [archive]
      unlitPipelineDescriptor.binaryArchives = [archive]
      edgePipelineDescriptor.binaryArchives = [archive]
    }

    do {
      litRenderPipelineState = try device.makeRenderPipelineState(descriptor: litPipelineDescriptor)
      texturedRenderPipelineState = try device.makeRenderPipelineState(descriptor: texturedPipelineDescriptor)
      unlitRenderPipelineState = try device.makeRenderPipelineState(descriptor: unlitPipelineDescriptor)
      edgeRenderPipelineState = try device.makeRenderPipelineState(descriptor: edgePipelineDescriptor)
    } catch {
      Swift.print("Unable to compile render pipeline states: \(error)")
    }

    let pickingPipelineDescriptor = MTLRenderPipelineDescriptor()
    pickingPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexPicking")
    pickingPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentPicking")
    pickingPipelineDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
    pickingPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    pickingPipelineDescriptor.rasterSampleCount = 1
    if let archive = archive {
      pickingPipelineDescriptor.binaryArchives = [archive]
    }
    do {
      pickingRenderPipelineState = try device.makeRenderPipelineState(descriptor: pickingPipelineDescriptor)
    } catch {
      Swift.print("Unable to compile picking pipeline state: \(error)")
    }

    let exportLitDesc = MTLRenderPipelineDescriptor()
    exportLitDesc.vertexFunction = library.makeFunction(name: "vertexLit")
    exportLitDesc.fragmentFunction = library.makeFunction(name: "fragmentLit")
    exportLitDesc.colorAttachments[0].pixelFormat = .rgba8Unorm
    exportLitDesc.colorAttachments[0].isBlendingEnabled = true
    exportLitDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    exportLitDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    exportLitDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    exportLitDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    exportLitDesc.depthAttachmentPixelFormat = depthStencilPixelFormat
    exportLitDesc.rasterSampleCount = sampleCount

    let exportUnlitDesc = MTLRenderPipelineDescriptor()
    exportUnlitDesc.vertexFunction = library.makeFunction(name: "vertexUnlit")
    exportUnlitDesc.fragmentFunction = library.makeFunction(name: "fragmentUnlit")
    exportUnlitDesc.colorAttachments[0].pixelFormat = .rgba8Unorm
    exportUnlitDesc.colorAttachments[0].isBlendingEnabled = false
    exportUnlitDesc.depthAttachmentPixelFormat = depthStencilPixelFormat
    exportUnlitDesc.rasterSampleCount = sampleCount

    let exportEdgeDesc = MTLRenderPipelineDescriptor()
    exportEdgeDesc.vertexFunction = library.makeFunction(name: "vertexEdge")
    exportEdgeDesc.fragmentFunction = library.makeFunction(name: "fragmentEdge")
    exportEdgeDesc.colorAttachments[0].pixelFormat = .rgba8Unorm
    exportEdgeDesc.colorAttachments[0].isBlendingEnabled = false
    exportEdgeDesc.depthAttachmentPixelFormat = depthStencilPixelFormat
    exportEdgeDesc.rasterSampleCount = sampleCount

    let exportTexturedDesc = MTLRenderPipelineDescriptor()
    exportTexturedDesc.vertexFunction = library.makeFunction(name: "vertexLitTextured")
    exportTexturedDesc.fragmentFunction = library.makeFunction(name: "fragmentLitTextured")
    exportTexturedDesc.colorAttachments[0].pixelFormat = .rgba8Unorm
    exportTexturedDesc.colorAttachments[0].isBlendingEnabled = true
    exportTexturedDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    exportTexturedDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    exportTexturedDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    exportTexturedDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    exportTexturedDesc.depthAttachmentPixelFormat = depthStencilPixelFormat
    exportTexturedDesc.rasterSampleCount = sampleCount

    if let archive = archive {
      exportLitDesc.binaryArchives = [archive]
      exportTexturedDesc.binaryArchives = [archive]
      exportUnlitDesc.binaryArchives = [archive]
      exportEdgeDesc.binaryArchives = [archive]
    }

    do {
      exportLitRenderPipelineState = try device.makeRenderPipelineState(descriptor: exportLitDesc)
      exportTexturedRenderPipelineState = try device.makeRenderPipelineState(descriptor: exportTexturedDesc)
      exportUnlitRenderPipelineState = try device.makeRenderPipelineState(descriptor: exportUnlitDesc)
      exportEdgeRenderPipelineState = try device.makeRenderPipelineState(descriptor: exportEdgeDesc)
    } catch {
      Swift.print("Unable to compile export pipeline states: \(error)")
    }
  }

  func cachePipelineArchive() {
    guard let library = library, let device = device else { return }

    let fileManager = FileManager.default
    let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("azul", isDirectory: true)
    let archiveURL = appSupportURL.appendingPathComponent("azul.metalar")
    guard !fileManager.fileExists(atPath: archiveURL.path) else { return }

    do {
      try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    } catch {
      Swift.print("Could not create archive directory: \(error)")
      return
    }

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
    litPipelineDescriptor.rasterSampleCount = msaaSampleCount

    let texturedPipelineDescriptor = MTLRenderPipelineDescriptor()
    texturedPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexLitTextured")
    texturedPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentLitTextured")
    texturedPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
    texturedPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
    texturedPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    texturedPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    texturedPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    texturedPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    texturedPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    texturedPipelineDescriptor.rasterSampleCount = msaaSampleCount

    let unlitPipelineDescriptor = MTLRenderPipelineDescriptor()
    unlitPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexUnlit")
    unlitPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentUnlit")
    unlitPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
    unlitPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
    unlitPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
    unlitPipelineDescriptor.rasterSampleCount = msaaSampleCount

    do {
      let archive = try device.makeBinaryArchive(descriptor: MTLBinaryArchiveDescriptor())
      var allSucceeded = true

      do {
        try archive.addRenderPipelineFunctions(descriptor: litPipelineDescriptor)
      } catch {
        Swift.print("Failed to cache lit pipeline: \(error)")
        allSucceeded = false
      }
      do {
        try archive.addRenderPipelineFunctions(descriptor: texturedPipelineDescriptor)
      } catch {
        Swift.print("Failed to cache textured pipeline: \(error)")
        allSucceeded = false
      }
      do {
        try archive.addRenderPipelineFunctions(descriptor: unlitPipelineDescriptor)
      } catch {
        Swift.print("Failed to cache unlit pipeline: \(error)")
        allSucceeded = false
      }
      if let pickFunction = library.makeFunction(name: "pick") {
        let pickDesc = MTLComputePipelineDescriptor()
        pickDesc.computeFunction = pickFunction
        do {
          try archive.addComputePipelineFunctions(descriptor: pickDesc)
        } catch {
          Swift.print("Failed to cache pick compute pipeline: \(error)")
          allSucceeded = false
        }
      }

      if allSucceeded {
        try archive.serialize(to: archiveURL)
        Swift.print("Cached binary archive to \(archiveURL.path)")
      } else {
        Swift.print("Binary archive not saved due to previous errors")
      }
    } catch {
      Swift.print("Failed to create binary archive: \(error)")
    }
  }

  func buildTextureSamplerState() -> MTLSamplerState? {
    let descriptor = MTLSamplerDescriptor()
    descriptor.minFilter = .linear
    descriptor.magFilter = .linear
    descriptor.mipFilter = .linear
    descriptor.sAddressMode = .repeat
    descriptor.tAddressMode = .repeat
    descriptor.normalizedCoordinates = true
    return device?.makeSamplerState(descriptor: descriptor)
  }

  func textureURL(from path: String) -> URL? {
    if path.isEmpty { return nil }
    if let url = URL(string: path), url.scheme != nil {
      return url
    }
    return URL(fileURLWithPath: path)
  }

  func logTextureFailure(_ message: String) {
    if loggedTextureFailureCount < maxLoggedTextureFailures {
      Swift.print(message)
    } else if loggedTextureFailureCount == maxLoggedTextureFailures {
      Swift.print("Texture load failed: additional failures suppressed.")
    }
    loggedTextureFailureCount += 1
  }

  func errorIndicatesPermissionDenied(_ error: NSError) -> Bool {
    if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError { return true }
    if error.domain == NSURLErrorDomain && error.code == NSURLErrorNoPermissionsToReadFile { return true }
    if error.localizedDescription.localizedCaseInsensitiveContains("permission") { return true }
    if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
      return errorIndicatesPermissionDenied(underlyingError)
    }
    return false
  }

  func recordPermissionDeniedDirectory(for textureURL: URL, error: Error) {
    guard textureURL.isFileURL else { return }
    if errorIndicatesPermissionDenied(error as NSError) {
      permissionDeniedTextureDirectories.insert(textureURL.deletingLastPathComponent().path)
    }
  }

  func textureForPath(_ texturePath: String) -> MTLTexture? {
    if let loaded = loadedTextures[texturePath] { return loaded }
    if failedTexturePaths.contains(texturePath) { return nil }
    guard let loader = textureLoader,
          let textureURL = textureURL(from: texturePath) else {
      let wasNewFailure = failedTexturePaths.insert(texturePath).inserted
      if wasNewFailure { logTextureFailure("Texture load failed (\(texturePath)): invalid texture path") }
      return nil
    }
    do {
      let options: [MTKTextureLoader.Option: Any] = [
        .origin: MTKTextureLoader.Origin.bottomLeft,
        .SRGB: false,
        .generateMipmaps: true
      ]
      let loaded = try loader.newTexture(URL: textureURL, options: options)
      loadedTextures[texturePath] = loaded
      return loaded
    } catch {
      let wasNewFailure = failedTexturePaths.insert(texturePath).inserted
      if wasNewFailure {
        recordPermissionDeniedDirectory(for: textureURL, error: error)
        logTextureFailure("Texture load failed (\(texturePath)): \(error.localizedDescription)")
      }
      return nil
    }
  }

  @objc func clearFailedTexturePaths() {
    failedTexturePaths.removeAll()
    permissionDeniedTextureDirectories.removeAll()
    loggedTextureFailureCount = 0
  }

  @objc func consumePermissionDeniedTextureDirectories() -> [String] {
    let directories = Array(permissionDeniedTextureDirectories).sorted()
    permissionDeniedTextureDirectories.removeAll()
    return directories
  }

  @objc func failedTextureDirectories() -> [String] {
    let directories: Set<String> = Set<String>(failedTexturePaths.compactMap { texturePath in
      guard let textureURL = textureURL(from: texturePath), textureURL.isFileURL else { return nil }
      return textureURL.deletingLastPathComponent().path
    })
    return Array(directories).sorted()
  }

  @objc func primeTexturesForCurrentBuffers() {
    for i in triangleBuffers.indices where !triangleBuffers[i].texturePath.isEmpty {
      triangleBuffers[i].texture = textureForPath(triangleBuffers[i].texturePath)
    }
  }

  @objc func clearTextureCaches() {
    loadedTextures.removeAll()
    clearFailedTexturePaths()
  }

  func createPickingTextures() {
    let w = Int(drawableSize.width)
    let h = Int(drawableSize.height)
    guard w > 0, h > 0 else { return }
    
    let desc = MTLTextureDescriptor()
    desc.pixelFormat = .rgba8Unorm
    desc.width = w
    desc.height = h
    desc.storageMode = .private
    desc.usage = [.renderTarget, .shaderRead]
    pickingTexture = device!.makeTexture(descriptor: desc)
    
    let depthDesc = MTLTextureDescriptor()
    depthDesc.pixelFormat = depthStencilPixelFormat
    depthDesc.width = w
    depthDesc.height = h
    depthDesc.storageMode = .private
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
  
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateAppearance()
  }

  override func viewDidChangeEffectiveAppearance() {
    updateAppearance()
  }
  
  func createMSAATextures(size: CGSize) {
    let w = Int(size.width)
    let h = Int(size.height)
    guard w > 0, h > 0 else { return }
    
    if sampleCount > 1 {
      let desc = MTLTextureDescriptor()
      desc.pixelFormat = colorPixelFormat
      desc.width = w
      desc.height = h
      desc.textureType = .type2DMultisample
      desc.sampleCount = sampleCount
      desc.storageMode = .private
      desc.usage = .renderTarget
      msaaTexture = device!.makeTexture(descriptor: desc)
      
      let depthDesc = MTLTextureDescriptor()
      depthDesc.pixelFormat = depthStencilPixelFormat
      depthDesc.width = w
      depthDesc.height = h
      depthDesc.textureType = .type2DMultisample
      depthDesc.sampleCount = sampleCount
      depthDesc.storageMode = .private
      depthDesc.usage = .renderTarget
      msaaDepthTexture = device!.makeTexture(descriptor: depthDesc)
    } else {
      msaaTexture = nil
      msaaDepthTexture = nil
    }
  }
  
  override func draw(_ dirtyRect: NSRect) {
//    Swift.print("MetalView.draw(NSRect)")
    
    if dirtyRect.width == 0 {
      return
    }
    
    let commandBuffer = commandQueue!.makeCommandBuffer()!
    let renderPassDescriptor = MTLRenderPassDescriptor()
    if sampleCount > 1 {
      guard let msaaTex = msaaTexture, let msaaDepthTex = msaaDepthTexture else { return }
      renderPassDescriptor.colorAttachments[0].texture = msaaTex
      renderPassDescriptor.colorAttachments[0].resolveTexture = currentDrawable!.texture
      renderPassDescriptor.colorAttachments[0].storeAction = .multisampleResolve
      renderPassDescriptor.depthAttachment.texture = msaaDepthTex
      renderPassDescriptor.depthAttachment.storeAction = .dontCare
    } else {
      renderPassDescriptor.colorAttachments[0].texture = currentDrawable!.texture
      renderPassDescriptor.colorAttachments[0].storeAction = .store
      renderPassDescriptor.depthAttachment.texture = depthStencilTexture
      renderPassDescriptor.depthAttachment.storeAction = .dontCare
    }
    renderPassDescriptor.colorAttachments[0].clearColor = clearColor
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    renderPassDescriptor.depthAttachment.clearDepth = 1.0
    renderPassDescriptor.depthAttachment.loadAction = .clear
    let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    
    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.setDepthStencilState(depthStencilState)
    
    if let selBuffer = selectionStateBuffer, selectionStateCount > 0 {
      renderEncoder.setFragmentBuffer(selBuffer, offset: 0, index: 2)
    } else {
      var zero: Float = 0
      renderEncoder.setFragmentBytes(&zero, length: MemoryLayout<Float>.size, index: 2)
    }
    if let visBuffer = visibleStateBuffer, visibleStateCount > 0 {
      renderEncoder.setFragmentBuffer(visBuffer, offset: 0, index: 3)
    } else {
      var one: Float = 1
      renderEncoder.setFragmentBytes(&one, length: MemoryLayout<Float>.size, index: 3)
    }

    let drawVertices: (BufferWithColour) -> Void = { triangleBuffer in
      renderEncoder.setVertexBuffer(triangleBuffer.buffer, offset:0, index:0)
      self.constants.colour = triangleBuffer.colour
      renderEncoder.setVertexBytes(&self.constants, length: MemoryLayout<Constants>.size, index: 1)
      renderEncoder.setFragmentBytes(&self.constants, length: MemoryLayout<Constants>.size, index: 0)
      renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: triangleBuffer.indexCount, indexType: .uint32, indexBuffer: triangleBuffer.indexBuffer, indexBufferOffset: 0)
    }

    func drawPass(where opacityCondition: (Float) -> Bool) {
      if self.showTextures, let texturedPipeline = self.texturedRenderPipelineState {
        renderEncoder.setRenderPipelineState(texturedPipeline)
        for i in triangleBuffers.indices where opacityCondition(triangleBuffers[i].colour.w) && !triangleBuffers[i].texturePath.isEmpty {
          if triangleBuffers[i].texture == nil {
            triangleBuffers[i].texture = self.textureForPath(triangleBuffers[i].texturePath)
          }
          if let texture = triangleBuffers[i].texture {
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.setFragmentSamplerState(self.textureSamplerState, index: 0)
            drawVertices(triangleBuffers[i])
          }
        }
      }
      renderEncoder.setRenderPipelineState(self.litRenderPipelineState!)
      renderEncoder.setFragmentTexture(nil, index: 0)
      for i in triangleBuffers.indices where opacityCondition(triangleBuffers[i].colour.w) && (!self.showTextures || triangleBuffers[i].texturePath.isEmpty || triangleBuffers[i].texture == nil) {
        drawVertices(triangleBuffers[i])
      }
    }

    drawPass { $0 == 1.0 }
    drawPass { $0 != 1.0 }
    
    if viewEdges {
      renderEncoder.setRenderPipelineState(edgeRenderPipelineState!)
      if let visBuffer = visibleStateBuffer, visibleStateCount > 0 {
        renderEncoder.setFragmentBuffer(visBuffer, offset: 0, index: 2)
      } else {
        var one: Float = 1
        renderEncoder.setFragmentBytes(&one, length: MemoryLayout<Float>.size, index: 2)
      }
      for edgeBuffer in edgeBuffers {
        renderEncoder.setVertexBuffer(edgeBuffer.buffer, offset:0, index:0)
        var edgeColour = edgeBuffer.colour
        if isDarkMode && edgeColour.x == 0 && edgeColour.y == 0 && edgeColour.z == 0 {
          edgeColour = SIMD4<Float>(1, 1, 1, 1)
        }
        constants.colour = edgeColour
        renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
        renderEncoder.setFragmentBytes(&constants, length: MemoryLayout<Constants>.size, index: 0)
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: edgeBuffer.buffer.length/MemoryLayout<EdgeVertex>.size)
      }
      renderEncoder.setRenderPipelineState(unlitRenderPipelineState!)
    }
    
    if viewBoundingBox && boundingBoxBuffer != nil {
      renderEncoder.setVertexBuffer(boundingBoxBuffer, offset:0, index:0)
      constants.colour = isDarkMode ? SIMD4<Float>(1.0, 1.0, 1.0, 1.0) : SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
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
    
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dragOverlay?.frame = bounds
    dragOverlay?.path = CGPath(rect: bounds, transform: nil)
    CATransaction.commit()
    createMSAATextures(size: drawableSize)
    createPickingTextures()
    projectionMatrix = matrix4x4_perspective_shorter_dim(fieldOfView: fieldOfView, width: Float(bounds.size.width), height: Float(bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    needsDisplay = true
    if let statusBar = controller?.statusBarView {
      let barInset: CGFloat = 8
      let barWidth = self.frame.width - barInset * 2
      statusBar.frame = NSRect(x: barInset, y: barInset, width: barWidth, height: 36)
      controller?.progressIndicator?.frame = NSRect(x: 8, y: 12, width: barWidth - 196, height: 12)
      controller?.statusTextField?.frame = NSRect(x: barWidth - 188, y: 11, width: 180, height: 14)
    }
  }
  
  @objc func depthAtCentre() -> Float {
    
    let firstMinCoordinate = dataManager!.minCoordinates()
    let minCoordinatesBuffer = UnsafeBufferPointer(start: firstMinCoordinate, count: 3)
    let minCoordinatesArray = ContiguousArray(minCoordinatesBuffer)
    let minCoordinates = [Double](minCoordinatesArray)
    let firstMidCoordinate = dataManager!.midCoordinates()
    let midCoordinatesBuffer = UnsafeBufferPointer(start: firstMidCoordinate, count: 3)
    let midCoordinatesArray = ContiguousArray(midCoordinatesBuffer)
    let midCoordinates = [Double](midCoordinatesArray)
    let firstMaxCoordinate = dataManager!.maxCoordinates()
    let maxCoordinatesBuffer = UnsafeBufferPointer(start: firstMaxCoordinate, count: 3)
    let maxCoordinatesArray = ContiguousArray(maxCoordinatesBuffer)
    let maxCoordinates = [Double](maxCoordinatesArray)
    let maxRange = dataManager!.maxRange()
    let minCoords = minCoordinates.map(Float.init)
    let midCoords = midCoordinates.map(Float.init)
    let maxCoords = maxCoordinates.map(Float.init)
    let range = Float(maxRange)

    // Create three points along the data plane
    let leftUpPointInObjectCoordinates = SIMD4<Float>((minCoords[0]-midCoords[0])/range, (maxCoords[1]-midCoords[1])/range, 0.0, 1.0)
    let rightUpPointInObjectCoordinates = SIMD4<Float>((maxCoords[0]-midCoords[0])/range, (maxCoords[1]-midCoords[1])/range, 0.0, 1.0)
    let centreDownPointInObjectCoordinates = SIMD4<Float>(0.0, (minCoords[1]-midCoords[1])/range, 0.0, 1.0)

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
    projectionMatrix = matrix4x4_perspective_shorter_dim(fieldOfView: fieldOfView, width: Float(bounds.size.width), height: Float(bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
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
    projectionMatrix = matrix4x4_perspective_shorter_dim(fieldOfView: fieldOfView, width: Float(bounds.size.width), height: Float(bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
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
    projectionMatrix = matrix4x4_perspective_shorter_dim(fieldOfView: fieldOfView, width: Float(bounds.size.width), height: Float(bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
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
    if let visBuffer = visibleStateBuffer, visibleStateCount > 0 {
      encoder.setFragmentBuffer(visBuffer, offset: 0, index: 2)
    } else {
      var one: Float = 1
      encoder.setFragmentBytes(&one, length: MemoryLayout<Float>.size, index: 2)
    }
    
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
  
  @objc func exportImage(width: Int, height: Int, transparentBackground: Bool) -> NSImage? {
    guard !triangleBuffers.isEmpty else { return nil }
    guard width > 0, height > 0 else { return nil }
    guard let litPSO = exportLitRenderPipelineState,
          let texturedPSO = exportTexturedRenderPipelineState,
          let unlitPSO = exportUnlitRenderPipelineState,
          let edgePSO = exportEdgeRenderPipelineState else { return nil }

    let texDesc = MTLTextureDescriptor()
    texDesc.pixelFormat = .rgba8Unorm
    texDesc.width = width
    texDesc.height = height
    texDesc.storageMode = .private
    texDesc.usage = [.renderTarget, .shaderRead]
    guard let exportTexture = device!.makeTexture(descriptor: texDesc) else { return nil }

    let commandBuffer = commandQueue!.makeCommandBuffer()!
    let renderPassDescriptor = MTLRenderPassDescriptor()
    if sampleCount > 1 {
      let msaaDesc = MTLTextureDescriptor()
      msaaDesc.pixelFormat = .rgba8Unorm
      msaaDesc.width = width
      msaaDesc.height = height
      msaaDesc.textureType = .type2DMultisample
      msaaDesc.sampleCount = sampleCount
      msaaDesc.storageMode = .private
      msaaDesc.usage = .renderTarget
      guard let exportMSAATexture = device!.makeTexture(descriptor: msaaDesc) else { return nil }

      let msaaDepthDesc = MTLTextureDescriptor()
      msaaDepthDesc.pixelFormat = depthStencilPixelFormat
      msaaDepthDesc.width = width
      msaaDepthDesc.height = height
      msaaDepthDesc.textureType = .type2DMultisample
      msaaDepthDesc.sampleCount = sampleCount
      msaaDepthDesc.storageMode = .private
      msaaDepthDesc.usage = .renderTarget
      guard let exportMSAADepthTexture = device!.makeTexture(descriptor: msaaDepthDesc) else { return nil }

      renderPassDescriptor.colorAttachments[0].texture = exportMSAATexture
      renderPassDescriptor.colorAttachments[0].resolveTexture = exportTexture
      renderPassDescriptor.colorAttachments[0].storeAction = .multisampleResolve
      renderPassDescriptor.depthAttachment.texture = exportMSAADepthTexture
      renderPassDescriptor.depthAttachment.storeAction = .dontCare
    } else {
      renderPassDescriptor.colorAttachments[0].texture = exportTexture
      renderPassDescriptor.colorAttachments[0].storeAction = .store
      renderPassDescriptor.depthAttachment.texture = device!.makeTexture(descriptor: {
        let d = MTLTextureDescriptor()
        d.pixelFormat = depthStencilPixelFormat
        d.width = width
        d.height = height
        d.storageMode = .private
        d.usage = .renderTarget
        return d
      }())
      renderPassDescriptor.depthAttachment.storeAction = .dontCare
    }
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    if transparentBackground {
      renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    } else {
      renderPassDescriptor.colorAttachments[0].clearColor = clearColor
    }
    renderPassDescriptor.depthAttachment.loadAction = .clear
    renderPassDescriptor.depthAttachment.clearDepth = 1.0

    guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return nil }

    renderEncoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(width), height: Double(height), znear: 0, zfar: 1))
    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.setDepthStencilState(depthStencilState)
    if let selBuffer = selectionStateBuffer, selectionStateCount > 0 {
      renderEncoder.setFragmentBuffer(selBuffer, offset: 0, index: 2)
    } else {
      var zero: Float = 0
      renderEncoder.setFragmentBytes(&zero, length: MemoryLayout<Float>.size, index: 2)
    }
    if let visBuffer = visibleStateBuffer, visibleStateCount > 0 {
      renderEncoder.setFragmentBuffer(visBuffer, offset: 0, index: 3)
    } else {
      var one: Float = 1
      renderEncoder.setFragmentBytes(&one, length: MemoryLayout<Float>.size, index: 3)
    }

    let drawVertices: (BufferWithColour) -> Void = { triangleBuffer in
      renderEncoder.setVertexBuffer(triangleBuffer.buffer, offset: 0, index: 0)
      self.constants.colour = triangleBuffer.colour
      renderEncoder.setVertexBytes(&self.constants, length: MemoryLayout<Constants>.size, index: 1)
      renderEncoder.setFragmentBytes(&self.constants, length: MemoryLayout<Constants>.size, index: 0)
      renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: triangleBuffer.indexCount, indexType: .uint32, indexBuffer: triangleBuffer.indexBuffer, indexBufferOffset: 0)
    }

    func drawPass(where opacityCondition: (Float) -> Bool) {
      if self.showTextures {
        renderEncoder.setRenderPipelineState(texturedPSO)
        for i in triangleBuffers.indices where opacityCondition(triangleBuffers[i].colour.w) && !triangleBuffers[i].texturePath.isEmpty {
          if triangleBuffers[i].texture == nil {
            triangleBuffers[i].texture = self.textureForPath(triangleBuffers[i].texturePath)
          }
          if let texture = triangleBuffers[i].texture {
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.setFragmentSamplerState(self.textureSamplerState, index: 0)
            drawVertices(triangleBuffers[i])
          }
        }
      }
      renderEncoder.setRenderPipelineState(litPSO)
      renderEncoder.setFragmentTexture(nil, index: 0)
      for i in triangleBuffers.indices where opacityCondition(triangleBuffers[i].colour.w) && (!self.showTextures || triangleBuffers[i].texturePath.isEmpty || triangleBuffers[i].texture == nil) {
        drawVertices(triangleBuffers[i])
      }
    }

    drawPass { $0 == 1.0 }
    drawPass { $0 != 1.0 }

    if viewEdges {
      renderEncoder.setRenderPipelineState(edgePSO)
      if let visBuffer = visibleStateBuffer, visibleStateCount > 0 {
        renderEncoder.setFragmentBuffer(visBuffer, offset: 0, index: 2)
      } else {
        var one: Float = 1
        renderEncoder.setFragmentBytes(&one, length: MemoryLayout<Float>.size, index: 2)
      }
      for edgeBuffer in edgeBuffers {
        renderEncoder.setVertexBuffer(edgeBuffer.buffer, offset: 0, index: 0)
        var edgeColour = edgeBuffer.colour
        if isDarkMode && edgeColour.x == 0 && edgeColour.y == 0 && edgeColour.z == 0 {
          edgeColour = SIMD4<Float>(1, 1, 1, 1)
        }
        constants.colour = edgeColour
        renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
        renderEncoder.setFragmentBytes(&constants, length: MemoryLayout<Constants>.size, index: 0)
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: edgeBuffer.buffer.length / MemoryLayout<EdgeVertex>.size)
      }
      renderEncoder.setRenderPipelineState(unlitPSO)
    }

    if viewBoundingBox, let bb = boundingBoxBuffer {
      renderEncoder.setVertexBuffer(bb, offset: 0, index: 0)
      constants.colour = isDarkMode ? SIMD4<Float>(1.0, 1.0, 1.0, 1.0) : SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
      renderEncoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
      renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: bb.length / MemoryLayout<Vertex>.size)
    }

    renderEncoder.endEncoding()

    let bytesPerRow = width * 4
    let stagingBuffer = device!.makeBuffer(length: bytesPerRow * height, options: .storageModeShared)!
    let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
    blitEncoder.copy(from: exportTexture, sourceSlice: 0, sourceLevel: 0,
                     sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                     sourceSize: MTLSize(width: width, height: height, depth: 1),
                     to: stagingBuffer, destinationOffset: 0,
                     destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * height)
    blitEncoder.endEncoding()

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    let pixelData = Data(bytes: stagingBuffer.contents(), count: bytesPerRow * height)
    guard let provider = CGDataProvider(data: pixelData as CFData) else { return nil }
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let cgImage = CGImage(width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bitsPerPixel: 32,
                                bytesPerRow: bytesPerRow,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: bitmapInfo,
                                provider: provider,
                                decode: nil,
                                shouldInterpolate: false,
                                intent: .defaultIntent) else { return nil }

    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
  }

  @objc func updateVisibleStateBuffer(_ data: Data) {
    visibleStateCount = data.count / MemoryLayout<Float>.size
    guard visibleStateCount > 0 else {
      visibleStateBuffer = nil
      return
    }
    if visibleStateBuffer?.length ?? 0 >= data.count {
      data.withUnsafeBytes { ptr in
        visibleStateBuffer!.contents().copyMemory(from: ptr.baseAddress!, byteCount: data.count)
      }
    } else {
      visibleStateBuffer = data.withUnsafeBytes { ptr in
        device!.makeBuffer(bytes: ptr.baseAddress!, length: data.count, options: [])
      }
    }
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
    projectionMatrix = matrix4x4_perspective_shorter_dim(fieldOfView: fieldOfView, width: Float(bounds.size.width), height: Float(bounds.size.height), nearZ: 0.001, farZ: 100.0)
    
    constants.modelMatrix = modelMatrix
    constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
    constants.viewMatrixInverse = viewMatrix.inverse
    
    needsDisplay = true
  }
  
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let acceptedExtensions: Set = ["gml", "xml", "json", "jsonl", "obj", "off", "poly"]
    if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL] {
      for url in urls {
        if acceptedExtensions.contains(url.pathExtension) || url.lastPathComponent.hasSuffix(".city.json") {
          dragOverlay?.isHidden = false
          return .copy
        }
      }
    }
    return [];
  }
  
  override func draggingExited(_ sender: NSDraggingInfo?) {
    dragOverlay?.isHidden = true
  }
  
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    dragOverlay?.isHidden = true
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
      controller!.copySelectedObjectIds()
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
  
}
