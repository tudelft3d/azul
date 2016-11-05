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
  var vboSelectionFaces: GLuint = 0
  var vboSelectionEdges: GLuint = 0
  
  var uniformM: GLint = 0
  var uniformV: GLint = 0
  var uniformP: GLint = 0
  var uniformMIT: GLint = 0
  var uniformVI: GLint = 0
  var uniformColour: GLint = 0

  var attributeCoordinates: GLint = -1
  var attributeNormals: GLint = -1
  
  var eye: GLKVector3 = GLKVector3Make(0.0, 0.0, 0.0)
  var centre: GLKVector3 = GLKVector3Make(0.0, 0.0, 0.0)
  var fieldOfView: Float = 0.0
  
  var modelTranslationToCentreOfRotation = GLKMatrix4Identity
  var modelRotation = GLKMatrix4Identity
  var modelShiftBack = GLKMatrix4Identity
  
  var model: GLKMatrix4 = GLKMatrix4Identity
  var view: GLKMatrix4 = GLKMatrix4Identity
  var projection: GLKMatrix4 = GLKMatrix4Identity
//  var mvp = GLKMatrix4Identity
  
  var mArray: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var vArray: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var pArray: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var mitArray: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var viArray: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  
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
  let selectionFacesColour: Array<GLfloat> = [0.8, 0.8, 0.0]
  let selectionEdgesColour: Array<GLfloat> = [1.0, 1.0, 0.0]
  
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
  var selectionFaces: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var selectionEdges: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  
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
    
    var uniformName: String = "m"
    uniformName.utf8CString.withUnsafeBufferPointer { pointer in
      uniformM = glGetUniformLocation(program, pointer.baseAddress)
      if uniformM == -1 {
        Swift.print("prepareOpenGL: Couldn't bind uniformM")
      }
    }
    
    uniformName = "v"
    uniformName.utf8CString.withUnsafeBufferPointer { pointer in
      uniformV = glGetUniformLocation(program, pointer.baseAddress)
      if uniformV == -1 {
        Swift.print("prepareOpenGL: Couldn't bind uniformV")
      }
    }
    
    uniformName = "p"
    uniformName.utf8CString.withUnsafeBufferPointer { pointer in
      uniformP = glGetUniformLocation(program, pointer.baseAddress)
      if uniformP == -1 {
        Swift.print("prepareOpenGL: Couldn't bind uniformP")
      }
    }
    
    uniformName = "mit"
    uniformName.utf8CString.withUnsafeBufferPointer { pointer in
      uniformMIT = glGetUniformLocation(program, pointer.baseAddress)
      if uniformMIT == -1 {
        Swift.print("prepareOpenGL: Couldn't bind uniformMIT")
      }
    }
    
    uniformName = "vi"
    uniformName.utf8CString.withUnsafeBufferPointer { pointer in
      uniformVI = glGetUniformLocation(program, pointer.baseAddress)
      if uniformVI == -1 {
        Swift.print("prepareOpenGL: Couldn't bind uniformVI")
      }
    }
    
    uniformName = "v_color"
    uniformName.utf8CString.withUnsafeBufferPointer { pointer in
      uniformColour = glGetUniformLocation(program, pointer.baseAddress)
      if uniformColour == -1 {
        Swift.print("prepareOpenGL: Couldn't bind uniformColour")
      }
    }
    
    var attributeName: String = "v_coord"
    attributeName.utf8CString.withUnsafeBufferPointer { pointer in
      attributeCoordinates = glGetAttribLocation(program, pointer.baseAddress)
      if attributeCoordinates == -1 {
        Swift.print("prepareOpenGL: Couldn't bind attributeCoordinates")
      }
    }
    
    attributeName = "v_normal"
    attributeName.utf8CString.withUnsafeBufferPointer { pointer in
      attributeNormals = glGetAttribLocation(program, pointer.baseAddress)
      if attributeNormals == -1 {
        Swift.print("prepareOpenGL: Couldn't bind attributeNormals")
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
    glGenBuffers(1, &vboSelectionFaces)
    glGenBuffers(1, &vboSelectionEdges)
    
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
    fieldOfView = GLKMathDegreesToRadians(45.0)
    
    modelTranslationToCentreOfRotation = GLKMatrix4Identity
    modelRotation = GLKMatrix4Identity
    modelShiftBack = GLKMatrix4MakeTranslation(centre.x, centre.y, centre.z)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
    mArray = [model.m00, model.m01, model.m02, model.m03,
              model.m10, model.m11, model.m12, model.m13,
              model.m20, model.m21, model.m22, model.m23,
              model.m30, model.m31, model.m32, model.m33]
    var isInvertible: Bool = true
    let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(model), &isInvertible))
    mitArray = [mit.m00, mit.m01, mit.m02,
                mit.m10, mit.m11, mit.m12,
                mit.m20, mit.m21, mit.m22]
    view = GLKMatrix4MakeLookAt(eye.x, eye.y, eye.z, centre.x, centre.y, centre.z, 0.0, 1.0, 0.0)
    vArray = [view.m00, view.m01, view.m02, view.m03,
              view.m10, view.m11, view.m12, view.m13,
              view.m20, view.m21, view.m22, view.m23,
              view.m30, view.m31, view.m32, view.m33]
    let vi = GLKMatrix4Invert(view, &isInvertible)
    viArray = [vi.m00, vi.m01, vi.m02, vi.m03,
               vi.m10, vi.m11, vi.m12, vi.m13,
               vi.m20, vi.m21, vi.m22, vi.m23,
               vi.m30, vi.m31, vi.m32, vi.m33]
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    pArray = [projection.m00, projection.m01, projection.m02, projection.m03,
              projection.m10, projection.m11, projection.m12, projection.m13,
              projection.m20, projection.m21, projection.m22, projection.m23,
              projection.m30, projection.m31, projection.m32, projection.m33]
    
