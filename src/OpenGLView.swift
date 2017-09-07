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
import OpenGL.GL3
import GLKit

class TriangleList {
  var triangles = ContiguousArray<GLfloat>()
}

class TriangleListsBySubtype {
  var triangleListOfSubtype = [String: TriangleList]()
}

class TriangleListsByTypeAndSubtype {
  var triangleListOfType = [String: TriangleListsBySubtype]()
}

class OpenGLView: NSOpenGLView {
  
  var controller: Controller?
  var dataStorage: DataStorage?
  
  var displayLink: CVDisplayLink?
  
  var program: GLuint = 0
  
  var preparedOpenGL: Bool = false
  
  var viewEdges: Bool = false
  var viewBoundingBox: Bool = false
  
  var multipleSelection: Bool = false
  
  var vboFaces = [String: [String: GLuint]]()
  var vboEdges: GLuint = 0
  var vboBoundingBox: GLuint = 0
  var vboSelectionFaces: GLuint = 0
  var vboSelectionEdges: GLuint = 0
  
  var uniformM: GLint = 0
  var uniformMVP: GLint = 0
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
  
  var mArray: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var mvpArray: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var mitArray: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var viArray: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  
  var facesColour = [String: [String: Array<GLfloat>]]()
  let edgesColour: Array<GLfloat> = [0.0, 0.0, 0.0, 1.0]
  let boundingBoxColour: Array<GLfloat> = [0.0, 0.0, 0.0, 1.0]
  let selectionFacesColour: Array<GLfloat> = [1.0, 1.0, 0.0, 1.0]
  let selectionEdgesColour: Array<GLfloat> = [1.0, 0.0, 0.0, 1.0]
  
  var faceTriangles = TriangleListsByTypeAndSubtype()
  var edges: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var boundingBox: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var selectionFaces: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  var selectionEdges: ContiguousArray<GLfloat> = ContiguousArray<GLfloat>()
  
  override init?(frame: NSRect, pixelFormat: NSOpenGLPixelFormat?) {
    Swift.print("init?(NSRect, NSOpenGLPixelFormat?)")
  
    super.init(frame: frame, pixelFormat: pixelFormat)
    
    wantsBestResolutionOpenGLSurface = true
    openGLContext = NSOpenGLContext(format: pixelFormat!, share: nil)
    openGLContext!.setValues([1], for: NSOpenGLCPSwapInterval)
    
    facesColour["AuxiliaryTrafficArea"] = [String: Array<GLfloat>]()
    facesColour["AuxiliaryTrafficArea"]![""] = [0.7, 0.7, 0.7, 1.0]
    facesColour["Bridge"] = [String: Array<GLfloat>]()
    facesColour["Bridge"]![""] = [0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0]
    facesColour["Building"] = [String: Array<GLfloat>]()
    facesColour["Building"]![""] = [1.0, 0.956862745098039, 0.690196078431373, 1.0]
    facesColour["Building"]!["Door"] = [0.482352941176471, 0.376470588235294, 0.231372549019608, 1.0]
    facesColour["Building"]!["GroundSurface"] = [0.7, 0.7, 0.7, 1.0]
    facesColour["Building"]!["RoofSurface"] = [0.882352941176471, 0.254901960784314, 0.219607843137255, 1.0]
    facesColour["Building"]!["Window"] = [0.584313725490196, 0.917647058823529, 1.0, 0.3]
    facesColour["BuildingPart"] = [String: Array<GLfloat>]()
    facesColour["BuildingPart"]![""] = [1.0, 0.956862745098039, 0.690196078431373, 1.0]
    facesColour["BuildingPart"]!["Door"] = [0.482352941176471, 0.376470588235294, 0.231372549019608, 1.0]
    facesColour["BuildingPart"]!["GroundSurface"] = [0.7, 0.7, 0.7, 1.0]
    facesColour["BuildingPart"]!["RoofSurface"] = [0.882352941176471, 0.254901960784314, 0.219607843137255, 1.0]
    facesColour["BuildingPart"]!["Window"] = [0.584313725490196, 0.917647058823529, 1.0, 0.3]
    facesColour["CityFurniture"] = [String: Array<GLfloat>]()
    facesColour["CityFurniture"]![""] = [0.7, 0.7, 0.7, 1.0]
    facesColour["GenericCityObject"] = [String: Array<GLfloat>]()
    facesColour["GenericCityObject"]![""] = [0.7, 0.7, 0.7, 1.0]
    facesColour["LandUse"] = [String: Array<GLfloat>]()
    facesColour["LandUse"]![""] = [0.3, 0.3, 0.3, 1.0]
    facesColour["PlantCover"] = [String: Array<GLfloat>]()
    facesColour["PlantCover"]![""] = [0.4, 0.882352941176471, 0.333333333333333, 1.0]
    facesColour["Railway"] = [String: Array<GLfloat>]()
    facesColour["Railway"]![""] = [0.7, 0.7, 0.7, 1.0]
    facesColour["ReliefFeature"] = [String: Array<GLfloat>]()
    facesColour["ReliefFeature"]![""] = [0.713725490196078, 0.882352941176471, 0.623529411764706, 1.0]
    facesColour["Road"] = [String: Array<GLfloat>]()
    facesColour["Road"]![""] = [0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0]
    facesColour["SolitaryVegetationObject"] = [String: Array<GLfloat>]()
    facesColour["SolitaryVegetationObject"]![""] = [0.4, 0.882352941176471, 0.333333333333333, 1.0]
    facesColour["TrafficArea"] = [String: Array<GLfloat>]()
    facesColour["TrafficArea"]![""] = [0.7, 0.7, 0.7, 1.0]
    facesColour["Tunnel"] = [String: Array<GLfloat>]()
    facesColour["Tunnel"]![""] = [0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0]
    facesColour["Tunnel"]!["GroundSurface"] = [0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0]
    facesColour["Tunnel"]!["RoofSurface"] = [0.458823529411765, 0.458823529411765, 0.458823529411765, 1.0]
    facesColour["WaterBody"] = [String: Array<GLfloat>]()
    facesColour["WaterBody"]![""] = [0.584313725490196, 0.917647058823529, 1.0, 1.0]
    
    register(forDraggedTypes: [NSFilenamesPboardType])
  }
  
