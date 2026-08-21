import UIKit
import Metal
import MetalKit
import UniformTypeIdentifiers

class MainViewController: UIViewController, MTKViewDelegate {

    // MARK: Data manager
    lazy var dataManager: DataManagerWrapperWrapper = DataManagerWrapperWrapper()!

    // MARK: Metal
    var metalView: MTKView!
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var library: MTLLibrary!

    var litRenderPipelineState: MTLRenderPipelineState?
    var texturedRenderPipelineState: MTLRenderPipelineState?
    var unlitRenderPipelineState: MTLRenderPipelineState?
    var edgeRenderPipelineState: MTLRenderPipelineState?
    var pickingRenderPipelineState: MTLRenderPipelineState?
    var depthStencilState: MTLDepthStencilState?

    var loadedTextures: [String: MTLTexture] = [:]
    var failedTexturePaths: Set<String> = []
    var textureLoader: MTKTextureLoader?
    var textureSamplerState: MTLSamplerState?
    var grantedTextureDirectoryURL: URL?
    var openedFileURL: URL?

    var msaaTexture: MTLTexture?
    var msaaDepthTexture: MTLTexture?
    var depthTexture: MTLTexture?
    var pickingTexture: MTLTexture?
    var pickingDepthTexture: MTLTexture?

    var triangleBuffers = [BufferWithColour]()
    var edgeBuffers = [BufferWithColour]()
    var boundingBoxBuffer: MTLBuffer?
    var selectionStateBuffer: MTLBuffer?
    var selectionStateCount: Int = 0
    var visibleStateBuffer: MTLBuffer?
    var visibleStateCount: Int = 0

    var constants = Constants()

    // MARK: Camera (matches macOS MetalView)
    var eye = SIMD3<Float>(0.0, 0.0, 0.0)
    var centre = SIMD3<Float>(0.0, 0.0, -1.0)
    var fieldOfView: Float = 1.047197551196598

    var modelTranslationToCentreOfRotationMatrix = matrix_identity_float4x4
    var modelRotationMatrix = matrix_identity_float4x4
    var modelShiftBackMatrix = matrix_identity_float4x4

    var modelMatrix = matrix_identity_float4x4
    var viewMatrix = matrix_identity_float4x4
    var projectionMatrix = matrix_identity_float4x4

    // MARK: Scene state
    var showingBBox = false
    var selectionColour = SIMD4<Float>(1.0, 1.0, 0.0, 0.7)
    var customLightClearColor: MTLClearColor?
    var customDarkClearColor: MTLClearColor?
    let depthFormat = MTLPixelFormat.depth32Float
    var isDarkMode: Bool { traitCollection.userInterfaceStyle == .dark }

    // MARK: Appearance
    var showTextures: Bool = false
    var currentAppearanceTheme: String = ""

    // MARK: Floating buttons
    var openButton: UIView!
    var objectsButton: UIView!
    var lodButton: UIView!
    var appearanceButton: UIView!
    var homeButton: UIView!
    private var openButtonControl: UIButton!

    // MARK: Empty state
    var emptyStateView: UIView!

    // MARK: Status bar
    var statusBarView: UIView!
    var progressBar: UIProgressView!
    var statusLabel: UILabel!

    // MARK: LoD filter
    var currentLodFilter: String = ""

    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        dataManager.controller = self

        device = MTLCreateSystemDefaultDevice()
        guard device != nil else {
            showMessage("Metal not available on simulator.\nRun on a real device to see the 3D view.")
            setupFloatingButtons()
            return
        }
        commandQueue = device.makeCommandQueue()
        library = device.makeDefaultLibrary()

        setupMetal()
        setupEmptyState()
        setupFloatingButtons()
        setupStatusBar()
        setupGestures()
        setupCamera()

