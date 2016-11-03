//
//  OpenGLView.swift
//  Azul
//
//  Copyright © 2016 Ken Arroyo Ohori. All rights reserved.
//

import Cocoa
import OpenGL.GL3
import GLKit

class OpenGLView: NSOpenGLView {
  
  var controller: Controller?
  
  var displayLink: CVDisplayLink?
  
  var program: GLuint = 0
  
  var viewEdges: Bool = true
  var viewBoundingBox: Bool = false
  
  var vboBuildings: GLuint = 0
  var vboBuildingRoofs: GLuint = 0
  var vboRoads: GLuint = 0
  var vboWater: GLuint = 0
  var vboPlantCover: GLuint = 0
  var vboTerrain: GLuint = 0
  var vboGeneric: GLuint = 0
  var vboBridges: GLuint = 0
  var vboLandUse: GLuint = 0
  var vboEdges: GLuint = 0
  var vboBoundingBox: GLuint = 0
  
  var uniformColour: GLint = 0
  var uniformMVP: GLint = 0
  
  var attributeCoordinates: GLint = -1
  
  var eye: GLKVector3 = GLKVector3Make(0.0, 0.0, 0.0)
  var centre: GLKVector3 = GLKVector3Make(0.0, 0.0, 0.0)
  var fieldOfView: Float = 0.0
  
  var modelTranslationToCentreOfRotation = GLKMatrix4Identity
  var modelRotation = GLKMatrix4Identity
  var modelShiftBack = GLKMatrix4Identity
  
  var model: GLKMatrix4 = GLKMatrix4Identity
  var view: GLKMatrix4 = GLKMatrix4Identity
  var projection: GLKMatrix4 = GLKMatrix4Identity
  var mvp = GLKMatrix4Identity
  
  var transformArray: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  
  let buildingsColour: Array<GLfloat> = [1.0, 0.956862745098039, 0.690196078431373]
  let buildingRoofsColour: Array<GLfloat> = [0.882352941176471, 0.254901960784314, 0.219607843137255]
  let roadsColour: Array<GLfloat> = [0.458823529411765, 0.458823529411765, 0.458823529411765]
  let waterColour: Array<GLfloat> = [0.584313725490196, 0.917647058823529, 1.0]
  let plantCoverColour: Array<GLfloat> = [0.4, 0.882352941176471, 0.333333333333333]
  let terrainColour: Array<GLfloat> = [0.713725490196078, 0.882352941176471, 0.623529411764706]
  let genericColour: Array<GLfloat> = [0.7, 0.7, 0.7]
  let bridgeColour: Array<GLfloat> = [0.247058823529412, 0.247058823529412, 0.247058823529412]
  let landUseColour: Array<GLfloat> = [1.0, 0.0, 0.0]
  let edgesColour: Array<GLfloat> = [0.0, 0.0, 0.0]
  let boundingBoxColour: Array<GLfloat> = [0.0, 0.0, 0.0]
  