//    Swift.print("View bounds: height = \(bounds.size.height), width = \(bounds.size.width)")
    
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
    CVDisplayLinkSetOutputCallback(displayLink!, displayLinkOutputCallback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
//    CVDisplayLinkStart(displayLink!)
  }
  
  override var acceptsFirstResponder: Bool {
    return true
  }
  
  func click(with event: NSEvent) {
    Swift.print("OpenGLView.click()")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    
    // Compute the current mouse position
    let currentX: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
    
    // Compute two points on the ray represented by the mouse position at the near and far planes
    var isInvertible: Bool = true
    let mvpInverse = GLKMatrix4Invert(GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model)), &isInvertible)
    let pointOnNearPlaneInProjectionCoordinates = GLKVector4Make(currentX, currentY, -1.0, 1.0)
    let pointOnNearPlaneInObjectCoordinates = GLKMatrix4MultiplyVector4(mvpInverse, pointOnNearPlaneInProjectionCoordinates)
    let pointOnFarPlaneInProjectionCoordinates = GLKVector4Make(currentX, currentY, 1.0, 1.0)
    let pointOnFarPlaneInObjectCoordinates = GLKMatrix4MultiplyVector4(mvpInverse, pointOnFarPlaneInProjectionCoordinates)
    
    // Compute ray
    let rayOrigin = GLKVector3Make(pointOnNearPlaneInObjectCoordinates.x/pointOnNearPlaneInObjectCoordinates.w, pointOnNearPlaneInObjectCoordinates.y/pointOnNearPlaneInObjectCoordinates.w, pointOnNearPlaneInObjectCoordinates.z/pointOnNearPlaneInObjectCoordinates.w)
    let rayDestination = GLKVector3Make(pointOnFarPlaneInObjectCoordinates.x/pointOnFarPlaneInObjectCoordinates.w, pointOnFarPlaneInObjectCoordinates.y/pointOnFarPlaneInObjectCoordinates.w, pointOnFarPlaneInObjectCoordinates.z/pointOnFarPlaneInObjectCoordinates.w)
    let rayDirection = GLKVector3Subtract(rayDestination, rayOrigin)
    
    // Test intersections with triangles
    var hitObjects = [String]()
    controller!.cityGMLParser!.initialiseIterator()
    while !controller!.cityGMLParser!.iteratorEnded() {
      
      // Get buffers
      var numberOfTriangleVertices: UInt = 0
      let firstElementOfTrianglesBuffer = controller!.cityGMLParser!.trianglesBuffer(&numberOfTriangleVertices)
      let trianglesBuffer = UnsafeBufferPointer(start: firstElementOfTrianglesBuffer, count: Int(numberOfTriangleVertices))
      let triangles = ContiguousArray(trianglesBuffer)
      var numberOfTriangleVertices2: UInt = 0
      let firstElementOfTrianglesBuffer2 = controller!.cityGMLParser!.triangles2Buffer(&numberOfTriangleVertices2)
      let trianglesBuffer2 = UnsafeBufferPointer(start: firstElementOfTrianglesBuffer2, count: Int(numberOfTriangleVertices2))
      let triangles2 = ContiguousArray(trianglesBuffer2)
      var idLength: UInt = 0
      let firstElementOfIdBuffer = UnsafeRawPointer(controller!.cityGMLParser!.identifier(&idLength))
      let idData = Data(bytes: firstElementOfIdBuffer!, count: Int(idLength)*MemoryLayout<Int8>.size)
      let id = String(data: idData, encoding: String.Encoding.utf8)
      
      let epsilon: Float = 0.000001
      
      let numberOfTriangles = numberOfTriangleVertices/18
      for triangleIndex in 0..<numberOfTriangles {
        let vertex1 = GLKVector3Make(triangles[Int(18*triangleIndex)], triangles[Int(18*triangleIndex+1)], triangles[Int(18*triangleIndex+2)])
        let vertex2 = GLKVector3Make(triangles[Int(18*triangleIndex+6)], triangles[Int(18*triangleIndex+7)], triangles[Int(18*triangleIndex+8)])
        let vertex3 = GLKVector3Make(triangles[Int(18*triangleIndex+12)], triangles[Int(18*triangleIndex+13)], triangles[Int(18*triangleIndex+14)])
        let edge1 = GLKVector3Subtract(vertex2, vertex1)
        let edge2 = GLKVector3Subtract(vertex3, vertex1)
        let P = GLKVector3CrossProduct(rayDirection, edge2)
        let determinant = GLKVector3DotProduct(edge1, P)
        if determinant > -epsilon && determinant < epsilon {
          continue
        }
        let inverseDeterminant = 1.0 / determinant
        let T = GLKVector3Subtract(rayOrigin, vertex1)
        let u = GLKVector3DotProduct(T, P) * inverseDeterminant
        if u < 0.0 || u > 1.0 {
          continue
        }
        let Q = GLKVector3CrossProduct(T, edge1)
        let v = GLKVector3DotProduct(rayDirection, Q) * inverseDeterminant
        if v < 0.0 || u + v > 1.0 {
          continue
        }
        let t = GLKVector3DotProduct(edge2, Q) * inverseDeterminant
        if t > epsilon {
          Swift.print("Hit \(id!)")
          hitObjects.append(id!)
        }
      }
      
      controller!.cityGMLParser!.advanceIterator()
    }
  }
  
  func doubleClick(with event: NSEvent) {
    Swift.print("OpenGLView.doubleClick()")
//    Swift.print("Mouse location X: \(window!.mouseLocationOutsideOfEventStream.x), Y: \(window!.mouseLocationOutsideOfEventStream.y)")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
//    Swift.print("View X: \(viewFrameInWindowCoordinates.origin.x), Y: \(viewFrameInWindowCoordinates.origin.y)")
    
    // Compute the current mouse position
    let currentX: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
//    Swift.print("currentX: \(currentX), currentY: \(currentY)")
    
    // Compute two points on the ray represented by the mouse position at the near and far planes
    var isInvertible: Bool = true
    let mvpInverse = GLKMatrix4Invert(GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model)), &isInvertible)
    let pointOnNearPlaneInProjectionCoordinates = GLKVector4Make(currentX, currentY, -1.0, 1.0)
    let pointOnNearPlaneInObjectCoordinates = GLKMatrix4MultiplyVector4(mvpInverse, pointOnNearPlaneInProjectionCoordinates)
    let pointOnFarPlaneInProjectionCoordinates = GLKVector4Make(currentX, currentY, 1.0, 1.0)
    let pointOnFarPlaneInObjectCoordinates = GLKMatrix4MultiplyVector4(mvpInverse, pointOnFarPlaneInProjectionCoordinates)
    
    // Interpolate the points to obtain the intersection with the data plane z = 0
    let alpha: Float = -(pointOnFarPlaneInObjectCoordinates.z/pointOnFarPlaneInObjectCoordinates.w)/((pointOnNearPlaneInObjectCoordinates.z/pointOnNearPlaneInObjectCoordinates.w)-(pointOnFarPlaneInObjectCoordinates.z/pointOnFarPlaneInObjectCoordinates.w))
    let clickedPointInObjectCoordinates = GLKVector4Make(alpha*(pointOnNearPlaneInObjectCoordinates.x/pointOnNearPlaneInObjectCoordinates.w)+(1.0-alpha)*(pointOnFarPlaneInObjectCoordinates.x/pointOnFarPlaneInObjectCoordinates.w), alpha*(pointOnNearPlaneInObjectCoordinates.y/pointOnNearPlaneInObjectCoordinates.w)+(1.0-alpha)*(pointOnFarPlaneInObjectCoordinates.y/pointOnFarPlaneInObjectCoordinates.w), 0.0, 1.0)
    
    // Use the intersection to compute the shift in the view space
    let objectToCamera = GLKMatrix4Multiply(model, view)
    let clickedPointInCameraCoordinates = GLKMatrix4MultiplyVector4(objectToCamera, clickedPointInObjectCoordinates)
    
    // Compute shift in object space
    let shiftInCameraCoordinates: GLKVector3 = GLKVector3Make(-clickedPointInCameraCoordinates.x, -clickedPointInCameraCoordinates.y, 0.0)
    var cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(objectToCamera), &isInvertible)
    let shiftInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, shiftInCameraCoordinates)
    modelTranslationToCentreOfRotation = GLKMatrix4TranslateWithVector3(modelTranslationToCentreOfRotation, shiftInObjectCoordinates)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)

    // Correct shift so that the point of rotation remains at the same depth as the data
    cameraToObject = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(model, view)), &isInvertible)
    let depthOffset = 1.0+depthAtCentre()
    let depthOffsetInCameraCoordinates: GLKVector3 = GLKVector3Make(0.0, 0.0, -depthOffset)
    let depthOffsetInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, depthOffsetInCameraCoordinates)
    modelTranslationToCentreOfRotation = GLKMatrix4TranslateWithVector3(modelTranslationToCentreOfRotation, depthOffsetInObjectCoordinates)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
    
    // Put model matrix in arrays and render
    mArray = [model.m00, model.m01, model.m02, model.m03,
              model.m10, model.m11, model.m12, model.m13,
              model.m20, model.m21, model.m22, model.m23,
              model.m30, model.m31, model.m32, model.m33]
    let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(model), &isInvertible))
    mitArray = [mit.m00, mit.m01, mit.m02,
                mit.m10, mit.m11, mit.m12,
                mit.m20, mit.m21, mit.m22]
    renderFrame()
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
  
  override func mouseDragged(with event: NSEvent) {
//    Swift.print("OpenGLView.mouseDragged()")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    
    // Compute the current and last mouse positions and their depth on a sphere
    let currentX: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x) / bounds.size.width)
    let currentY: Float = Float(-1.0 + 2.0*(window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y) / bounds.size.height)
    let currentZ = sqrt(1 - (currentX*currentX+currentY*currentY))
    let currentPosition = GLKVector3Normalize(GLKVector3(v: (Float(currentX), Float(currentY), Float(currentZ))))