  required init?(coder: NSCoder) {
    Swift.print("init?(NSCoder)")
    super.init(coder: coder)
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
    Swift.print("prepareOpenGL()")
    
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
    
    uniformName = "mvp"
    uniformName.utf8CString.withUnsafeBufferPointer { pointer in
      uniformMVP = glGetUniformLocation(program, pointer.baseAddress)
      if uniformMVP == -1 {
        Swift.print("prepareOpenGL: Couldn't bind uniformMVP")
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
    
    for faceType in facesColour {
      vboFaces[faceType.key] = [String: GLuint]()
      for faceSubtype in faceType.value {
        vboFaces[faceType.key]![faceSubtype.key] = 0
        glGenBuffers(1, &vboFaces[faceType.key]![faceSubtype.key]!)
      }
    }
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
    fieldOfView = GLKMathDegreesToRadians(60.0)
    
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
    let vi = GLKMatrix4Invert(view, &isInvertible)
    viArray = [vi.m00, vi.m01, vi.m02, vi.m03,
               vi.m10, vi.m11, vi.m12, vi.m13,
               vi.m20, vi.m21, vi.m22, vi.m23,
               vi.m30, vi.m31, vi.m32, vi.m33]
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    let mvp = GLKMatrix4Multiply(GLKMatrix4Multiply(projection, view), model)
    mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    
//    Swift.print("View bounds: height = \(bounds.size.height), width = \(bounds.size.width)")
    
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
    CVDisplayLinkSetOutputCallback(displayLink!, displayLinkOutputCallback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
//    CVDisplayLinkStart(displayLink!)
    
    preparedOpenGL = true
  }
  
  override var acceptsFirstResponder: Bool {
    return true
  }
  
  func new() {
    Swift.print("OpenGLView()")
    
    for faceType in faceTriangles.triangleListOfType {
      for faceSubtype in faceType.value.triangleListOfSubtype {
        faceTriangles.triangleListOfType[faceType.key]!.triangleListOfSubtype[faceSubtype.key]!.triangles.removeAll()
      }
    }
    edges.removeAll()
    boundingBox.removeAll()
    selectionFaces.removeAll()
    selectionEdges.removeAll()
    
    fieldOfView = GLKMathDegreesToRadians(60.0)
    
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
    let vi = GLKMatrix4Invert(view, &isInvertible)
    viArray = [vi.m00, vi.m01, vi.m02, vi.m03,
               vi.m10, vi.m11, vi.m12, vi.m13,
               vi.m20, vi.m21, vi.m22, vi.m23,
               vi.m30, vi.m31, vi.m32, vi.m33]
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    let mvp = GLKMatrix4Multiply(GLKMatrix4Multiply(projection, view), model)
    mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    
    pullData()
    renderFrame()
  }
  
  func goHome() {
    fieldOfView = GLKMathDegreesToRadians(60.0)
    
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
    let vi = GLKMatrix4Invert(view, &isInvertible)
    viArray = [vi.m00, vi.m01, vi.m02, vi.m03,
               vi.m10, vi.m11, vi.m12, vi.m13,
               vi.m20, vi.m21, vi.m22, vi.m23,
               vi.m30, vi.m31, vi.m32, vi.m33]
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    let mvp = GLKMatrix4Multiply(GLKMatrix4Multiply(projection, view), model)
    mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    renderFrame()
  }
  
  func click(with event: NSEvent) {
//    Swift.print("click()")
    let viewFrameInWindowCoordinates = convert(bounds, to: nil)
    
    // Compute midCoordinates and maxRange
    let minCoordinates = GLKVector3Make(dataStorage!.minCoordinates[0], dataStorage!.minCoordinates[1], dataStorage!.minCoordinates[2])
    let maxCoordinates = GLKVector3Make(dataStorage!.maxCoordinates[0], dataStorage!.maxCoordinates[1], dataStorage!.maxCoordinates[2])
    let range = GLKVector3Subtract(maxCoordinates, minCoordinates)
    let midCoordinates = GLKVector3Add(minCoordinates, GLKVector3MultiplyScalar(range, 0.5))
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
    var closestHit: String = ""
    var hitDistance: Float = -1.0
    for object in dataStorage!.objects {
      
      let epsilon: Float = 0.000001
      let objectToCamera = GLKMatrix4Multiply(view, model)
      
      // Moller-Trumbore algorithm for triangle-ray intersection (non-culling)
      // u,v are the barycentric coordinates of the intersection point
      // t is the distance from rayOrigin to the intersection point
      for trianglesBuffer in object.triangleBuffersByType {
        let numberOfTriangles = trianglesBuffer.value.count/18
        for triangleIndex in 0..<numberOfTriangles {
          let vertex0 = GLKVector3Make((trianglesBuffer.value[Int(18*triangleIndex)]-midCoordinates[0])/maxRange,
                                       (trianglesBuffer.value[Int(18*triangleIndex+1)]-midCoordinates[1])/maxRange,
                                       (trianglesBuffer.value[Int(18*triangleIndex+2)]-midCoordinates[2])/maxRange)
          let vertex1 = GLKVector3Make((trianglesBuffer.value[Int(18*triangleIndex+6)]-midCoordinates[0])/maxRange,
                                       (trianglesBuffer.value[Int(18*triangleIndex+7)]-midCoordinates[1])/maxRange,
                                       (trianglesBuffer.value[Int(18*triangleIndex+8)]-midCoordinates[2])/maxRange)
          let vertex2 = GLKVector3Make((trianglesBuffer.value[Int(18*triangleIndex+12)]-midCoordinates[0])/maxRange,
                                       (trianglesBuffer.value[Int(18*triangleIndex+13)]-midCoordinates[1])/maxRange,
                                       (trianglesBuffer.value[Int(18*triangleIndex+14)]-midCoordinates[2])/maxRange)
          let edge1 = GLKVector3Subtract(vertex1, vertex0)
          let edge2 = GLKVector3Subtract(vertex2, vertex0)
          let pvec = GLKVector3CrossProduct(rayDirection, edge2)
          let determinant = GLKVector3DotProduct(edge1, pvec)
          if determinant > -epsilon && determinant < epsilon {
            continue // if determinant is near zero  ray lies in plane of triangle
          }
          let inverseDeterminant = 1.0 / determinant
          let tvec = GLKVector3Subtract(rayOrigin, vertex0) // distance from vertex0 to rayOrigin
          let u = GLKVector3DotProduct(tvec, pvec) * inverseDeterminant
          if u < 0.0 || u > 1.0 {
            continue
          }
          let qvec = GLKVector3CrossProduct(tvec, edge1)
          let v = GLKVector3DotProduct(rayDirection, qvec) * inverseDeterminant
          if v < 0.0 || u + v > 1.0 {
            continue
          }
          let t = GLKVector3DotProduct(edge2, qvec) * inverseDeterminant
          if t > epsilon {
            let intersectionPointInObjectCoordinates = GLKVector3Add(GLKVector3Add(GLKVector3MultiplyScalar(vertex0, 1.0-u-v), GLKVector3MultiplyScalar(vertex1, u)), GLKVector3MultiplyScalar(vertex2, v))
            let intersectionPointInCameraCoordinates = GLKMatrix4MultiplyVector3(objectToCamera, intersectionPointInObjectCoordinates)
            let distance = intersectionPointInCameraCoordinates.z
  //          Swift.print("Hit \(id!) at distance \(distance)")
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
  }
  
  func doubleClick(with event: NSEvent) {
//    Swift.print("doubleClick()")
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
    let objectToCamera = GLKMatrix4Multiply(view, model)
    let clickedPointInCameraCoordinates = GLKMatrix4MultiplyVector4(objectToCamera, clickedPointInObjectCoordinates)
    
    // Compute shift in object space
    let shiftInCameraCoordinates: GLKVector3 = GLKVector3Make(-clickedPointInCameraCoordinates.x, -clickedPointInCameraCoordinates.y, 0.0)
    var cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(objectToCamera), &isInvertible)
    let shiftInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, shiftInCameraCoordinates)
    modelTranslationToCentreOfRotation = GLKMatrix4TranslateWithVector3(modelTranslationToCentreOfRotation, shiftInObjectCoordinates)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)

    // Correct shift so that the point of rotation remains at the same depth as the data
    cameraToObject = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(view, model)), &isInvertible)
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
    let mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
    mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(model), &isInvertible))
    mitArray = [mit.m00, mit.m01, mit.m02,
                mit.m10, mit.m11, mit.m12,
                mit.m20, mit.m21, mit.m22]
    renderFrame()
  }
  