        recreatePipelines()
        createPickingTextures()

        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
    }

    func showMessage(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .white
        label.font = .systemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
        ])
    }

    func setupEmptyState() {
        emptyStateView = UIView()
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            emptyStateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        let icon = UIImageView(image: UIImage(named: "AzulIcon"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        emptyStateView.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "azul"
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        emptyStateView.addSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "3D city model viewer"
        subtitleLabel.font = .systemFont(ofSize: 17)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        emptyStateView.addSubview(subtitleLabel)

        let descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.text = "Open a CityJSON, CityGML, OBJ, OFF or POLY file to view your model."
        descriptionLabel.font = .systemFont(ofSize: 15)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        emptyStateView.addSubview(descriptionLabel)

        let openButton: UIButton = {
            var config = UIButton.Configuration.filled()
            config.title = "  Open File"
            config.image = UIImage(systemName: "doc")
            config.baseForegroundColor = .white
            config.baseBackgroundColor = UIColor(white: 0, alpha: 0.4)
            config.background.cornerRadius = 12
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
            let button = UIButton(configuration: config)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(openFile), for: .touchUpInside)
            return button
        }()
        emptyStateView.addSubview(openButton)

        let hintLabel = UILabel()
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = "— or tap the 📄 button to open —"
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center
        emptyStateView.addSubview(hintLabel)

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, subtitleLabel, descriptionLabel, openButton, hintLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        emptyStateView.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),

            stack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor, constant: -30),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyStateView.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: emptyStateView.trailingAnchor, constant: -40),

            openButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    func hideEmptyState() {
        guard emptyStateView != nil, !emptyStateView.isHidden else { return }
        UIView.animate(withDuration: 0.3) {
            self.emptyStateView.alpha = 0
        } completion: { _ in
            self.emptyStateView.isHidden = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalView?.frame = view.bounds
    }

    func animateSelectionPulse() {
        constants.selectionColour.w = 1.0
        metalView?.setNeedsDisplay()

        let steps = 6
        let stepDuration = 0.05
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * stepDuration) { [weak self] in
                guard let self = self else { return }
                let progress = Float(i) / Float(steps)
                self.constants.selectionColour.w = 1.0 - (1.0 - 0.7) * progress
                self.metalView?.setNeedsDisplay()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateAppearance()
        }
    }

    func updateAppearance() {
        if isDarkMode {
            if let custom = customDarkClearColor {
                metalView.clearColor = custom
            } else {
                metalView.clearColor = MTLClearColorMake(0.15, 0.15, 0.20, 1.0)
            }
        } else {
            if let custom = customLightClearColor {
                metalView.clearColor = custom
            } else {
                metalView.clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0)
            }
        }
    }

    // MARK: Metal setup
    func setupMetal() {
        metalView = MTKView(frame: view.bounds, device: device)
        metalView.delegate = self
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalView.clearColor = MTLClearColorMake(0.15, 0.15, 0.20, 1.0)
        metalView.sampleCount = 1
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.autoresizesSubviews = true
        view.addSubview(metalView)
        view.sendSubviewToBack(metalView)

        updateAppearance()

        textureLoader = MTKTextureLoader(device: device)

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .linear
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        samplerDesc.normalizedCoordinates = true
        textureSamplerState = device.makeSamplerState(descriptor: samplerDesc)

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)

        createDepthTexture(size: metalView.drawableSize)
    }

    func createDepthTexture(size: CGSize) {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthFormat, width: w, height: h, mipmapped: false)
        desc.storageMode = .private
        desc.usage = .renderTarget
        depthTexture = device.makeTexture(descriptor: desc)
    }

    func setupCamera() {
        modelShiftBackMatrix = matrix4x4_translation(shift: centre)
        modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
        viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: SIMD3<Float>(0.0, 1.0, 0.0))
        projectionMatrix = matrix4x4_perspective_shorter_dim(fieldOfView: fieldOfView, width: Float(metalView.bounds.size.width), height: Float(metalView.bounds.size.height), nearZ: 0.001, farZ: 100.0)
        constants.modelMatrix = modelMatrix
        constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
        constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
        constants.viewMatrixInverse = viewMatrix.inverse
    }

    // MARK: Pipelines
    func recreatePipelines() {
        guard let library = library else { return }

        let litDesc = MTLRenderPipelineDescriptor()
        litDesc.vertexFunction = library.makeFunction(name: "vertexLit")
        litDesc.fragmentFunction = library.makeFunction(name: "fragmentLit")
        litDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        litDesc.colorAttachments[0].isBlendingEnabled = true
        litDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        litDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        litDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        litDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        litDesc.depthAttachmentPixelFormat = depthFormat
        litDesc.rasterSampleCount = metalView.sampleCount

        let texturedDesc = MTLRenderPipelineDescriptor()
        texturedDesc.vertexFunction = library.makeFunction(name: "vertexLitTextured")
        texturedDesc.fragmentFunction = library.makeFunction(name: "fragmentLitTextured")
        texturedDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        texturedDesc.colorAttachments[0].isBlendingEnabled = true
        texturedDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        texturedDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        texturedDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        texturedDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        texturedDesc.depthAttachmentPixelFormat = depthFormat
        texturedDesc.rasterSampleCount = metalView.sampleCount

        let unlitDesc = MTLRenderPipelineDescriptor()
        unlitDesc.vertexFunction = library.makeFunction(name: "vertexUnlit")
        unlitDesc.fragmentFunction = library.makeFunction(name: "fragmentUnlit")
        unlitDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        unlitDesc.colorAttachments[0].isBlendingEnabled = false
        unlitDesc.depthAttachmentPixelFormat = depthFormat
        unlitDesc.rasterSampleCount = metalView.sampleCount

        let edgeDesc = MTLRenderPipelineDescriptor()
        edgeDesc.vertexFunction = library.makeFunction(name: "vertexEdge")
        edgeDesc.fragmentFunction = library.makeFunction(name: "fragmentEdge")
        edgeDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        edgeDesc.colorAttachments[0].isBlendingEnabled = false
        edgeDesc.depthAttachmentPixelFormat = depthFormat
        edgeDesc.rasterSampleCount = metalView.sampleCount

        let pickDesc = MTLRenderPipelineDescriptor()
        pickDesc.vertexFunction = library.makeFunction(name: "vertexPicking")
        pickDesc.fragmentFunction = library.makeFunction(name: "fragmentPicking")
        pickDesc.colorAttachments[0].pixelFormat = .rgba8Unorm
        pickDesc.depthAttachmentPixelFormat = depthFormat
        pickDesc.rasterSampleCount = 1

        do {
            litRenderPipelineState = try device.makeRenderPipelineState(descriptor: litDesc)
            texturedRenderPipelineState = try device.makeRenderPipelineState(descriptor: texturedDesc)
            unlitRenderPipelineState = try device.makeRenderPipelineState(descriptor: unlitDesc)
            edgeRenderPipelineState = try device.makeRenderPipelineState(descriptor: edgeDesc)
            pickingRenderPipelineState = try device.makeRenderPipelineState(descriptor: pickDesc)
        } catch {
            print("Pipeline error: \(error)")
        }
    }

    // MARK: MSAA
    func createMSAATextures(size: CGSize) {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else { return }
        let sampleCount = metalView.sampleCount
        msaaTexture = nil
        msaaDepthTexture = nil
        if sampleCount > 1 {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: metalView.colorPixelFormat, width: w, height: h, mipmapped: false)
            desc.textureType = .type2DMultisample
            desc.sampleCount = sampleCount
            desc.usage = .renderTarget
            desc.storageMode = .private
            msaaTexture = device.makeTexture(descriptor: desc)

            let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthFormat, width: w, height: h, mipmapped: false)
            depthDesc.textureType = .type2DMultisample
            depthDesc.sampleCount = sampleCount
            depthDesc.usage = .renderTarget
            depthDesc.storageMode = .private
            msaaDepthTexture = device.makeTexture(descriptor: depthDesc)

            if msaaTexture == nil || msaaDepthTexture == nil {
                metalView.sampleCount = 1
                msaaTexture = nil
                msaaDepthTexture = nil
                recreatePipelines()
            }
        }
    }

    func createPickingTextures() {
        let w = Int(metalView.drawableSize.width)
        let h = Int(metalView.drawableSize.height)
        guard w > 0, h > 0 else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        pickingTexture = device.makeTexture(descriptor: desc)

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthFormat, width: w, height: h, mipmapped: false)
        depthDesc.storageMode = .private
        depthDesc.usage = .renderTarget
        pickingDepthTexture = device.makeTexture(descriptor: depthDesc)
    }

    // MARK: MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        createDepthTexture(size: size)
        createPickingTextures()
        projectionMatrix = matrix4x4_perspective_shorter_dim(fieldOfView: fieldOfView, width: Float(size.width), height: Float(size.height), nearZ: 0.001, farZ: 100.0)
        constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
    }

    func draw(in view: MTKView) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let drawable = view.currentDrawable else { return }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.colorAttachments[0].clearColor = metalView.clearColor
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.depthAttachment.clearDepth = 1.0

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        encoder.setFrontFacing(.counterClockwise)
        encoder.setDepthStencilState(depthStencilState)
        if let selBuffer = selectionStateBuffer, selectionStateCount > 0 {
            encoder.setFragmentBuffer(selBuffer, offset: 0, index: 2)
        } else {
            var zero: Float = 0
            encoder.setFragmentBytes(&zero, length: MemoryLayout<Float>.size, index: 2)
        }
        if let visBuffer = visibleStateBuffer, visibleStateCount > 0 {
            encoder.setFragmentBuffer(visBuffer, offset: 0, index: 3)
        } else {
            var one: Float = 1
            encoder.setFragmentBytes(&one, length: MemoryLayout<Float>.size, index: 3)
        }

        let drawVertices: (BufferWithColour) -> Void = { tb in
            encoder.setVertexBuffer(tb.buffer, offset: 0, index: 0)
            self.constants.colour = tb.colour
            encoder.setVertexBytes(&self.constants, length: MemoryLayout<Constants>.size, index: 1)
            encoder.setFragmentBytes(&self.constants, length: MemoryLayout<Constants>.size, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: tb.indexCount, indexType: .uint32, indexBuffer: tb.indexBuffer, indexBufferOffset: 0)
        }

        func drawPass(where opacityCondition: (Float) -> Bool) {
            if showTextures, let texturedPipeline = texturedRenderPipelineState {
                encoder.setRenderPipelineState(texturedPipeline)
                for i in triangleBuffers.indices where opacityCondition(triangleBuffers[i].colour.w) && !triangleBuffers[i].texturePath.isEmpty {
                    if triangleBuffers[i].texture == nil {
                        triangleBuffers[i].texture = textureForPath(triangleBuffers[i].texturePath)
                    }
                    if let texture = triangleBuffers[i].texture {
                        encoder.setFragmentTexture(texture, index: 0)
                        encoder.setFragmentSamplerState(textureSamplerState, index: 0)
                        drawVertices(triangleBuffers[i])
                    }
                }
            }
            encoder.setRenderPipelineState(litRenderPipelineState!)
            encoder.setFragmentTexture(nil, index: 0)
            for i in triangleBuffers.indices where opacityCondition(triangleBuffers[i].colour.w) && (!showTextures || triangleBuffers[i].texturePath.isEmpty || triangleBuffers[i].texture == nil) {
                drawVertices(triangleBuffers[i])
            }
        }

        drawPass { $0 == 1.0 }
        drawPass { $0 != 1.0 }

        // Edges
        encoder.setRenderPipelineState(edgeRenderPipelineState!)
        if let visBuffer = visibleStateBuffer, visibleStateCount > 0 {
            encoder.setFragmentBuffer(visBuffer, offset: 0, index: 2)
        } else {
            var one: Float = 1
            encoder.setFragmentBytes(&one, length: MemoryLayout<Float>.size, index: 2)
        }
        for eb in edgeBuffers {
            encoder.setVertexBuffer(eb.buffer, offset: 0, index: 0)
            var edgeColour = eb.colour
            if isDarkMode && edgeColour.x == 0 && edgeColour.y == 0 && edgeColour.z == 0 {
                edgeColour = SIMD4<Float>(1, 1, 1, 1)
            }
            constants.colour = edgeColour
            encoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
            encoder.setFragmentBytes(&constants, length: MemoryLayout<Constants>.size, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: eb.buffer.length / MemoryLayout<EdgeVertex>.size)
        }
        encoder.setRenderPipelineState(unlitRenderPipelineState!)

        // Bounding box
        if showingBBox, let bb = boundingBoxBuffer {
            encoder.setVertexBuffer(bb, offset: 0, index: 0)
            constants.colour = isDarkMode ? SIMD4<Float>(1.0, 1.0, 1.0, 1.0) : SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
            encoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: bb.length / MemoryLayout<Vertex>.size)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: Depth at centre
    func depthAtCentre() -> Float {
        guard let mins = dataManager.minCoordinates(),
              let mids = dataManager.midCoordinates(),
              let maxs = dataManager.maxCoordinates() else { return 0.0 }
        let minCoords = [mins[0], mins[1], mins[2]].map(Float.init)
        let midCoords = [mids[0], mids[1], mids[2]].map(Float.init)
        let maxCoords = [maxs[0], maxs[1], maxs[2]].map(Float.init)
        let range = Float(dataManager.maxRange())

        let leftUpPoint = SIMD4<Float>((minCoords[0]-midCoords[0])/range, (maxCoords[1]-midCoords[1])/range, 0.0, 1.0)
        let rightUpPoint = SIMD4<Float>((maxCoords[0]-midCoords[0])/range, (maxCoords[1]-midCoords[1])/range, 0.0, 1.0)
        let centreDownPoint = SIMD4<Float>(0.0, (minCoords[1]-midCoords[1])/range, 0.0, 1.0)

        let mv = matrix_multiply(viewMatrix, modelMatrix)
        let leftUp = matrix_multiply(mv, leftUpPoint)
        let rightUp = matrix_multiply(mv, rightUpPoint)
        let centreDown = matrix_multiply(mv, centreDownPoint)

        let v1 = SIMD3<Float>(leftUp.x - centreDown.x, leftUp.y - centreDown.y, leftUp.z - centreDown.z)
        let v2 = SIMD3<Float>(rightUp.x - centreDown.x, rightUp.y - centreDown.y, rightUp.z - centreDown.z)
        let cp = cross(v1, v2)
        let p3 = SIMD3<Float>(centreDown.x / centreDown.w, centreDown.y / centreDown.w, centreDown.z / centreDown.w)
        let d = -dot(cp, p3)
        return Float(-d / cp.z)
    }

    // MARK: Picking
    func pickObject(at location: CGPoint) -> Int32 {
        guard let pipeline = pickingRenderPipelineState,
              let colorTex = pickingTexture,
              let depthTex = pickingDepthTexture,
              !triangleBuffers.isEmpty else { return -1 }

        let scale: CGFloat = metalView.contentScaleFactor
        let pixelX = Int(location.x * scale)
        let pixelY = Int(location.y * scale)
        guard pixelX >= 0, pixelX < colorTex.width,
              pixelY >= 0, pixelY < colorTex.height else { return -1 }

        let cb = commandQueue.makeCommandBuffer()!

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = colorTex
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        passDesc.depthAttachment.texture = depthTex
        passDesc.depthAttachment.loadAction = .clear
        passDesc.depthAttachment.storeAction = .dontCare
        passDesc.depthAttachment.clearDepth = 1.0

        let encoder = cb.makeRenderCommandEncoder(descriptor: passDesc)!
        encoder.setRenderPipelineState(pipeline)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setDepthStencilState(depthStencilState)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(colorTex.width), height: Double(colorTex.height), znear: 0, zfar: 1))
        encoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.size, index: 1)
        if let visBuffer = visibleStateBuffer, visibleStateCount > 0 {
            encoder.setFragmentBuffer(visBuffer, offset: 0, index: 2)
        } else {
            var one: Float = 1
            encoder.setFragmentBytes(&one, length: MemoryLayout<Float>.size, index: 2)
        }

        for tb in triangleBuffers {
            encoder.setVertexBuffer(tb.buffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: tb.indexCount, indexType: .uint32, indexBuffer: tb.indexBuffer, indexBufferOffset: 0)
        }
        encoder.endEncoding()

        let stagingBuffer = device.makeBuffer(length: 4, options: .storageModeShared)!
        let blitEncoder = cb.makeBlitCommandEncoder()!
        blitEncoder.copy(from: colorTex, sourceSlice: 0, sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: pixelX, y: pixelY, z: 0),
                         sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                         to: stagingBuffer, destinationOffset: 0,
                         destinationBytesPerRow: 4, destinationBytesPerImage: 4)
        blitEncoder.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        let pixelValue = stagingBuffer.contents().load(as: UInt32.self)
        return pixelValue == 0 ? -1 : Int32(bitPattern: pixelValue) - 1
    }

    // MARK: Buffer updates (called from ObjC++ bridge)
    @objc func updateVisibleStateBuffer() {
        let cnt = Int32(dataManager.visibleStateCount())
        guard cnt > 0 else { return }
        let ptr = dataManager.visibleStateData()
        guard ptr != nil else { return }
        visibleStateCount = Int(cnt)
        let byteCount = Int(cnt) * MemoryLayout<Float>.size
        if visibleStateBuffer?.length ?? 0 >= byteCount {
            visibleStateBuffer!.contents().copyMemory(from: UnsafeRawPointer(ptr!), byteCount: byteCount)
        } else {
            visibleStateBuffer = device.makeBuffer(bytes: UnsafeRawPointer(ptr!), length: byteCount, options: [])
        }
    }

    @objc func updateSelectionStateBuffer() {
        let cnt = Int32(dataManager.selectionStateCount())
        guard cnt > 0 else { return }
        let ptr = dataManager.selectionStateData()
        guard ptr != nil else { return }
        selectionStateCount = Int(cnt)
        let byteCount = Int(cnt) * MemoryLayout<Float>.size
        if selectionStateBuffer?.length ?? 0 >= byteCount {
            selectionStateBuffer!.contents().copyMemory(from: UnsafeRawPointer(ptr!), byteCount: byteCount)
        } else {
            selectionStateBuffer = device.makeBuffer(bytes: UnsafeRawPointer(ptr!), length: byteCount, options: [])
        }
    }

    // MARK: Buffer loading from DataManager
    func reloadTriangleBuffers() {
        triangleBuffers.removeAll()
        dataManager.initialiseTriangleBufferIterator()
        while !dataManager.triangleBufferIteratorEnded() {
            var bytes: Int = 0
            guard let vertexPtr = dataManager.currentTriangleBuffer(withSize: &bytes), bytes > 0 else {
                dataManager.advanceTriangleBufferIterator()
                continue
            }
            var indexBytes: Int = 0
            guard let indexPtr = dataManager.currentTriangleBufferIndices(withSize: &indexBytes), indexBytes > 0 else {
                dataManager.advanceTriangleBufferIterator()
                continue
            }

            let colour = dataManager.currentTriangleBufferColour()
            let colourSIMD = colour != nil ? SIMD4<Float>(colour![0], colour![1], colour![2], colour![3]) : SIMD4<Float>(1, 1, 1, 1)

            var texturePathLength: Int = 0
            let firstTexturePathCharacter = UnsafeRawPointer(dataManager.currentTriangleBufferTextureURI(withLength: &texturePathLength))
            var texturePath = ""
            if let firstTexturePathCharacter = firstTexturePathCharacter, texturePathLength > 0 {
                let texturePathData = Data(bytes: firstTexturePathCharacter, count: texturePathLength * MemoryLayout<Int8>.size)
                texturePath = String(data: texturePathData, encoding: .utf8) ?? ""
            }

            let buffer = device.makeBuffer(bytes: vertexPtr, length: bytes, options: [])!
            let indexBuffer = device.makeBuffer(bytes: indexPtr, length: indexBytes, options: [])!
            let indexCount = indexBytes / MemoryLayout<UInt32>.size

            triangleBuffers.append(BufferWithColour(buffer: buffer, indexBuffer: indexBuffer, indexCount: indexCount, type: "", colour: colourSIMD, texturePath: texturePath))
            dataManager.advanceTriangleBufferIterator()
        }
    }

    func reloadEdgeBuffers() {
        edgeBuffers.removeAll()
        dataManager.initialiseEdgeBufferIterator()
        while !dataManager.edgeBufferIteratorEnded() {
            var bytes: Int = 0
            guard let vertexPtr = dataManager.currentEdgeBuffer(withSize: &bytes) else {
                dataManager.advanceEdgeBufferIterator()
                continue
            }
            let colour = dataManager.currentEdgeBufferColour()
            let colourSIMD = colour != nil ? SIMD4<Float>(colour![0], colour![1], colour![2], colour![3]) : SIMD4<Float>(0, 0, 0, 1)
            let buffer = device.makeBuffer(bytes: vertexPtr, length: bytes, options: [])!
            edgeBuffers.append(BufferWithColour(buffer: buffer, indexBuffer: buffer, indexCount: 0, type: "", colour: colourSIMD))
            dataManager.advanceEdgeBufferIterator()
        }
    }

    func regenerateBoundingBoxBuffer() {
        guard let mins = dataManager.minCoordinates(),
              let mids = dataManager.midCoordinates(),
              let maxs = dataManager.maxCoordinates() else { return }
        let minCoords = [mins[0], mins[1], mins[2]].map(Float.init)
        let midCoords = [mids[0], mids[1], mids[2]].map(Float.init)
        let maxCoords = [maxs[0], maxs[1], maxs[2]].map(Float.init)
        let range = Float(dataManager.maxRange())

        let corners: [SIMD3<Float>] = [
            SIMD3<Float>((minCoords[0]-midCoords[0])/range, (minCoords[1]-midCoords[1])/range, (minCoords[2]-midCoords[2])/range),
            SIMD3<Float>((maxCoords[0]-midCoords[0])/range, (minCoords[1]-midCoords[1])/range, (minCoords[2]-midCoords[2])/range),
            SIMD3<Float>((maxCoords[0]-midCoords[0])/range, (maxCoords[1]-midCoords[1])/range, (minCoords[2]-midCoords[2])/range),
            SIMD3<Float>((minCoords[0]-midCoords[0])/range, (maxCoords[1]-midCoords[1])/range, (minCoords[2]-midCoords[2])/range),
            SIMD3<Float>((minCoords[0]-midCoords[0])/range, (minCoords[1]-midCoords[1])/range, (maxCoords[2]-midCoords[2])/range),
            SIMD3<Float>((maxCoords[0]-midCoords[0])/range, (minCoords[1]-midCoords[1])/range, (maxCoords[2]-midCoords[2])/range),
            SIMD3<Float>((maxCoords[0]-midCoords[0])/range, (maxCoords[1]-midCoords[1])/range, (maxCoords[2]-midCoords[2])/range),
            SIMD3<Float>((minCoords[0]-midCoords[0])/range, (maxCoords[1]-midCoords[1])/range, (maxCoords[2]-midCoords[2])/range),
        ]
        let edges: [Int] = [
            0,1, 1,2, 2,3, 3,0,
            4,5, 5,6, 6,7, 7,4,
            0,4, 1,5, 2,6, 3,7,
        ]
        var vertices = [Vertex]()
        for i in edges {
            vertices.append(Vertex(position: corners[i]))
        }
        boundingBoxBuffer = vertices.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: [])
        }
    }

    // MARK: Texture loading
    func textureForPath(_ texturePath: String) -> MTLTexture? {
        if let loaded = loadedTextures[texturePath] { return loaded }
        if failedTexturePaths.contains(texturePath) { return nil }
        guard let loader = textureLoader else { return nil }

        let textureURL: URL?
        if texturePath.isEmpty {
            textureURL = nil
        } else if let url = URL(string: texturePath), url.scheme != nil {
            textureURL = url
        } else {
            textureURL = URL(fileURLWithPath: texturePath)
        }

        if let url = textureURL {
            do {
                let options: [MTKTextureLoader.Option: Any] = [
                    .origin: MTKTextureLoader.Origin.bottomLeft,
                    .SRGB: false,
                    .generateMipmaps: true
                ]
                let loaded = try loader.newTexture(URL: url, options: options)
                loadedTextures[texturePath] = loaded
                return loaded
            } catch {
                // Fallback: try loading from the granted textures directory
                if let grantedDir = grantedTextureDirectoryURL {
                    let fallbackURL = grantedDir.appendingPathComponent(url.lastPathComponent)
                    do {
                        let loaded = try loader.newTexture(URL: fallbackURL, options: [
                            .origin: MTKTextureLoader.Origin.bottomLeft,
                            .SRGB: false,
                            .generateMipmaps: true
                        ])
                        loadedTextures[texturePath] = loaded
                        return loaded
                    } catch {
                        // Both attempts failed
                    }
                }
                failedTexturePaths.insert(texturePath)
                print("Texture load failed (\(texturePath)): \(error.localizedDescription)")
                return nil
            }
        }
        failedTexturePaths.insert(texturePath)
        return nil
    }

    func primeTexturesForCurrentBuffers() {
        for i in triangleBuffers.indices where !triangleBuffers[i].texturePath.isEmpty {
            triangleBuffers[i].texture = textureForPath(triangleBuffers[i].texturePath)
        }
    }

    // MARK: Appearance
    func requestTextureDirectoryAccessIfNeeded() {
        guard !failedTexturePaths.isEmpty, grantedTextureDirectoryURL == nil else { return }
        let samplePath = failedTexturePaths.first ?? ""
        let dirName = (samplePath as NSString).deletingLastPathComponent
        let alert = UIAlertController(
            title: "Texture Access Needed",
            message: "This file references textures that couldn't be loaded. Would you like to select the textures folder (\(dirName))?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Select Folder", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            picker.delegate = self
            picker.allowsMultipleSelection = false
            self.present(picker, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        present(alert, animated: true)
    }

    func refreshAppearanceRendering() {
        let appearancesEnabled = showTextures
        dataManager.setUseAppearances(appearancesEnabled)
        currentAppearanceTheme.withCString { pointer in
            dataManager.setAppearanceTheme(pointer)
        }
        dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
        reloadTriangleBuffers()
        dataManager.updateVisibleStates()
        updateVisibleStateBuffer()
        dataManager.updateSelectionStates()
        updateSelectionStateBuffer()
        if appearancesEnabled {
            failedTexturePaths.removeAll()
            primeTexturesForCurrentBuffers()
            requestTextureDirectoryAccessIfNeeded()
        }
        dataManager.regenerateEdgeBuffers(withMaximumSize: 16 * 1024 * 1024)
        reloadEdgeBuffers()
        metalView?.setNeedsDisplay()
    }

    @objc func showAppearancePicker() {
        var themes = Set(dataManager.availableAppearanceThemes() ?? [])
        if themes.contains("Materials") && themes.contains("Textures") {
            themes.remove("visual")
        }
        let sortedThemes = themes.sorted()

        let picker = AppearancePickerViewController()
        picker.availableThemes = sortedThemes
        picker.currentType = showTextures ? "theme" : "semantics"
        picker.currentTheme = currentAppearanceTheme
        picker.delegate = self
        picker.title = "Appearance"

        let nav = UINavigationController(rootViewController: picker)
        if UIDevice.current.userInterfaceIdiom == .pad {
            nav.modalPresentationStyle = .popover
            if let popover = nav.popoverPresentationController {
                popover.sourceView = appearanceButton
                popover.permittedArrowDirections = .down
            }
        } else {
            nav.modalPresentationStyle = .pageSheet
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }

    // MARK: File loading
    func loadFile(url: URL) {
        openedFileURL?.stopAccessingSecurityScopedResource()
        let accessGranted = url.startAccessingSecurityScopedResource()
        openedFileURL = accessGranted ? url : nil
        let path = url.path
        addRecentFile(url)
        updateOpenButtonMenu()
        let totalWeight: Float = 75.165239
        var progress: Float = 0
        DispatchQueue.main.async {
            self.updateStatus(message: "Loading \(url.lastPathComponent)...", progress: 0)
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard FileManager.default.fileExists(atPath: path) else {
                DispatchQueue.main.async {
                    self.updateStatus(message: "File not found", progress: 0)
                    self.hideStatusBar()
                }
                return
            }
            self.dataManager.parse(path)
            progress += 20.071734 / totalWeight
            DispatchQueue.main.async { self.progressBar.setProgress(progress, animated: true) }

            self.dataManager.clearHelpers()
            progress += 0.51605 / totalWeight
            DispatchQueue.main.async { self.progressBar.setProgress(progress, animated: true) }

            self.dataManager.transformGeographicCoordinates()

            self.dataManager.updateBoundsWithLastFile()
            progress += 0.158675 / totalWeight
            DispatchQueue.main.async { self.progressBar.setProgress(progress, animated: true) }

            self.dataManager.triangulateLastFile()
            progress += 45.400172 / totalWeight
            DispatchQueue.main.async { self.progressBar.setProgress(progress, animated: true) }

            self.dataManager.generateEdgesForLastFile()
            progress += 1.150533 / totalWeight
            DispatchQueue.main.async { self.progressBar.setProgress(progress, animated: true) }

            self.dataManager.clearPolygonsOfLastFile()
            progress += 0.359982 / totalWeight
            DispatchQueue.main.async { self.progressBar.setProgress(progress, animated: true) }

            self.dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
            progress += 3.535023 / totalWeight
            DispatchQueue.main.async { self.progressBar.setProgress(progress, animated: true) }

            self.dataManager.regenerateEdgeBuffers(withMaximumSize: 16 * 1024 * 1024)
            progress += 2.085606 / totalWeight
            DispatchQueue.main.async { self.progressBar.setProgress(progress, animated: true) }

            DispatchQueue.main.async {
                self.reloadTriangleBuffers()
                progress += 1.31523 / totalWeight
                self.progressBar.setProgress(progress, animated: true)

                self.reloadEdgeBuffers()
                progress += 0.572072 / totalWeight
                self.progressBar.setProgress(progress, animated: true)

                self.regenerateBoundingBoxBuffer()
                progress += 0.000162 / totalWeight
                self.progressBar.setProgress(progress, animated: true)

                self.dataManager.updateVisibleStates()
                self.updateVisibleStateBuffer()
                self.dataManager.updateSelectionStates()
                self.updateSelectionStateBuffer()

                self.showTextures = false
                self.currentAppearanceTheme = ""
                self.dataManager.setAppearanceTheme("")
                self.dataManager.setUseAppearances(false)

                let lods = self.dataManager.availableLods() ?? []
                if !lods.isEmpty {
                    self.currentLodFilter = "__highest__"
                    "__highest__".withCString { pointer in
                        self.dataManager.setLodFilter(pointer)
                    }
                    self.dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
                    self.reloadTriangleBuffers()
                    self.dataManager.updateVisibleStates()
                    self.updateVisibleStateBuffer()
                    self.dataManager.updateSelectionStates()
                    self.updateSelectionStateBuffer()
                    self.dataManager.regenerateEdgeBuffers(withMaximumSize: 16 * 1024 * 1024)
                    self.reloadEdgeBuffers()
                }

                self.statusLabel.text = self.dataManager.statusMessage() ?? "Done"
                self.hideStatusBar()
                self.hideEmptyState()
                NotificationCenter.default.post(name: Notification.Name("AzulFileLoaded"), object: nil)
            }
        }
    }

    // MARK: Gesture recognizers
    func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
        metalView.addGestureRecognizer(pan)

        let orbitGesture = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbitGesture.minimumNumberOfTouches = 2
        metalView.addGestureRecognizer(orbitGesture)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        metalView.addGestureRecognizer(pinch)

        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotation.delegate = self
        metalView.addGestureRecognizer(rotation)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        metalView.addGestureRecognizer(tap)

        metalView.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    func updateConstants() {
        constants.modelMatrix = modelMatrix
        constants.modelViewProjectionMatrix = matrix_multiply(projectionMatrix, matrix_multiply(viewMatrix, modelMatrix))
        constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: modelMatrix).inverse.transpose
        constants.viewMatrixInverse = viewMatrix.inverse
    }

    func orbit(angleX: Float, angleY: Float) {
        let forward = normalize(centre - eye)
        let right = normalize(cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = SIMD3<Float>(0, 1, 0)
        let rx = matrix4x4_rotation(angle: angleX, axis: right)
        let ry = matrix4x4_rotation(angle: angleY, axis: up)
        let rotatedForward = (ry * rx) * simd_float4(forward.x, forward.y, forward.z, 0)
        let distance = simd_length(centre - eye)
        eye = centre - simd_float3(rotatedForward.x, rotatedForward.y, rotatedForward.z) * distance
        viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: up)
        updateConstants()
    }

    @objc func handleOrbit(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let translation = gesture.translation(in: metalView)
        let viewSize = metalView.bounds.size
        let sensitivity = Float.pi / Float(min(viewSize.width, viewSize.height))
        orbit(angleX: Float(-translation.y) * sensitivity, angleY: Float(-translation.x) * sensitivity)
        gesture.setTranslation(.zero, in: metalView)
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let translation = gesture.translation(in: metalView)
        let distance = simd_length(centre - eye)
        let sensitivity: Float = 0.003 * (fieldOfView / (.pi / 4)) * distance
        let motionInCamera = SIMD3<Float>(sensitivity * Float(-translation.x), sensitivity * Float(translation.y), 0)
        let cameraToWorld = matrix_upper_left_3x3(matrix: viewMatrix).inverse
        let motionInWorld = matrix_multiply(cameraToWorld, motionInCamera)
        eye += motionInWorld
        centre += motionInWorld
        viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: SIMD3<Float>(0, 1, 0))
        updateConstants()
        gesture.setTranslation(.zero, in: metalView)
    }

    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            let mag: Float = 1.0 + Float(gesture.scale - 1.0)
            fieldOfView = 2.0 * atanf(tanf(0.5 * fieldOfView) / mag)
            let w = Float(metalView.drawableSize.width)
            let h = Float(metalView.drawableSize.height)
            projectionMatrix = matrix4x4_perspective_shorter_dim(fieldOfView: fieldOfView, width: w, height: h, nearZ: 0.001, farZ: 100.0)
            updateConstants()
            gesture.scale = 1.0
        }
    }

    @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .changed {
            let axisInCamera = SIMD3<Float>(0.0, 0.0, 1.0)
            let cameraToObject = matrix_upper_left_3x3(matrix: matrix_multiply(viewMatrix, modelMatrix)).inverse
            let axisInObject = matrix_multiply(cameraToObject, axisInCamera)
            modelRotationMatrix = matrix_multiply(modelRotationMatrix, matrix4x4_rotation(angle: Float(-gesture.rotation), axis: axisInObject))
            modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
            updateConstants()
            gesture.rotation = 0
        }
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: metalView)
        let objectId = pickObject(at: location)
        if objectId >= 0 {
            dataManager.setBestHitFromObjectId(objectId)
            dataManager.selectBestHitObject()
            updateSelectionStateBuffer()
            dataManager.updateVisibleStates()
            updateVisibleStateBuffer()

            if let hitItem = dataManager.bestHitObjectIterator() as? AzulObjectIterator {
                animateSelectionPulse()
                let attrsVC = AttributeTableViewController()
                attrsVC.dataManager = dataManager
                let ident = dataManager.identifier(ofItem: hitItem) ?? ""
                attrsVC.title = ident.isEmpty ? (dataManager.type(ofItem: hitItem) ?? "") : ident
                attrsVC.selectedItem = hitItem
                attrsVC.tableView.reloadData()
                let nav = UINavigationController(rootViewController: attrsVC)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    nav.modalPresentationStyle = .popover
                    if let popover = nav.popoverPresentationController {
                        popover.sourceView = objectsButton ?? openButton ?? view
                        popover.permittedArrowDirections = .down
                    }
                } else {
                    nav.modalPresentationStyle = .pageSheet
                    if let sheet = nav.sheetPresentationController {
                        sheet.detents = [.medium(), .large()]
                        sheet.prefersGrabberVisible = true
                    }
                }
                present(nav, animated: true)
            }
        } else {
            dataManager.clearSelection()
            updateSelectionStateBuffer()
        }
    }

    // MARK: Floating buttons
    func setupFloatingButtons() {
        let buttonConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        openButton = makeFloatingButton(systemName: "doc", config: buttonConfig, action: #selector(openFile))
        if let btn = openButton.subviews.compactMap({ $0 as? UIButton }).first {
            openButtonControl = btn
            updateOpenButtonMenu()
        }
        let objectIcon = UIDevice.current.userInterfaceIdiom == .pad ? "sidebar.leading" : "cube"
        objectsButton = makeFloatingButton(systemName: objectIcon, config: buttonConfig, action: #selector(showObjects))
        lodButton = makeFloatingButton(systemName: "plus.minus.capsule", config: buttonConfig, action: #selector(showLodPicker))
        let multicolorConfig = buttonConfig.applying(UIImage.SymbolConfiguration.preferringMulticolor())
        appearanceButton = makeFloatingButton(systemName: "paintpalette.fill", config: multicolorConfig, action: #selector(showAppearancePicker), tintColor: nil)
        homeButton = makeFloatingButton(systemName: "viewfinder.circle", config: buttonConfig, action: #selector(goHome))
        
        let bottomStack = UIStackView(arrangedSubviews: [openButton, objectsButton, lodButton, appearanceButton, homeButton])
        bottomStack.axis = .horizontal
        bottomStack.spacing = 12
        bottomStack.distribution = .equalSpacing
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            bottomStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: Recent files
    private func recentFiles() -> [(path: String, bookmark: Data?)] {
        guard let array = UserDefaults.standard.array(forKey: "azulRecentFiles") as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let path = dict["path"] as? String else { return nil }
            return (path, dict["bookmark"] as? Data)
        }
    }

    private func addRecentFile(_ url: URL) {
        var files = recentFiles()
        files.removeAll { $0.path == url.path }
        let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        files.insert((url.path, bookmark), at: 0)
        if files.count > 5 { files = Array(files.prefix(5)) }
        let array: [[String: Any]] = files.map { entry in
            var dict: [String: Any] = ["path": entry.path]
            if let bookmark = entry.bookmark { dict["bookmark"] = bookmark }
            return dict
        }
        UserDefaults.standard.set(array, forKey: "azulRecentFiles")
    }

    private func updateOpenButtonMenu() {
        var children = [UIMenuElement]()

        children.append(UIAction(title: "New", image: UIImage(systemName: "plus")) { [weak self] _ in
            self?.newDocument()
        })

        children.append(UIAction(title: "Open…", image: UIImage(systemName: "doc")) { [weak self] _ in
            self?.openFile()
        })

        let recents = recentFiles()
        if !recents.isEmpty {
            let recentActions = recents.map { entry in
                let url: URL = {
                    if let bookmark = entry.bookmark {
                        var stale = false
                        if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                            return resolved
                        }
                    }
                    return URL(fileURLWithPath: entry.path)
                }()
                return UIAction(title: url.lastPathComponent) { [weak self] _ in
                    self?.loadFile(url: url)
                }
            }
            children.append(UIMenu(title: "Open Recent", image: UIImage(systemName: "clock"), children: recentActions))
        }

        openButtonControl.menu = UIMenu(title: "", children: children)
    }

    func makeFloatingButton(systemName: String, config: UIImage.SymbolConfiguration, action: Selector, tintColor: UIColor? = .label, menu: UIMenu? = nil) -> UIView {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let size: CGFloat = isPad ? 40 : 32
        let image = UIImage(systemName: systemName, withConfiguration: config)

        let button = UIButton(type: .system)
        if let tintColor {
            button.setImage(image, for: .normal)
            button.tintColor = tintColor
        } else {
            button.setImage(image?.withRenderingMode(.alwaysOriginal), for: .normal)
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.menu = menu
        button.addTarget(self, action: action, for: .touchUpInside)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = size / 2
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        container.widthAnchor.constraint(equalToConstant: size).isActive = true
        container.heightAnchor.constraint(equalToConstant: size).isActive = true

        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.isUserInteractionEnabled = false
        container.addSubview(blurView)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: container.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    // MARK: Status bar
    func setupStatusBar() {
        statusBarView = UIView()
        statusBarView.backgroundColor = UIColor(white: 0, alpha: 0.7)
        statusBarView.layer.cornerRadius = 8
        statusBarView.layer.masksToBounds = true
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        statusBarView.isHidden = true
        view.addSubview(statusBarView)

        progressBar = UIProgressView(progressViewStyle: .default)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        statusBarView.addSubview(progressBar)

        statusLabel = UILabel()
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBarView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusBarView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            statusBarView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            statusBarView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56),
            statusBarView.heightAnchor.constraint(equalToConstant: 44),

            progressBar.leadingAnchor.constraint(equalTo: statusBarView.leadingAnchor, constant: 12),
            progressBar.trailingAnchor.constraint(equalTo: statusBarView.trailingAnchor, constant: -12),
            progressBar.topAnchor.constraint(equalTo: statusBarView.topAnchor, constant: 10),
            progressBar.heightAnchor.constraint(equalToConstant: 4),

            statusLabel.leadingAnchor.constraint(equalTo: statusBarView.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: statusBarView.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),
        ])

        statusBarView.alpha = 0
    }

    func showStatusBar() {
        statusBarView.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.statusBarView.alpha = 1
        }
    }

    func updateStatus(message: String, progress: Float) {
        statusLabel.text = message
        progressBar.setProgress(progress, animated: true)
        if statusBarView.isHidden {
            showStatusBar()
        }
    }

    func hideStatusBar() {
        UIView.animate(withDuration: 0.2, delay: 1.0, options: []) {
            self.statusBarView.alpha = 0
        } completion: { _ in
            self.statusBarView.isHidden = true
        }
    }

    // MARK: Actions
    @objc func openFile() {
        let types: [UTType] = [UTType(filenameExtension: "city.json"), UTType(filenameExtension: "cityjson"), .json, .xml, UTType(filenameExtension: "obj"), UTType(filenameExtension: "off"), UTType(filenameExtension: "poly"), UTType(filenameExtension: "gml"), UTType(filenameExtension: "jsonl"), UTType(filenameExtension: "fcb"), UTType(filenameExtension: "azulview")].compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    @objc func showObjects() {
        if UIDevice.current.userInterfaceIdiom == .pad, let split = splitViewController, !split.isCollapsed {
            if split.viewController(for: .primary)?.view.window != nil {
                split.hide(.primary)
            } else {
                split.show(.primary)
            }
        } else {
            let objectsVC = ObjectListViewController()
            objectsVC.dataManager = dataManager
            objectsVC.delegate = self
            objectsVC.title = "Objects"
            let nav = UINavigationController(rootViewController: objectsVC)
            nav.modalPresentationStyle = .pageSheet
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
            present(nav, animated: true)
        }
    }

    @objc func goHome() {
        fieldOfView = 1.047197551196598
        modelTranslationToCentreOfRotationMatrix = matrix_identity_float4x4
        modelRotationMatrix = matrix_identity_float4x4
        modelShiftBackMatrix = matrix4x4_translation(shift: centre)
        modelMatrix = matrix_multiply(matrix_multiply(modelShiftBackMatrix, modelRotationMatrix), modelTranslationToCentreOfRotationMatrix)
        viewMatrix = matrix4x4_look_at(eye: eye, centre: centre, up: SIMD3<Float>(0.0, 1.0, 0.0))
        projectionMatrix = matrix4x4_perspective_shorter_dim(fieldOfView: fieldOfView, width: Float(metalView.drawableSize.width), height: Float(metalView.drawableSize.height), nearZ: 0.001, farZ: 100.0)
        updateConstants()
    }

    func newDocument() {
        dataManager.clear()
        loadedTextures.removeAll()
        failedTexturePaths.removeAll()
        grantedTextureDirectoryURL = nil
        openedFileURL?.stopAccessingSecurityScopedResource()
        openedFileURL = nil

        triangleBuffers.removeAll()
        edgeBuffers.removeAll()
        boundingBoxBuffer = nil
        selectionStateBuffer = nil
        selectionStateCount = 0
        visibleStateBuffer = nil
        visibleStateCount = 0

        goHome()
        showTextures = false
        currentAppearanceTheme = ""
        currentLodFilter = ""

        metalView?.setNeedsDisplay()

        emptyStateView?.isHidden = false
        emptyStateView?.alpha = 1
    }

    // MARK: LoD filter
    @objc func showLodPicker() {
        let lods = dataManager.availableLods() ?? []
        guard !lods.isEmpty else {
            updateStatus(message: "No LoD data available", progress: 0)
            hideStatusBar()
            return
        }

        let picker = LodPickerViewController()
        picker.availableLods = lods.sorted { Double($0) ?? 0 < Double($1) ?? 0 }
        picker.currentLod = currentLodFilter
        picker.delegate = self
        picker.title = "Level of Detail"

        let nav = UINavigationController(rootViewController: picker)
        if UIDevice.current.userInterfaceIdiom == .pad {
            nav.modalPresentationStyle = .popover
            if let popover = nav.popoverPresentationController {
                popover.sourceView = lodButton
                popover.permittedArrowDirections = .down
            }
        } else {
            nav.modalPresentationStyle = .pageSheet
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }

    private func applyLodFilter(_ lod: String) {
        currentLodFilter = lod
        lod.withCString { pointer in
            dataManager.setLodFilter(pointer)
        }
        dataManager.regenerateTriangleBuffers(withMaximumSize: 16 * 1024 * 1024)
        reloadTriangleBuffers()
        if showTextures {
            primeTexturesForCurrentBuffers()
        }
        dataManager.updateVisibleStates()
        updateVisibleStateBuffer()
        dataManager.updateSelectionStates()
        updateSelectionStateBuffer()
        dataManager.regenerateEdgeBuffers(withMaximumSize: 16 * 1024 * 1024)
        reloadEdgeBuffers()
        metalView?.setNeedsDisplay()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

// MARK: LodPickerDelegate
extension MainViewController: LodPickerDelegate {
    func lodPickerDidSelect(_ lod: String) {
        applyLodFilter(lod)
    }
}

// MARK: ObjectListViewControllerDelegate
extension MainViewController: ObjectListViewControllerDelegate {
    func objectListDidSelectItem(_ item: AzulObjectIterator) {
        dataManager.selectItem(item)
        animateSelectionPulse()
        updateSelectionStateBuffer()
        dataManager.updateVisibleStates()
        updateVisibleStateBuffer()

        let attrsVC = AttributeTableViewController()
        attrsVC.dataManager = dataManager
        let ident = dataManager.identifier(ofItem: item) ?? ""
        attrsVC.title = ident.isEmpty ? (dataManager.type(ofItem: item) ?? "") : ident
        attrsVC.selectedItem = item
        attrsVC.tableView.reloadData()

        if UIDevice.current.userInterfaceIdiom == .pad,
           let split = splitViewController,
           let detailNav = split.viewController(for: .secondary) as? UINavigationController {
            detailNav.pushViewController(attrsVC, animated: true)
        } else if let nav = presentedViewController as? UINavigationController {
            nav.pushViewController(attrsVC, animated: true)
        }
    }

    func objectListDidRequestCenter(_ item: AzulObjectIterator) {
        dataManager.selectItem(item)
        animateSelectionPulse()
        updateSelectionStateBuffer()
        dataManager.updateVisibleStates()
        updateVisibleStateBuffer()
        metalView?.setNeedsDisplay()

        guard let centroid = dataManager.centroid(ofItem: item),
              let mids = dataManager.midCoordinates(),
              let mins = dataManager.minCoordinates(),
              let maxs = dataManager.maxCoordinates() else { return }
        let midF = [mids[0], mids[1], mids[2]].map(Float.init)
        let range = Float(dataManager.maxRange())
        guard range > 0 else { return }

        let normCentroid = SIMD4<Float>(
            (Float(centroid[0]) - midF[0]) / range,
            (Float(centroid[1]) - midF[1]) / range,
            (Float(centroid[2]) - midF[2]) / range,
            1.0)

        let objectToCamera = matrix_multiply(viewMatrix, modelMatrix)
        let centroidInCamera = matrix_multiply(objectToCamera, normCentroid)

        let shiftInCamera = SIMD3<Float>(-centroidInCamera.x, -centroidInCamera.y, 0.0)
        let cameraToObject = matrix_upper_left_3x3(matrix: objectToCamera).inverse
        let shiftInObject = matrix_multiply(cameraToObject, shiftInCamera)

        modelTranslationToCentreOfRotationMatrix = matrix_multiply(
            modelTranslationToCentreOfRotationMatrix,
            matrix4x4_translation(shift: shiftInObject))
        modelMatrix = matrix_multiply(
            matrix_multiply(modelShiftBackMatrix, modelRotationMatrix),
            modelTranslationToCentreOfRotationMatrix)

        let correctedObjectToCamera = matrix_multiply(viewMatrix, modelMatrix)
        let correctedCameraToObject = matrix_upper_left_3x3(matrix: correctedObjectToCamera).inverse
        let depthOffset: Float = 1.0 + depthAtCentre()
        let depthOffsetInCamera = SIMD3<Float>(0.0, 0.0, -depthOffset)
        let depthOffsetInObject = matrix_multiply(correctedCameraToObject, depthOffsetInCamera)

        modelTranslationToCentreOfRotationMatrix = matrix_multiply(
            modelTranslationToCentreOfRotationMatrix,
            matrix4x4_translation(shift: depthOffsetInObject))
        modelMatrix = matrix_multiply(
            matrix_multiply(modelShiftBackMatrix, modelRotationMatrix),
            modelTranslationToCentreOfRotationMatrix)

        updateConstants()
    }
}

// MARK: AppearancePickerDelegate
extension MainViewController: AppearancePickerDelegate {
    func appearancePickerDidSelect(type: String, theme: String) {
        if type == "semantics" {
            showTextures = false
            currentAppearanceTheme = ""
        } else {
            showTextures = true
            currentAppearanceTheme = theme
        }
        refreshAppearanceRendering()
    }
}

// MARK: UIGestureRecognizerDelegate
extension MainViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        let isPinch = gestureRecognizer is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer
        let isRotation = gestureRecognizer is UIRotationGestureRecognizer || other is UIRotationGestureRecognizer
        return isPinch && isRotation
    }
}

// MARK: UIDocumentPickerDelegate
extension MainViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                grantedTextureDirectoryURL = url
                failedTexturePaths.removeAll()
                primeTexturesForCurrentBuffers()
                metalView?.setNeedsDisplay()
            } else {
                loadFile(url: url)
            }
        }
    }
}