//    Swift.print("Current position X: \(currentPosition.x) Y: \(currentPosition.y) Z: \(currentPosition.z)")
    let lastX = -1.0 + 2.0*((window!.mouseLocationOutsideOfEventStream.x-viewFrameInWindowCoordinates.origin.x)-event.deltaX) / bounds.size.width
    let lastY = -1.0 + 2.0*((window!.mouseLocationOutsideOfEventStream.y-viewFrameInWindowCoordinates.origin.y)+event.deltaY) / bounds.size.height
    let lastZ = sqrt(1 - (lastX*lastX+lastY*lastY))
    let lastPosition = GLKVector3Normalize(GLKVector3(v: (Float(lastX), Float(lastY), Float(lastZ))))
//    Swift.print("Last position X: \(lastPosition.x) Y: \(lastPosition.y) Z: \(lastPosition.z)")
    
    // Compute the angle between the two and use it to move in camera space
    let angle = acos(GLKVector3DotProduct(lastPosition, currentPosition))
    if !angle.isNaN && angle > 0.0 {
//      Swift.print("Angle: \(angle)")
      let axisInCameraCoordinates: GLKVector3 = GLKVector3CrossProduct(lastPosition, currentPosition)
      var isInvertible: Bool = true
      let cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(model, view)), &isInvertible)
      let axisInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, axisInCameraCoordinates)
      modelRotation = GLKMatrix4RotateWithVector3(modelRotation, angle, axisInObjectCoordinates)
      model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
      mArray = [model.m00, model.m01, model.m02, model.m03,
                model.m10, model.m11, model.m12, model.m13,
                model.m20, model.m21, model.m22, model.m23,
                model.m30, model.m31, model.m32, model.m33]
      let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(model), &isInvertible))
      mitArray = [mit.m00, mit.m01, mit.m02,
                  mit.m10, mit.m11, mit.m12,
                  mit.m20, mit.m21, mit.m22]
      renderFrame()
    } else {
//      Swift.print("NaN!")
    }
  }
  
  override func rotate(with event: NSEvent) {
//    Swift.print("OpenGLView.rotate()")
//    Swift.print("Rotation angle: \(event.rotation)")
    
    let axisInCameraCoordinates: GLKVector3 = GLKVector3Make(0.0, 0.0, 1.0)
    var isInvertible: Bool = true
    let cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(model, view)), &isInvertible)
    let axisInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, axisInCameraCoordinates)
    modelRotation = GLKMatrix4RotateWithVector3(modelRotation, GLKMathDegreesToRadians(event.rotation), axisInObjectCoordinates)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
    mArray = [model.m00, model.m01, model.m02, model.m03,
              model.m10, model.m11, model.m12, model.m13,
              model.m20, model.m21, model.m22, model.m23,
              model.m30, model.m31, model.m32, model.m33]
    let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(model), &isInvertible))
    mitArray = [mit.m00, mit.m01, mit.m02,
                mit.m10, mit.m11, mit.m12,
                mit.m20, mit.m21, mit.m22]
    renderFrame()
  }
  
  override func rightMouseDragged(with event: NSEvent) {
//    Swift.print("OpenGLView.rightMouseDragged()")
//    Swift.print("Delta: (\(event.deltaX), \(event.deltaY))")
    
    let zoomSensitivity: Float = 0.005
    let magnification: Float = 1.0+zoomSensitivity*Float(event.deltaY)
    fieldOfView = 2.0*atanf(tanf(0.5*fieldOfView)/magnification)
//    Swift.print("Field of view: \(fieldOfView)")
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    pArray = [projection.m00, projection.m01, projection.m02, projection.m03,
              projection.m10, projection.m11, projection.m12, projection.m13,
              projection.m20, projection.m21, projection.m22, projection.m23,
              projection.m30, projection.m31, projection.m32, projection.m33]
    renderFrame()
  }
  
  override func scrollWheel(with event: NSEvent) {
//    Swift.print("OpenGLView.scrollWheel()")
//    Swift.print("Scrolled X: \(event.scrollingDeltaX) Y: \(event.scrollingDeltaY)")
    
    // Motion according to trackpad
    let scrollingSensitivity: Float = 0.003*(fieldOfView/GLKMathDegreesToRadians(45.0))
    var isInvertible: Bool = true
    let motionInCameraCoordinates: GLKVector3 = GLKVector3Make(scrollingSensitivity*Float(event.scrollingDeltaX), -scrollingSensitivity*Float(event.scrollingDeltaY), 0.0)
    var cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(model, view)), &isInvertible)
    let motionInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, motionInCameraCoordinates)
    modelTranslationToCentreOfRotation = GLKMatrix4TranslateWithVector3(modelTranslationToCentreOfRotation, motionInObjectCoordinates)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
    
    // Correct motion so that the point of rotation remains at the same depth as the data
    cameraToObject = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(model, view)), &isInvertible)
    let depthOffset = 1.0+depthAtCentre()