  func outlineViewDoubleClick(_ sender: Any?) {
    Swift.print("outlineViewDoubleClick()")
    
    // Compute midCoordinates and maxRange
    let minCoordinates = GLKVector3Make(dataStorage!.minCoordinates[0], dataStorage!.minCoordinates[1], dataStorage!.minCoordinates[2])
    let maxCoordinates = GLKVector3Make(dataStorage!.maxCoordinates[0], dataStorage!.maxCoordinates[1], dataStorage!.maxCoordinates[2])
    let range = GLKVector3Subtract(maxCoordinates, minCoordinates)
    let midCoordinates = GLKVector3Add(minCoordinates, GLKVector3MultiplyScalar(range, 0.5))
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
        let centroidInObjectCoordinates = GLKVector4Make(sumX/Float(numberOfVertices), sumY/Float(numberOfVertices), sumZ/Float(numberOfVertices), 1.0)
        
        // Use the centroid to compute the shift in the view space
        let objectToCamera = GLKMatrix4Multiply(view, model)
        let centroidInCameraCoordinates = GLKMatrix4MultiplyVector4(objectToCamera, centroidInObjectCoordinates)
        
        // Compute shift in object space
        let shiftInCameraCoordinates: GLKVector3 = GLKVector3Make(-centroidInCameraCoordinates.x, -centroidInCameraCoordinates.y, 0.0)
        var isInvertible: Bool = true
        var cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(objectToCamera), &isInvertible)
        let shiftInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, shiftInCameraCoordinates)
        modelTranslationToCentreOfRotation = GLKMatrix4TranslateWithVector3(modelTranslationToCentreOfRotation, shiftInObjectCoordinates)
        model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
        
        // Correct shift so that the point of rotation remains at the same depth as the data
        cameraToObject = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(view, model)), &isInvertible)
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
        let mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
        mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                    mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                    mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                    mvp.m30, mvp.m31, mvp.m32, mvp.m33]
        let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(model), &isInvertible))
        mitArray = [mit.m00, mit.m01, mit.m02,
                    mit.m10, mit.m11, mit.m12,
                    mit.m20, mit.m21, mit.m22]
        renderFrame()
      }
    }
  }
  
  override func mouseUp(with event: NSEvent) {
//    Swift.print("mouseUp()")
    
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
//    Swift.print("mouseDragged()")
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
      let cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(view, model)), &isInvertible)
      let axisInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, axisInCameraCoordinates)
      modelRotation = GLKMatrix4RotateWithVector3(modelRotation, angle, axisInObjectCoordinates)
      model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
      mArray = [model.m00, model.m01, model.m02, model.m03,
                model.m10, model.m11, model.m12, model.m13,
                model.m20, model.m21, model.m22, model.m23,
                model.m30, model.m31, model.m32, model.m33]
      let mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
      mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                  mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                  mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                  mvp.m30, mvp.m31, mvp.m32, mvp.m33]
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
//    Swift.print("rotate()")
//    Swift.print("Rotation angle: \(event.rotation)")
    
    let axisInCameraCoordinates: GLKVector3 = GLKVector3Make(0.0, 0.0, 1.0)
    var isInvertible: Bool = true
    let cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(view, model)), &isInvertible)
    let axisInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, axisInCameraCoordinates)
    modelRotation = GLKMatrix4RotateWithVector3(modelRotation, GLKMathDegreesToRadians(event.rotation), axisInObjectCoordinates)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
    mArray = [model.m00, model.m01, model.m02, model.m03,
              model.m10, model.m11, model.m12, model.m13,
              model.m20, model.m21, model.m22, model.m23,
              model.m30, model.m31, model.m32, model.m33]
    let mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
    mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(model), &isInvertible))
    mitArray = [mit.m00, mit.m01, mit.m02,
                mit.m10, mit.m11, mit.m12,
                mit.m20, mit.m21, mit.m22]
    renderFrame()
  }
  
  override func rightMouseDragged(with event: NSEvent) {
//    Swift.print("rightMouseDragged()")
//    Swift.print("Delta: (\(event.deltaX), \(event.deltaY))")
    
    let zoomSensitivity: Float = 0.005
    let magnification: Float = 1.0+zoomSensitivity*Float(event.deltaY)
    fieldOfView = 2.0*atanf(tanf(0.5*fieldOfView)/magnification)
//    Swift.print("Field of view: \(fieldOfView)")
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    let mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
    mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    renderFrame()
  }
  
  override func scrollWheel(with event: NSEvent) {
//    Swift.print("scrollWheel()")
//    Swift.print("Scrolled X: \(event.scrollingDeltaX) Y: \(event.scrollingDeltaY)")
    
    // Motion according to trackpad
    let scrollingSensitivity: Float = 0.003*(fieldOfView/GLKMathDegreesToRadians(45.0))
    var isInvertible: Bool = true
    let motionInCameraCoordinates: GLKVector3 = GLKVector3Make(scrollingSensitivity*Float(event.scrollingDeltaX), -scrollingSensitivity*Float(event.scrollingDeltaY), 0.0)
    var cameraToObject: GLKMatrix3 = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(view, model)), &isInvertible)
    let motionInObjectCoordinates: GLKVector3 = GLKMatrix3MultiplyVector3(cameraToObject, motionInCameraCoordinates)
    modelTranslationToCentreOfRotation = GLKMatrix4TranslateWithVector3(modelTranslationToCentreOfRotation, motionInObjectCoordinates)
    model = GLKMatrix4Multiply(GLKMatrix4Multiply(modelShiftBack, modelRotation), modelTranslationToCentreOfRotation)
    
    // Correct motion so that the point of rotation remains at the same depth as the data
    cameraToObject = GLKMatrix3Invert(GLKMatrix4GetMatrix3(GLKMatrix4Multiply(view, model)), &isInvertible)
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
    let mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
    mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    let mit = GLKMatrix3Transpose(GLKMatrix3Invert(GLKMatrix4GetMatrix3(model), &isInvertible))
    mitArray = [mit.m00, mit.m01, mit.m02,
                mit.m10, mit.m11, mit.m12,
                mit.m20, mit.m21, mit.m22]
    renderFrame()
  }
  
  override func magnify(with event: NSEvent) {
//    Swift.print("magnify()")
//    Swift.print("Pinched: \(event.magnification)")
    let magnification: Float = 1.0+Float(event.magnification)
    fieldOfView = 2.0*atanf(tanf(0.5*fieldOfView)/magnification)
//    Swift.print("Field of view: \(fieldOfView)")
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    let mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
    mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                mvp.m30, mvp.m31, mvp.m32, mvp.m33]
    renderFrame()
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
    case "n":
      controller?.new(controller!.newFileMenuItem)
    case "o":
      controller!.openFile(controller!.openFileMenuItem)
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
    let minCoordinates = GLKVector3Make(dataStorage!.minCoordinates[0], dataStorage!.minCoordinates[1], dataStorage!.minCoordinates[2])
    let maxCoordinates = GLKVector3Make(dataStorage!.maxCoordinates[0], dataStorage!.maxCoordinates[1], dataStorage!.maxCoordinates[2])
    let range = GLKVector3Subtract(maxCoordinates, minCoordinates)
    let midCoordinates = GLKVector3Add(minCoordinates, GLKVector3MultiplyScalar(range, 0.5))
    var maxRange = range.x
    if range.y > maxRange {
      maxRange = range.y
    }
    if range.z > maxRange {
      maxRange = range.z
    }
    
    // Create three points along the data plane
    let leftUpPointInObjectCoordinates = GLKVector4Make((minCoordinates.x-midCoordinates.x)/maxRange, (maxCoordinates.y-midCoordinates.y)/maxRange, 0.0, 1.0)
    let rightUpPointInObjectCoordinates = GLKVector4Make((maxCoordinates.x-midCoordinates.x)/maxRange, (maxCoordinates.y-midCoordinates.y)/maxRange, 0.0, 1.0)
    let centreDownPointInObjectCoordinates = GLKVector4Make(0.0, (minCoordinates.y-midCoordinates.y)/maxRange, 0.0, 1.0)
    
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
//    Swift.print("reshape()")
//    Swift.print("View bounds: height = \(bounds.size.height), width = \(bounds.size.width)")
    super.reshape()
    glViewport(0, 0, GLsizei(bounds.size.width), GLsizei(bounds.size.height))
    projection = GLKMatrix4MakePerspective(fieldOfView, 1.0/Float(bounds.size.height/bounds.size.width), 0.001, 100.0)
    let mvp = GLKMatrix4Multiply(projection, GLKMatrix4Multiply(view, model))
    mvpArray = [mvp.m00, mvp.m01, mvp.m02, mvp.m03,
                mvp.m10, mvp.m11, mvp.m12, mvp.m13,
                mvp.m20, mvp.m21, mvp.m22, mvp.m23,
                mvp.m30, mvp.m31, mvp.m32, mvp.m33]
  }
  
  func renderFrame() {
//    Swift.print("renderFrame()")
    
    openGLContext!.makeCurrentContext()
    CGLLockContext(openGLContext!.cglContextObj!)
    
    glClearColor(1.0, 1.0, 1.0, 1.0)
    glEnable(GLenum(GL_DEPTH_TEST))
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT) | GLbitfield(GL_DEPTH_BUFFER_BIT))
    
    glUseProgram(program)
    
    mArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformM, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    mvpArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformMVP, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    mitArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix3fv(uniformMIT, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    viArray.withUnsafeBufferPointer { pointer in
      glUniformMatrix4fv(uniformVI, 1, GLboolean(GL_FALSE), pointer.baseAddress)
    }
    
    glEnableVertexAttribArray(GLuint(attributeCoordinates))
    glEnableVertexAttribArray(GLuint(attributeNormals))
    
    for faceType in facesColour {
      for faceSubtype in faceType.value {
        glUniform4f(uniformColour, faceSubtype.value[0], faceSubtype.value[1], faceSubtype.value[2], faceSubtype.value[3])
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboFaces[faceType.key]![faceSubtype.key]!)
        glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
        glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
        var sizeInBytes: GLint = 0
        glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &sizeInBytes)
        let vertices: GLsizei = sizeInBytes/GLint(MemoryLayout<GLfloat>.size)
//        Swift.print("Drawing \(vertices/6) \(faceType.key) \(faceSubtype.key) triangles")
        glDrawArrays(GLenum(GL_TRIANGLES), 0, vertices)
        if glGetError() != GLenum(GL_NO_ERROR) {
          Swift.print("Rendering \(faceType.key) \(faceSubtype.key): some error occurred!")
        }
      }
    }
    
    glUniform4f(uniformColour, selectionFacesColour[0], selectionFacesColour[1], selectionFacesColour[2], selectionFacesColour[3])
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboSelectionFaces)
    glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: UInt(0)))
    glVertexAttribPointer(GLuint(attributeNormals), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(6*MemoryLayout<GLfloat>.size), UnsafeRawPointer(bitPattern: 3*MemoryLayout<GLfloat>.size))
    var sizeInBytes: GLint = 0
    glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &sizeInBytes)
    var vertices = sizeInBytes/GLint(MemoryLayout<GLfloat>.size)