// MARK: UIContextMenuInteractionDelegate
extension MainViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let objectId = pickObject(at: location)
        guard objectId >= 0 else { return nil }

        dataManager.setBestHitFromObjectId(objectId)
        dataManager.selectBestHitObject()
        animateSelectionPulse()
        updateSelectionStateBuffer()
        dataManager.updateVisibleStates()
        updateVisibleStateBuffer()

        guard let hitItem = dataManager.bestHitObjectIterator() as? AzulObjectIterator else { return nil }
        let ident = dataManager.identifier(ofItem: hitItem) ?? ""

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return UIMenu() }
            var actions = [UIAction]()

            actions.append(UIAction(title: "Show Attributes", image: UIImage(systemName: "info.circle")) { _ in
                let attrsVC = AttributeTableViewController()
                attrsVC.dataManager = self.dataManager
                attrsVC.title = ident.isEmpty ? (self.dataManager.type(ofItem: hitItem) ?? "") : ident
                attrsVC.selectedItem = hitItem
                attrsVC.tableView.reloadData()
                let nav = UINavigationController(rootViewController: attrsVC)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    nav.modalPresentationStyle = .popover
                    if let popover = nav.popoverPresentationController {
                        popover.sourceView = self.objectsButton ?? self.openButton ?? self.view
                        popover.permittedArrowDirections = .down
                    }
                } else {
                    nav.modalPresentationStyle = .pageSheet
                    if let sheet = nav.sheetPresentationController {
                        sheet.detents = [.medium(), .large()]
                        sheet.prefersGrabberVisible = true
                    }
                }
                self.present(nav, animated: true)
            })

            actions.append(UIAction(title: "Select and centre", image: UIImage(systemName: "location")) { _ in
                self.objectListDidRequestCenter(hitItem)
            })

            return UIMenu(title: ident, children: actions)
        }
    }
}