//    Swift.print("Depth offset: \(depthOffset)")
    let depthOffsetInCameraCoordinates: GLKVector3 = GLKVector3Make(0.0, 0.0, -depthOffset)
    let depthOffsetInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, depthOffsetInCameraCoordinates)
    modelTranslationToCentreOfRotation = GLKMatrix4TranslateWithVector3(modelTranslationToCentreOfRotation, depthOffsetInObjectCoordinates)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
    
    // Put model matrix in arrays and render
    mArray = [model.m00, model.m01, model.m02, model.m03,
              model.m10, model.m11, model.m12, model.m13,
              model.m20, model.m21, model.m22, model.m23,
              model.m30, model.m31, model.m32, model.m33]
    let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(model), &isInvertible))
    mitArray = [mit.m00, mit.m01, mit.m02,
                mit.m10, mit.m11, mit.m12,
                mit.m20, mit.m21, mit.m22]
    renderFrame()
  }
  
  override func magnify(with event: NSEvent) {
//    Swift.print("OpenGLView.magnify()")
//    Swift.print("Pinched: \(event.magnification)")
    let magnification: Float = 1.0+Float(event.magnification)
    fieldOfView = 2.0*atanf(tanf(0.5*fieldOfView)/magnification)
//    Swift.print("Field of view: \(fieldOfView)")
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    pArray = [projection.m00, projection.m01, projection.m02, projection.m03,
              projection.m10, projection.m11, projection.m12, projection.m13,
              projection.m20, projection.m21, projection.m22, projection.m23,
              projection.m30, projection.m31, projection.m32, projection.m33]
    renderFrame()
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
    
    // Create three points along the data plane
    let leftUpPointInObjectCoordinates = GLKVector4Make(minCoordinates[0], maxCoordinates[1], 0.0, 1.0)
    let rightUpPointInObjectCoordinates = GLKVector4Make(maxCoordinates[0], maxCoordinates[1], 0.0, 1.0)
    let centreDownPointInObjectCoordinates = GLKVector4Make(0.0, minCoordinates[1], 0.0, 1.0)
    
    // Obtain their coordinates in eye space
    let modelView = GLKMatrix4Multiply(view, model)
    let leftUpPoint = GLKMatrix4MultiplyVector4(modelView, leftUpPointInObjectCoordinates)
    let rightUpPoint = GLKMatrix4MultiplyVector4(modelView, rightUpPointInObjectCoordinates)
    let centreDownPoint = GLKMatrix4MultiplyVector4(modelView, centreDownPointInObjectCoordinates)
    
    // Compute the plane passing through the points.
    // In ax + by + cz + d = 0, abc are given by the cross product, d by evaluating a point in the equation.
    let vector1 = GLKVector4Make(leftUpPoint.x-centreDownPoint.x, leftUpPoint.y-centreDownPoint.y, leftUpPoint.z-centreDownPoint.z, 1.0)
    let vector2 = GLKVector4Make(rightUpPoint.x-centreDownPoint.x, rightUpPoint.y-centreDownPoint.y, rightUpPoint.z-centreDownPoint.z, 1.0)
    let crossProduct = GLKVector4CrossProduct(vector1, vector2)
    let d = -GLKVector4DotProduct(crossProduct, centreDownPoint)
    
    // Assuming x = 0 and y = 0, z (i.e. depth at the centre) = -d/c
//    Swift.print("Depth at centre: \(-d/crossProduct.z)")
    return -d/crossProduct.z
  }
  
  override func reshape() {
//    Swift.print("OpenGLView.reshape()")
//    Swift.print("View bounds: height = \(bounds.size.height), width = \(bounds.size.width)")
    super.reshape()
    glViewport(0, 0, GLsizei(bounds.size.width), GLsizei(bounds.size.height))
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    pArray = [projection.m00, projection.m01, projection.m02, projection.m03,
              projection.m10, projection.m11, projection.m12, projection.m13,
              projection.m20, projection.m21, projection.m22, projection.m23,
              projection.m30, projection.m31, projection.m32, projection.m33]
    pArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformP, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
  }
  
  func renderFrame() {
//    Swift.print("OpenGLView.renderFrame()")
    
    openGLContext!.makeCurrentContext()
    CGLLockContext(openGLContext!.cglContextObj!)
    
    glClearColor(1.0, 1.0, 1.0, 1.0)
    glEnable(GLenum(GL_DEPTH_TEST))
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT) | GLbitfield(GL_DEPTH_BUFFER_BIT))
    
    glUseProgram(program)
    
    mArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformM, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    vArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformV, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    pArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformP, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    mitArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix3fv(uniformMIT, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    viArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformVI, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    
    glEnableVertexAttribArray(GLuint(attributeCoordinates))
    glEnableVertexAttribArray(GLuint(attributeNormals))
    
    glUniform3f(uniformColour, buildingsColour[0], buildingsColour[1], buildingsColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboBuildings)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    var size: GLsizei = 0
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) building triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering buildings: some error occurred!")
    }
    
    glUniform3f(uniformColour, buildingRoofsColour[0], buildingRoofsColour[1], buildingRoofsColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboBuildingRoofs)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) building roof triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering building roofs: some error occurred!")
    }
    
    glUniform3f(uniformColour, roadsColour[0], roadsColour[1], roadsColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboRoads)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) road triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering roads: some error occurred!")
    }
    
    glUniform3f(uniformColour, waterColour[0], waterColour[1], waterColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboWater)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) water triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering water bodies: some error occurred!")
    }
    
    glUniform3f(uniformColour, plantCoverColour[0], plantCoverColour[1], plantCoverColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboPlantCover)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) plant cover triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering plant cover: some error occurred!")
    }
    
    glUniform3f(uniformColour, terrainColour[0], terrainColour[1], terrainColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboTerrain)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) terrain triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering terrain: some error occurred!")
    }
    
    glUniform3f(uniformColour, genericColour[0], genericColour[1], genericColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboGeneric)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) generic triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering generic objects: some error occurred!")
    }
    
    glUniform3f(uniformColour, bridgeColour[0], bridgeColour[1], bridgeColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboBridges)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) bridge triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering bridges: some error occurred!")
    }
    
    glUniform3f(uniformColour, landUseColour[0], landUseColour[1], landUseColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboLandUse)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//    Swift.print("Drawing \(size/3) land use triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering land use: some error occurred!")
    }
    
    glUniform3f(uniformColour, selectionFacesColour[0], selectionFacesColour[1], selectionFacesColour[2])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboSelectionFaces)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
    //    Swift.print("Drawing \(size/3) selection triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, size)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering selection faces: some error occurred!")
    }
    
    glDisableVertexAttribArray(GLuint(attributeNormals))
    
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
    
    if viewEdges {
      glUniform3f(uniformColour, selectionEdgesColour[0], selectionEdgesColour[1], selectionEdgesColour[2])
      glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboSelectionEdges)
      glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
      glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &size)
//      Swift.print("Drawing \(size/2) selection edges")
      glDrawArrays(GLenum(GL_LINES), 0, size)
      if glGetError() != GLenum(GL_NO_ERROR) {
        Swift.print("Rendering selection edges: some error occurred!")
      }
    }
    
    glDisableVertexAttribArray(GLuint(attributeCoordinates))
    glDisableVertexAttribArray(GLuint(attributeNormals))
    
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
    glDeleteBuffers(1, &vboSelectionFaces)
    glDeleteBuffers(1, &vboSelectionEdges)
  }
}