  var buildingsTriangles: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var buildingRoofsTriangles: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var roadsTriangles: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var waterTriangles: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var plantCoverTriangles: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var terrainTriangles: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var genericTriangles: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var bridgeTriangles: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var landUseTriangles: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var edges: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var boundingBox: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  
  required init?(coder: NSCoder) {
    Swift.print("OpenGLView.init?(NSCoder)")
    super.init(coder: coder)
    
    wantsBestResolutionOpenGLSurface = true
    
    let attributes: [NSOpenGLPixelFormatAttribute] = [
      UInt32(NSOpenGLPFAAccelerated),
      UInt32(NSOpenGLPFAColorSize), UInt32(24),
      UInt32(NSOpenGLPFADoubleBuffer),
      UInt32(NSOpenGLPFADepthSize), UInt32(32),
      UInt32(0)
    ]
    
    pixelFormat = NSOpenGLPixelFormat(attributes: attributes)
    openGLContext = NSOpenGLContext(format: pixelFormat!, share: nil)
    
    openGLContext!.setValues([1], for: NSOpenGLCPSwapInterval)
    
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
      self.controller!.loadData(from: urls)
    }
    return true
  }
  
  func createShader(name: String, type: GLenum) -> GLuint {
    var shader: GLuint = glCreateShader(type)
    let shaderPath = Bundle.main.path(forResource: name, ofType: "glsl")
    do {
      let shaderSource = try String(contentsOfFile: shaderPath!, encoding: String.Encoding.utf8).utf8CString
      shaderSource.withUnsafeBufferPointer { pointer in
        var shaderAddress: UnsafePointer<GLchar>? = pointer.baseAddress
        glShaderSource(shader, 1, &shaderAddress, nil)
        glCompileShader(shader)
        var shaderCompiledSuccessfully: GLint = GL_FALSE
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &shaderCompiledSuccessfully)
        if shaderCompiledSuccessfully == GL_FALSE {
          Swift.print("createShader: Couldn't compile shader")
          printLog(object: shader)
          glDeleteShader(shader)
          shader = 0
        }
      }
    } catch {
      
    }
    return shader
  }
  
  func printLog(object: GLuint) {
    var logLength: GLint = 0
    if glIsShader(object) != 0 {
      glGetShaderiv(object, GLenum(GL_INFO_LOG_LENGTH), &logLength)
    } else if glIsProgram(object) != 0 {
      glGetProgramiv(object, GLenum(GL_INFO_LOG_LENGTH), &logLength)
    } else {
      Swift.print("printLog: Not a shader or a program")
      return
    }
    
    let infoLog = UnsafeMutablePointer<GLchar>.allocate(capacity: Int(logLength))
    
    if glIsShader(object) != 0 {
      glGetShaderInfoLog(object, logLength, &logLength, infoLog)
    } else {
      glGetProgramInfoLog(object, logLength, &logLength, infoLog)
    }
    
    let infoLogString = String(cString: infoLog)
    Swift.print(infoLogString)
    infoLog.deallocate(capacity: Int(logLength))
  }
  
  override func prepareOpenGL() {
    Swift.print("OpenGLView.prepareOpenGL()")
    
    func displayLinkOutputCallback(displayLink: CVDisplayLink, _ now: UnsafePointer<CVTimeStamp>, _ outputTime: UnsafePointer<CVTimeStamp>, _ flagsIn: CVOptionFlags, _ flagsOut: UnsafeMutablePointer<CVOptionFlags>, _ displayLinkContext: UnsafeMutableRawPointer?) -> CVReturn {
      
      unsafeBitCast(displayLinkContext, to: OpenGLView.self).renderFrame()
      return kCVReturnSuccess
    }
    
    var linkedSuccessfully: GLint = 0
    
    let vertexShader: GLuint = createShader(name: "vertex", type: GLenum(GL_VERTEX_SHADER))
    let fragmentShader: GLuint = createShader(name: "fragment", type: GLenum(GL_FRAGMENT_SHADER))
    
    program = glCreateProgram()
    glAttachShader(program, vertexShader)
    glAttachShader(program, fragmentShader)
    glLinkProgram(program)
    glGetProgramiv(program, GLenum(GL_LINK_STATUS), &linkedSuccessfully)
    if linkedSuccessfully == 0 {
      Swift.print("prepareOpenGL: Couldn't link program")
      printLog(object: program)
    }
    
    var uniformName: String = "mvp"
    uniformName.utf8CString.withUnsafeBufferPointer { pointer in
      uniformMVP = glGetUniformLocation(program, pointer.baseAddress)
      if uniformMVP == -1 {
        Swift.print("prepareOpenGL: Couldn't bind uniformTransformation")
      }
    }
    
    uniformName = "v_color"
    uniformName.utf8CString.withUnsafeBufferPointer { pointer in
      uniformColour = glGetUniformLocation(program, pointer.baseAddress)
      if uniformColour == -1 {
        Swift.print("prepareOpenGL: Couldn't bind uniformColour")
      }
    }
    
    let attributeName: String = "coord3d"
    attributeName.utf8CString.withUnsafeBufferPointer { pointer in
      attributeCoordinates = glGetAttribLocation(program, pointer.baseAddress)
      if attributeCoordinates == -1 {
        Swift.print("prepareOpenGL: Couldn't bind attributeCoordinates")
      }
    }
    
    glGenBuffers(1, &vboBuildings)
    glGenBuffers(1, &vboBuildingRoofs)
    glGenBuffers(1, &vboRoads)
    glGenBuffers(1, &vboWater)
    glGenBuffers(1, &vboPlantCover)
    glGenBuffers(1, &vboTerrain)
    glGenBuffers(1, &vboGeneric)
    glGenBuffers(1, &vboBridges)
    glGenBuffers(1, &vboLandUse)
    glGenBuffers(1, &vboEdges)
    glGenBuffers(1, &vboBoundingBox)
    
    while glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("An error occurred in the initialisation of OpenGL")
    }
    
    glEnable(GLenum(GL_LINE_SMOOTH))
    glEnable(GLenum(GL_BLEND))
    glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA))
    glHint(GLenum(GL_LINE_SMOOTH_HINT), GLenum(GL_NICEST))
    glLineWidth(1.5)
    
    eye = GLKVector3Make(0.0, 0.0, 0.0)
    centre = GLKVector3Make(0.0, 0.0, -1.0)
    fieldOfView = 45.0
    
    modelTranslationToCentreOfRotation = GLKMatrix4Identity
    modelRotation = GLKMatrix4Identity
    modelShiftBack = GLKMatrix4MakeTranslation(centre.x, centre.y, centre.z)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
    view = GLKMatrix4MakeLookAt(eye.x, eye.y, eye.z, centre.x, centre.y, centre.z, 0.0, 1.0, 0.0)
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
    transformArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                      mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                      mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                      mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    transformArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformMVP, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
    CVDisplayLinkSetOutputCallback(displayLink!, displayLinkOutputCallback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
//    CVDisplayLinkStart(displayLink!)
  }
  
  override var acceptsFirstResponder: Bool {
    return true
  }
  
  override func mouseDragged(with event: NSEvent) {
//    Swift.print("OpenGLView.mouseDragged()")
    let currentX = -1.0 + 2.0*window!.mouseLocationOutsideOfEventStream.x / bounds.size.width
    let currentY = -1.0 + 2.0*window!.mouseLocationOutsideOfEventStream.y / bounds.size.height
    let currentZ = sqrt(1 - (currentX*currentX+currentY*currentY))
    let currentPosition = GLKVector3Normalize(GLKVector3(v: (Float(currentX), Float(currentY), Float(currentZ))))
//    Swift.print("Current position X: \(currentPosition.x) Y: \(currentPosition.y) Z: \(currentPosition.z)")
    let lastX = -1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.x-event.deltaX) / bounds.size.width
    let lastY = -1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.y+event.deltaY) / bounds.size.height
    let lastZ = sqrt(1 - (lastX*lastX+lastY*lastY))
    let lastPosition = GLKVector3Normalize(GLKVector3(v: (Float(lastX), Float(lastY), Float(lastZ))))