//        Swift.print("Drawing \(vertices/6) selection triangles")
    glDrawArrays(GLenum(GL_TRIANGLES), 0, vertices)
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Rendering selection faces: some error occurred!")
    }
    
    glDisableVertexAttribArray(GLuint(attributeNormals))
    
    if (viewEdges) {
      glUniform4f(uniformColour, selectionEdgesColour[0], selectionEdgesColour[1], selectionEdgesColour[2], selectionEdgesColour[3])
      glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboSelectionEdges)
      glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
      glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &sizeInBytes)
      vertices = sizeInBytes/GLint(MemoryLayout<GLfloat>.size)
//      Swift.print("Drawing \(vertices/2) selection edges")
      glDrawArrays(GLenum(GL_LINES), 0, vertices)
      if glGetError() != GLenum(GL_NO_ERROR) {
        Swift.print("Rendering selection edges: some error occurred!")
      }
      
      glUniform4f(uniformColour, edgesColour[0], edgesColour[1], edgesColour[2], edgesColour[3])
      glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboEdges)
      glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
      glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &sizeInBytes)
      vertices = sizeInBytes/GLint(MemoryLayout<GLfloat>.size)
//      Swift.print("Drawing \(vertices/2) edges")
      glDrawArrays(GLenum(GL_LINES), 0, vertices)
      if glGetError() != GLenum(GL_NO_ERROR) {
        Swift.print("Rendering edges: some error occurred!")
      }
    }
    
    if (viewBoundingBox) {
      glUniform4f(uniformColour, boundingBoxColour[0], boundingBoxColour[1], boundingBoxColour[2], boundingBoxColour[3])
      glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboBoundingBox)
      glVertexAttribPointer(GLuint(attributeCoordinates), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, UnsafeRawPointer(bitPattern: UInt(0)))
      glGetBufferParameteriv(GLenum(GL_ARRAY_BUFFER), GLenum(GL_BUFFER_SIZE), &sizeInBytes)
      vertices = sizeInBytes/GLint(MemoryLayout<GLfloat>.size)