//    Swift.print("Last position X: \(lastPosition.x) Y: \(lastPosition.y) Z: \(lastPosition.z)")
    let angle = acos(GLKVector3DotProduct(lastPosition, currentPosition))
    if !angle.isNaN && angle > 0.0 {
//      Swift.print("Angle: \(angle)")
      let axisInCameraCoordinates: GLKVector3 = GLKVector3CrossProduct(lastPosition, currentPosition)
      var isInvertible: Bool = true
      let cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(model, view)), &isInvertible)
      let axisInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, axisInCameraCoordinates)
      modelRotation = GLKMatrix4RotateWithVector3(modelRotation, angle, axisInObjectCoordinates)
      model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
      mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
      transformArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                        mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                        mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                        mvp.m30, mvp.m31, mvp.m32, mvp.m33]
      renderFrame()
    } else {
//      Swift.print("NaN!")
    }
  }
  
  override func scrollWheel(with event: NSEvent) {
//    Swift.print("OpenGLView.scrollWheel()")
//    Swift.print("Scrolled X: \(event.scrollingDeltaX) Y: \(event.scrollingDeltaY)")
    let scrollingSensitivity: Float = 0.003
    var isInvertible: Bool = true
    let motionInCameraCoordinates: GLKVector3 = GLKVector3Make(scrollingSensitivity*Float(event.scrollingDeltaX), -scrollingSensitivity*Float(event.scrollingDeltaY), 0.0)
    let cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(model, view)), &isInvertible)
    let motionInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, motionInCameraCoordinates)
    modelTranslationToCentreOfRotation = GLKMatrix4TranslateWithVector3(modelTranslationToCentreOfRotation, motionInObjectCoordinates)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
    mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
    transformArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                      mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                      mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                      mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    renderFrame()
  }
  
  override func magnify(with event: NSEvent) {
//    Swift.print("OpenGLView.magnify()")
//    Swift.print("Pinched: \(event.magnification)")
//    let pinchSensitivity: Float = 0.01
//    var isInvertible: Bool = true
//    let motionInCameraCoordinates: GLKVector3 = GLKVector3Make(0.0, 0.0, pinchSensitivity*Float(event.magnification))
//    let cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(model, view)), &isInvertible)
//    let motionInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, motionInCameraCoordinates)
//    modelTranslation = GLKMatrix4TranslateWithVector3(modelTranslation, motionInObjectCoordinates)
//    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslation)
//    Swift.print("Field of view: \(fieldOfView)")
//    fieldOfView = fieldOfView - Float(event.magnification)
//    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
    transformArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                      mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                      mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                      mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    renderFrame()
  }
  
  override func keyDown(with event: NSEvent) {
    Swift.print(event.charactersIgnoringModifiers![(event.charactersIgnoringModifiers?.startIndex)!])
    
    switch event.charactersIgnoringModifiers![(event.charactersIgnoringModifiers?.startIndex)!] {
    case "b":
      controller!.toggleViewBoundingBox(controller!.toggleViewBoundingBoxMenuItem)
    case "e":
      controller!.toggleViewEdges(controller!.toggleViewEdgesMenuItem)
    case "t":
      testDepthAtCentre()
    default:
      break
    }
  }
  
  func testDepthAtCentre() {
    let firstMinCoordinate = controller!.cityGMLParser!.minCoordinates()
    let minCoordinatesBuffer = UnsafeBufferPointer(start: firstMinCoordinate, count: 3)
    var minCoordinates = ContiguousArray(minCoordinatesBuffer)
    let firstMidCoordinate = controller!.cityGMLParser!.midCoordinates()
    let midCoordinatesBuffer = UnsafeBufferPointer(start: firstMidCoordinate, count: 3)
    let midCoordinates = ContiguousArray(midCoordinatesBuffer)
    let firstMaxCoordinate = controller!.cityGMLParser!.maxCoordinates()
    let maxCoordinatesBuffer = UnsafeBufferPointer(start: firstMaxCoordinate, count: 3)
    var maxCoordinates = ContiguousArray(maxCoordinatesBuffer)
    let maxRange = controller!.cityGMLParser!.maxRange()
    
    for coordinate in 0..<3 {
      minCoordinates[coordinate] = (minCoordinates[coordinate]-midCoordinates[coordinate])/maxRange
      maxCoordinates[coordinate] = (maxCoordinates[coordinate]-midCoordinates[coordinate])/maxRange
    }
    
    let leftUpPointInObjectCoordinates = GLKVector4Make(minCoordinates[0], maxCoordinates[1], 0.0, 1.0)
    let rightUpPointInObjectCoordinates = GLKVector4Make(maxCoordinates[0], maxCoordinates[1], 0.0, 1.0)
    let centreDownPointInObjectCoordinates = GLKVector4Make(0.0, minCoordinates[1], 0.0, 1.0)
    
//    Swift.print("Left up: (\(leftUpPointInObjectCoordinates.x), \(leftUpPointInObjectCoordinates.y), \(leftUpPointInObjectCoordinates.z))")
//    Swift.print("Right up: (\(rightUpPointInObjectCoordinates.x), \(rightUpPointInObjectCoordinates.y), \(rightUpPointInObjectCoordinates.z))")
//    Swift.print("Centre down: (\(centreDownPointInObjectCoordinates.x), \(centreDownPointInObjectCoordinates.y), \(centreDownPointInObjectCoordinates.z))")
    
    let modelView = GLKMatrix4Multiply(view, model)
    
//    Swift.print("Model view matrix")
//    Swift.print("\(modelView.m00)\t\(modelView.m01)\t\(modelView.m02)\t\(modelView.m03)")
//    Swift.print("\(modelView.m10)\t\(modelView.m11)\t\(modelView.m12)\t\(modelView.m13)")
//    Swift.print("\(modelView.m20)\t\(modelView.m21)\t\(modelView.m22)\t\(modelView.m23)")
//    Swift.print("\(modelView.m30)\t\(modelView.m31)\t\(modelView.m32)\t\(modelView.m33)")
    
    let leftUpPoint = GLKMatrix4MultiplyVector4(modelView, leftUpPointInObjectCoordinates)
    let rightUpPoint = GLKMatrix4MultiplyVector4(modelView, rightUpPointInObjectCoordinates)
    let centreDownPoint = GLKMatrix4MultiplyVector4(modelView, centreDownPointInObjectCoordinates)
    
//    Swift.print("Left up: (\(leftUpPoint.x), \(leftUpPoint.y), \(leftUpPoint.z))")
//    Swift.print("Right up: (\(rightUpPoint.x), \(rightUpPoint.y), \(rightUpPoint.z))")
//    Swift.print("Centre down: (\(centreDownPoint.x), \(centreDownPoint.y), \(centreDownPoint.z))")
    
    let vector1 = GLKVector4Make(leftUpPoint.x-centreDownPoint.x, leftUpPoint.y-centreDownPoint.y, leftUpPoint.z-centreDownPoint.z, 1.0)
    let vector2 = GLKVector4Make(rightUpPoint.x-centreDownPoint.x, rightUpPoint.y-centreDownPoint.y, rightUpPoint.z-centreDownPoint.z, 1.0)
    let crossProduct = GLKVector4CrossProduct(vector1, vector2)
    
    // Plane equation passing through points: ax + bx + cy + d = 0
//    let a = crossProduct.x
//    let b = crossProduct.y
//    let c = crossProduct.z
    let d = -GLKVector4DotProduct(crossProduct, centreDownPoint)
    
    // -d/c = y
    Swift.print("Depth at centre: \(-d/crossProduct.z)")
  }
  
  override func reshape() {
//    Swift.print("OpenGLView.reshape()")
    super.reshape()
    glViewport(0, 0, GLsizei(bounds.size.width), GLsizei(bounds.size.height))
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
    transformArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                      mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                      mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                      mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    transformArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformMVP, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    update()
  }
  
  func renderFrame() {
//    Swift.print("OpenGLView.renderFrame()")
    
    openGLContext!.makeCurrentContext()
    CGLLockContext(openGLContext!.cglContextObj!)
    
    glClearColor(1.0, 1.0, 1.0, 1.0)
    glEnable(GLenum(GL_DEPTH_TEST))
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT) | GLbitfield(GL_DEPTH_BUFFER_BIT))
    
    glUseProgram(program)
    
    transformArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformMVP, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    
    glEnableVertexAttribArray(GLuint(attributeCoordinates))
    
    glUniform3f(uniformColour, buildingsColour[0], buildingsColour[1], buildingsColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboBuildings)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
    var size: GLsizei = 0
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) building triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering buildings: some error occurred!")
    }
    
    glUniform3f(uniformColour, buildingRoofsColour[0], buildingRoofsColour[1], buildingRoofsColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboBuildingRoofs)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) building roof triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering building roofs: some error occurred!")
    }
    
    glUniform3f(uniformColour, roadsColour[0], roadsColour[1], roadsColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboRoads)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) road triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering roads: some error occurred!")
    }
    
    glUniform3f(uniformColour, waterColour[0], waterColour[1], waterColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboWater)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) water triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering water bodies: some error occurred!")
    }
    
    glUniform3f(uniformColour, plantCoverColour[0], plantCoverColour[1], plantCoverColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboPlantCover)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) plant cover triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering plant cover: some error occurred!")
    }
    
    glUniform3f(uniformColour, terrainColour[0], terrainColour[1], terrainColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboTerrain)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) terrain triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering terrain: some error occurred!")
    }
    
    glUniform3f(uniformColour, genericColour[0], genericColour[1], genericColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboGeneric)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) generic triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering generic objects: some error occurred!")
    }
    
    glUniform3f(uniformColour, bridgeColour[0], bridgeColour[1], bridgeColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboBridges)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) bridge triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering bridges: some error occurred!")
    }
    
    glUniform3f(uniformColour, landUseColour[0], landUseColour[1], landUseColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboLandUse)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) land use triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering land use: some error occurred!")
    }
    
    if (viewEdges) {
      glUniform3f(uniformColour, edgesColour[0], edgesColour[1], edgesColour[2])
      glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboEdges)
      glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
      glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
  //    Swift.print("Drawing \(size/2) edges")
      glDrawArrays(GLenum(GL_LINES), 0, size)
      if glGetError() != GLenum(GL_NO_ERROR) {
        Swift.print("Rendering edges: some error occurred!")
      }
    }
    
    if (viewBoundingBox) {
      glUniform3f(uniformColour, boundingBoxColour[0], boundingBoxColour[1], boundingBoxColour[2])
      glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboBoundingBox)
      glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
      glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/2) bounding box edges")
      glDrawArrays(GLenum(GL_LINES), 0, size)
      if glGetError() != GLenum(GL_NO_ERROR) {
        Swift.print("Rendering bounding box: some error occurred!")
      }
    }
    
    glDisableVertexAttribArray(GLuint(attributeCoordinates))
    
    CGLFlushDrawable(openGLContext!.cglContextObj!)
    CGLUnlockContext(openGLContext!.cglContextObj!)
  }
  
  override func draw(_ dirtyRect: NSRect) {
//    Swift.print("OpenGLView.draw(NSRect)")
    super.draw(dirtyRect)
    renderFrame()
  }
  
  deinit {
    Swift.print("OpenGLView.deinit")
    
//    CVDisplayLinkStop(displayLink!)
    
    glDeleteProgram(program)
    glDeleteBuffers(1, &vboBuildings)
    glDeleteBuffers(1, &vboBuildingRoofs)
    glDeleteBuffers(1, &vboRoads)
    glDeleteBuffers(1, &vboWater)
    glDeleteBuffers(1, &vboPlantCover)
    glDeleteBuffers(1, &vboTerrain)
    glDeleteBuffers(1, &vboGeneric)
    glDeleteBuffers(1, &vboLandUse)
    glDeleteBuffers(1, &vboEdges)
    glDeleteBuffers(1, &vboBoundingBox)
  }
}