//    Swift.print("Drawing \(vertices/2) bounding box edges")
      glDrawArrays(GLenum(GL_LINES), 0, vertices)
      if glGetError() != GLenum(GL_NO_ERROR) {
        Swift.print("Rendering bounding box: some error occurred!")
      }
    }
    
    glDisableVertexAttribArray(GLuint(attributeCoordinates))
    
    CGLFlushDrawable(openGLContext!.cglContextObj!)
    CGLUnlockContext(openGLContext!.cglContextObj!)
  }
  
  func pullData() {
    let startTime = CACurrentMediaTime()
    
    // Compute midCoordinates and maxRange
    let minCoordinates = GLKVector3Make(dataStorage!.minCoordinates[0], dataStorage!.minCoordinates[1], dataStorage!.minCoordinates[2])
    let maxCoordinates = GLKVector3Make(dataStorage!.maxCoordinates[0], dataStorage!.maxCoordinates[1], dataStorage!.maxCoordinates[2])
    let range = GLKVector3Subtract(maxCoordinates, minCoordinates)
    let midCoordinates = GLKVector3Add(minCoordinates, GLKVector3MultiplyScalar(range, 0.5))
    var maxRange = range.x
    if range.y > maxRange {
      maxRange = range.y
    }
    if range.z > maxRange {
      maxRange = range.z
    }
    
    for faceType in faceTriangles.triangleListOfType {
      for faceSubtype in faceType.value.triangleListOfSubtype {
        faceTriangles.triangleListOfType[faceType.key]!.triangleListOfSubtype[faceSubtype.key]!.triangles.removeAll(keepingCapacity: true)
      }
    }
    edges.removeAll(keepingCapacity: true)
    boundingBox.removeAll(keepingCapacity: true)
    selectionFaces.removeAll(keepingCapacity: true)
    selectionEdges.removeAll(keepingCapacity: true)
    
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
    boundingBox.append(contentsOf: boundingBoxVertices)
    
    for object in dataStorage!.objects {
      if !faceTriangles.triangleListOfType.keys.contains(object.type) {
        faceTriangles.triangleListOfType[object.type] = TriangleListsBySubtype()
      }
      
      if dataStorage!.selection.contains(object.id) {
        let numberOfVertices = object.edgesBuffer.count/3
        for vertexIndex in 0..<numberOfVertices {
          selectionEdges.append(contentsOf: [(object.edgesBuffer[3*vertexIndex]-midCoordinates.x)/maxRange,
                                             (object.edgesBuffer[3*vertexIndex+1]-midCoordinates.y)/maxRange,
                                             (object.edgesBuffer[3*vertexIndex+2]-midCoordinates.z)/maxRange])
        }
        for triangleBufferType in object.triangleBuffersByType.keys {
          if object.triangleBuffersByType.keys.contains(triangleBufferType) {
            let numberOfVertices = object.triangleBuffersByType[triangleBufferType]!.count/6
            let currentTriangleBuffer = object.triangleBuffersByType[triangleBufferType]!
            for vertexIndex in 0..<numberOfVertices {
              selectionFaces.append(contentsOf: [(currentTriangleBuffer[6*vertexIndex]-midCoordinates.x)/maxRange,
                                                 (currentTriangleBuffer[6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                 (currentTriangleBuffer[6*vertexIndex+2]-midCoordinates.z)/maxRange,
                                                 currentTriangleBuffer[6*vertexIndex+3],
                                                 currentTriangleBuffer[6*vertexIndex+4],
                                                 currentTriangleBuffer[6*vertexIndex+5]])
            }
          }
        }
      } else {
        let numberOfVertices = object.edgesBuffer.count/3
        for vertexIndex in 0..<numberOfVertices {
          edges.append(contentsOf: [(object.edgesBuffer[3*vertexIndex]-midCoordinates.x)/maxRange,
                                    (object.edgesBuffer[3*vertexIndex+1]-midCoordinates.y)/maxRange,
                                    (object.edgesBuffer[3*vertexIndex+2]-midCoordinates.z)/maxRange])
        }
        for triangleBufferType in object.triangleBuffersByType.keys {
          if !faceTriangles.triangleListOfType[object.type]!.triangleListOfSubtype.keys.contains(triangleBufferType) {
            faceTriangles.triangleListOfType[object.type]!.triangleListOfSubtype[triangleBufferType] = TriangleList()
          }
          let numberOfVertices = object.triangleBuffersByType[triangleBufferType]!.count/6
          var temporaryBuffer = ContiguousArray<GLfloat>()
          let currentTriangleBuffer = object.triangleBuffersByType[triangleBufferType]!
          for vertexIndex in 0..<numberOfVertices {
            temporaryBuffer.append(contentsOf: [(object.triangleBuffersByType[triangleBufferType]![6*vertexIndex]-midCoordinates.x)/maxRange,
                                                (currentTriangleBuffer[6*vertexIndex+1]-midCoordinates.y)/maxRange,
                                                (currentTriangleBuffer[6*vertexIndex+2]-midCoordinates.z)/maxRange,
                                                currentTriangleBuffer[6*vertexIndex+3],
                                                currentTriangleBuffer[6*vertexIndex+4],
                                                currentTriangleBuffer[6*vertexIndex+5]])
          }
          faceTriangles.triangleListOfType[object.type]!.triangleListOfSubtype[triangleBufferType]!.triangles.append(contentsOf: temporaryBuffer)
        }
      }
    }
    
    openGLContext!.makeCurrentContext()
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("There's a previous OpenGL error")
    }
    
    for faceType in faceTriangles.triangleListOfType {
      for faceSubtype in faceType.value.triangleListOfSubtype {
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboFaces[faceType.key]![faceSubtype.key]!)
        faceSubtype.value.triangles.withUnsafeBufferPointer { pointer in
          glBufferData(GLenum(GL_ARRAY_BUFFER), faceSubtype.value.triangles.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        if glGetError() != GLenum(GL_NO_ERROR) {
          Swift.print("Loading \(faceType.key) \(faceSubtype.key) into memory: some error occurred!")
        }
      }
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboEdges)
    edges.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), edges.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading edges into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboBoundingBox)
    boundingBox.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), boundingBox.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading bounding box edges into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboSelectionFaces)
    selectionFaces.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), selectionFaces.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading selection triangles into memory: some error occurred!")
    }
    
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vboSelectionEdges)
    selectionEdges.withUnsafeBufferPointer { pointer in
      glBufferData(GLenum(GL_ARRAY_BUFFER), selectionEdges.count*MemoryLayout<GLfloat>.size, pointer.baseAddress, GLenum(GL_DYNAMIC_DRAW))
    }
    if glGetError() != GLenum(GL_NO_ERROR) {
      Swift.print("Loading selection edges into memory: some error occurred!")
    }
    
    Swift.print("Loaded triangles: ", separator: "", terminator: "")
    for faceType in faceTriangles.triangleListOfType {
      for faceSubtype in faceType.value.triangleListOfSubtype {
        Swift.print("\(faceSubtype.value.triangles.count/18) from \(faceType.key) \(faceSubtype.key)", separator: "", terminator: ", ")
      }
    }
    Swift.print("and \(selectionFaces.count/18) from selected objects.")
    Swift.print("Loaded \(edges.count/6) edges, \(boundingBox.count/6) edges from the bounding box and \(selectionEdges.count/6) edges from the selection.")
    Swift.print("Pulled data in \(CACurrentMediaTime()-startTime) seconds.")
  }
  
  override func draw(_ dirtyRect: NSRect) {
//    Swift.print("draw(NSRect)")
    super.draw(dirtyRect)
    renderFrame()
  }
  
  deinit {
    Swift.print("deinit")
    
//    CVDisplayLinkStop(displayLink!)
    
    glDeleteProgram(program)
    for faceType in vboFaces {
      for faceSubtype in faceType.value {
        glDeleteBuffers(1, &vboFaces[faceType.key]![faceSubtype.key]!)
      }
    }
    glDeleteBuffers(1, &vboEdges)
    glDeleteBuffers(1, &vboBoundingBox)
    glDeleteBuffers(1, &vboSelectionFaces)
    glDeleteBuffers(1, &vboSelectionEdges)
  }
}
