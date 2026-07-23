import AppKit
import RealityKit
import SwiftUI
import KuyuCore

public struct WorldRealityView: View {
    public enum RenderingMode: Sendable {
        case live
        case staticFallback
    }

    let roll: Double
    let pitch: Double
    let yaw: Double
    let position: Axis3
    let label: String
    let renderInfo: RenderAssetInfo?
    let jointAngles: [Double]
    let jointValues: [String: Double]
    /// Live per-actuator command/thrust values for the forces/actuator debug overlay.
    let actuatorChannels: [ActuatorChannelSnapshot]
    let showsSensorReadouts: Bool
    let renderingMode: RenderingMode

    public init(
        roll: Double,
        pitch: Double,
        yaw: Double,
        position: Axis3,
        label: String,
        renderInfo: RenderAssetInfo?,
        jointAngles: [Double] = [],
        jointValues: [String: Double] = [:],
        actuatorChannels: [ActuatorChannelSnapshot] = [],
        showsSensorReadouts: Bool = true,
        renderingMode: RenderingMode = .live
    ) {
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
        self.position = position
        self.label = label
        self.renderInfo = renderInfo
        self.jointAngles = jointAngles
        self.jointValues = jointValues
        self.actuatorChannels = actuatorChannels
        self.showsSensorReadouts = showsSensorReadouts
        self.renderingMode = renderingMode
    }

    @State private var rootEntity: Entity?
    @State private var proxyBodyEntity: Entity?
    @State private var proxyEntity: Entity?
    @State private var loadedEntity: Entity?
    @State private var loadedJointBindings: [RenderJointBinding] = []
    @State private var loadedURL: URL?
    @State private var loadFailed = false
    @State private var cameraEntity: PerspectiveCamera?
    @State private var cameraYaw: Float = 0.6
    @State private var cameraPitch: Float = 1.1
    @State private var cameraDistance: Float = 3.2
    @State private var cameraTarget = SIMD3<Float>(0, 0.15, 0)
    private static let defaultCameraYaw: Float = 0.6
    private static let defaultCameraPitch: Float = 1.1
    private static let defaultCameraDistance: Float = 3.2
    private static let defaultCameraTarget = SIMD3<Float>(0, 0.15, 0)
    private static let baseHeight: Float = 0.18

    public var body: some View {
        renderContent
            .overlay(alignment: .bottomLeading) {
                if showsSensorReadouts {
                    actuatorOverlay
                }
            }
    }

    @ViewBuilder
    private var renderContent: some View {
        #if KUYU_USE_REALITYVIEW
        switch renderingMode {
        case .live:
            realityBody
        case .staticFallback:
            fallbackBody
        }
        #else
        fallbackBody
        #endif
    }

    /// Forces/actuator debug overlay: per-actuator command magnitude as labeled bars.
    /// For a quadrotor each channel is a rotor thrust (a body force), so this doubles
    /// as the forces overlay required by the visual-inspection spec.
    @ViewBuilder
    private var actuatorOverlay: some View {
        if !actuatorChannels.isEmpty {
            let maxMagnitude = max(actuatorChannels.map { abs($0.value) }.max() ?? 1.0, 1e-6)
            VStack(alignment: .leading, spacing: 2) {
                Text(jointAngles.isEmpty ? "Actuator / forces" : "Joint state")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(actuatorChannels, id: \.id) { channel in
                    HStack(spacing: 6) {
                        Text(displayLabel(for: channel.id))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: 24, alignment: .leading)
                        GeometryReader { proxy in
                            let fraction = CGFloat(abs(channel.value) / maxMagnitude)
                            let width = proxy.size.width
                            let barWidth = max(2, (width * 0.5) * min(fraction, 1))
                            ZStack {
                                Capsule()
                                    .fill(.white.opacity(0.12))
                                    .frame(height: 2)
                                Rectangle()
                                    .fill(.white.opacity(0.28))
                                    .frame(width: 1, height: 8)
                                Capsule()
                                    .fill((channel.value >= 0 ? Color.green : Color.cyan).opacity(0.65))
                                    .frame(width: barWidth, height: 6)
                                    .offset(x: channel.value >= 0 ? barWidth * 0.5 : -barWidth * 0.5)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(width: 88, height: 8)
                        Text(String(format: "%.2f", channel.value))
                            .font(.system(.caption2, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .accessibilityLabel("\(channel.id) \(channel.value)")
                }
            }
            .padding(8)
            .background(.black.opacity(0.32))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(8)
        }
    }

    #if KUYU_USE_REALITYVIEW
    private var realityBody: some View {
        RealityView { content in
            let world = makeWorld()
            content.add(world)

            let root = Entity()
            root.name = "RobotRoot"
            let proxyBody = makeBody()
            root.addChild(proxyBody)
            let proxy = makeProxy()
            root.addChild(proxy)
            root.position = realityPosition()

            content.add(root)
            rootEntity = root
            proxyBodyEntity = proxyBody
            proxyEntity = proxy

            let camera = PerspectiveCamera()
            content.add(camera)
            cameraEntity = camera
            updateCamera()

            let light = DirectionalLight()
            light.light.intensity = 1200
            light.look(at: [0, 0, 0], from: [1.0, 1.8, 1.0], relativeTo: nil)
            content.add(light)

            let fill = PointLight()
            fill.light.intensity = 500
            fill.position = [-1.0, 0.6, -1.0]
            content.add(fill)
        } update: { _ in
            guard let rootEntity else { return }
            rootEntity.transform.rotation = rotationQuaternion()
            rootEntity.position = realityPosition()
            updateLoadedJoints()
            updateCamera()
        }
        .onChange(of: renderInfo?.url) { _, _ in
            guard let info = renderInfo else { return }
            loadRenderAssetIfNeeded(info: info)
        }
        .onAppear {
            if let info = renderInfo { loadRenderAssetIfNeeded(info: info) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            CameraInputOverlay(
                onDrag: { delta in
                    orbitCamera(delta: delta)
                },
                onMagnify: { magnification in
                    magnifyCamera(by: magnification)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusLine)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            Button("Reset") {
                resetCamera()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
        }
        .onChange(of: cameraYaw) { _, _ in updateCamera() }
        .onChange(of: cameraPitch) { _, _ in updateCamera() }
        .onChange(of: cameraDistance) { _, _ in updateCamera() }
    }
    #endif

    private var fallbackBody: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            fallbackGrid

            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.22))
                .frame(width: 88, height: 32)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.primary.opacity(0.28))
                        .frame(width: 150, height: 8)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.primary.opacity(0.28))
                        .frame(width: 8, height: 150)
                }
                .rotationEffect(.radians(yaw))
                .rotation3DEffect(.radians(pitch), axis: (x: 1, y: 0, z: 0))
                .rotation3DEffect(.radians(roll), axis: (x: 0, y: 1, z: 0))
                .shadow(radius: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusLine)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var fallbackGrid: some View {
        Canvas { context, size in
            let spacing: CGFloat = 28
            var path = Path()

            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
        }
    }

    private func rotationQuaternion() -> simd_quatf {
        let rollQuat = simd_quatf(angle: Float(roll), axis: SIMD3<Float>(1, 0, 0))
        let pitchQuat = simd_quatf(angle: Float(pitch), axis: SIMD3<Float>(0, 1, 0))
        let yawQuat = simd_quatf(angle: Float(yaw), axis: SIMD3<Float>(0, 0, 1))
        return yawQuat * pitchQuat * rollQuat
    }

    private func updateCamera() {
        guard let cameraEntity else { return }
        let x = cameraTarget.x + cameraDistance * cos(cameraPitch) * sin(cameraYaw)
        let y = cameraTarget.y + cameraDistance * sin(cameraPitch)
        let z = cameraTarget.z + cameraDistance * cos(cameraPitch) * cos(cameraYaw)
        cameraEntity.position = [x, y, z]
        cameraEntity.look(at: cameraTarget, from: cameraEntity.position, relativeTo: nil)
    }

    private func realityPosition() -> SIMD3<Float> {
        let x = Float(position.x)
        let y = Float(position.z) + Self.baseHeight
        let z = Float(position.y)
        return [x, y, z]
    }

    private func resetCamera() {
        cameraYaw = Self.defaultCameraYaw
        cameraPitch = Self.defaultCameraPitch
        cameraDistance = Self.defaultCameraDistance
        cameraTarget = Self.defaultCameraTarget
        updateCamera()
    }

    private func orbitCamera(delta: CGSize) {
        cameraYaw -= Float(delta.width) * 0.01
        cameraPitch = max(0.15, min(1.2, cameraPitch - Float(delta.height) * 0.01))
        updateCamera()
    }

    private func magnifyCamera(by magnification: CGFloat) {
        let factor = max(0.2, min(2.0, 1.0 - Float(magnification)))
        cameraDistance = clampedCameraDistance(cameraDistance * factor)
        updateCamera()
    }

    private func clampedCameraDistance(_ value: Float) -> Float {
        max(0.25, min(8.0, value))
    }

    private func displayLabel(for id: String) -> String {
        guard id.hasPrefix("joint_") else { return id }
        let suffix = id.dropFirst("joint_".count)
        return "J\(suffix)"
    }

    private func makeBody() -> Entity {
        let mesh = MeshResource.generateBox(size: [0.28, 0.08, 0.28])
        let material = SimpleMaterial(color: .gray, isMetallic: true)
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.position = [0, 0, 0]
        return model
    }

    private func makeProxy() -> Entity {
        let root = Entity()
        root.addChild(makeArms())
        root.addChild(makeRotor(at: [0.4, 0.02, 0.0]))
        root.addChild(makeRotor(at: [-0.4, 0.02, 0.0]))
        root.addChild(makeRotor(at: [0.0, 0.02, 0.4]))
        root.addChild(makeRotor(at: [0.0, 0.02, -0.4]))
        return root
    }

    private func makeArms() -> Entity {
        let armThickness: Float = 0.05
        let armLength: Float = 0.8
        let material = SimpleMaterial(color: .darkGray, isMetallic: true)
        let root = Entity()

        let armXMesh = MeshResource.generateBox(size: [armLength, armThickness, armThickness])
        let armX = ModelEntity(mesh: armXMesh, materials: [material])
        armX.position = [0, 0, 0]
        root.addChild(armX)

        let armZMesh = MeshResource.generateBox(size: [armThickness, armThickness, armLength])
        let armZ = ModelEntity(mesh: armZMesh, materials: [material])
        armZ.position = [0, 0, 0]
        root.addChild(armZ)

        return root
    }

    private func makeRotor(at position: SIMD3<Float>) -> Entity {
        let mesh = MeshResource.generateCylinder(height: 0.02, radius: 0.1)
        let material = SimpleMaterial(color: .black, isMetallic: false)
        let rotor = ModelEntity(mesh: mesh, materials: [material])
        rotor.position = position
        return rotor
    }

    private func makeWorld() -> Entity {
        let world = Entity()
        world.name = "WorldRoot"

        let groundSize: Float = 6.0
        let groundMesh = MeshResource.generatePlane(width: groundSize, depth: groundSize)
        let groundMaterial = SimpleMaterial(color: .init(white: 0.14, alpha: 1.0), isMetallic: false)
        let ground = ModelEntity(mesh: groundMesh, materials: [groundMaterial])
        ground.position = [0, 0, 0]
        world.addChild(ground)

        let grid = makeGrid(size: groundSize, spacing: 0.5)
        world.addChild(grid)

        let axes = makeAxes(length: 0.45)
        axes.position = [0, 0.001, 0]
        world.addChild(axes)

        return world
    }

    private func makeGrid(size: Float, spacing: Float) -> Entity {
        let grid = Entity()
        let half = size / 2
        let lineThickness: Float = 0.01
        let lineHeight: Float = 0.002
        let lineMaterial = SimpleMaterial(color: .init(white: 0.22, alpha: 1.0), isMetallic: false)

        var position: Float = -half
        while position <= half + 0.0001 {
            let lineXMesh = MeshResource.generateBox(size: [size, lineHeight, lineThickness])
            let lineX = ModelEntity(mesh: lineXMesh, materials: [lineMaterial])
            lineX.position = [0, 0.001, position]
            grid.addChild(lineX)

            let lineZMesh = MeshResource.generateBox(size: [lineThickness, lineHeight, size])
            let lineZ = ModelEntity(mesh: lineZMesh, materials: [lineMaterial])
            lineZ.position = [position, 0.001, 0]
            grid.addChild(lineZ)

            position += spacing
        }

        return grid
    }

    private func makeAxes(length: Float) -> Entity {
        let root = Entity()
        let thickness: Float = 0.02
        let height: Float = 0.01

        let xMaterial = SimpleMaterial(color: .red, isMetallic: false)
        let xMesh = MeshResource.generateBox(size: [length, height, thickness])
        let xAxis = ModelEntity(mesh: xMesh, materials: [xMaterial])
        xAxis.position = [length / 2, 0, 0]
        root.addChild(xAxis)

        let zMaterial = SimpleMaterial(color: .blue, isMetallic: false)
        let zMesh = MeshResource.generateBox(size: [thickness, height, length])
        let zAxis = ModelEntity(mesh: zMesh, materials: [zMaterial])
        zAxis.position = [0, 0, length / 2]
        root.addChild(zAxis)

        let yMaterial = SimpleMaterial(color: .green, isMetallic: false)
        let yMesh = MeshResource.generateBox(size: [thickness, length, thickness])
        let yAxis = ModelEntity(mesh: yMesh, materials: [yMaterial])
        yAxis.position = [0, length / 2, 0]
        root.addChild(yAxis)

        return root
    }

    private func loadRenderAssetIfNeeded(info: RenderAssetInfo) {
        guard loadedURL != info.url else { return }
        loadedURL = info.url
        loadFailed = false
        Task {
            do {
                // Served from the main-actor entity cache: a cache hit clones
                // the loaded template instead of re-parsing the asset, so
                // workspace switches do not repeat disk loads.
                let rendered = try await RobotEntityCache.shared.renderedEntity(for: info)
                guard loadedURL == info.url else { return }
                loadedEntity = rendered.entity
                loadedJointBindings = rendered.jointBindings
                if let proxyBodyEntity {
                    rootEntity?.removeChild(proxyBodyEntity)
                    self.proxyBodyEntity = nil
                }
                if let proxyEntity {
                    rootEntity?.removeChild(proxyEntity)
                    self.proxyEntity = nil
                }
                rootEntity?.addChild(rendered.entity)
                updateLoadedJoints()
            } catch {
                guard loadedURL == info.url else { return }
                loadFailed = true
            }
        }
    }

    private func updateLoadedJoints() {
        guard !loadedJointBindings.isEmpty else { return }
        for binding in loadedJointBindings {
            let value = jointValue(for: binding)
            switch binding.motion {
            case .fixed:
                binding.entity.position = binding.basePosition
                binding.entity.transform.rotation = binding.baseRotation
            case .revolute:
                binding.entity.position = binding.basePosition
                binding.entity.transform.rotation = binding.baseRotation
                    * simd_quatf(angle: Float(value), axis: binding.axis)
            case .prismatic:
                binding.entity.position = binding.basePosition + (binding.axis * Float(value))
                binding.entity.transform.rotation = binding.baseRotation
            }
        }
    }

    private func jointValue(for binding: RenderJointBinding) -> Double {
        if let value = jointValues[binding.name] {
            return value
        }
        if jointAngles.indices.contains(binding.order) {
            return jointAngles[binding.order]
        }
        return 0.0
    }

    private var statusLine: String {
        guard let renderInfo else { return "Proxy (no render asset)" }
        if loadFailed {
            return "Render failed: proxy fallback"
        }
        if loadedEntity != nil {
            return "Render: \(renderInfo.format.rawValue.uppercased())"
        }
        return "Proxy (format=\(renderInfo.format.rawValue))"
    }
}

#Preview {
    WorldRealityView(
        roll: 0.1,
        pitch: -0.2,
        yaw: 0.3,
        position: Axis3(x: 0, y: 0, z: 0),
        label: "Robot proxy",
        renderInfo: nil
    )
    .frame(width: 320, height: 240)
    .padding()
}

private struct CameraInputOverlay: NSViewRepresentable {
    let onDrag: (CGSize) -> Void
    let onMagnify: (CGFloat) -> Void

    func makeNSView(context: Context) -> CameraInputNSView {
        let view = CameraInputNSView()
        view.onDrag = onDrag
        view.onMagnify = onMagnify
        return view
    }

    func updateNSView(_ nsView: CameraInputNSView, context: Context) {
        nsView.onDrag = onDrag
        nsView.onMagnify = onMagnify
    }
}

private final class CameraInputNSView: NSView {
    var onDrag: (CGSize) -> Void = { _ in }
    var onMagnify: (CGFloat) -> Void = { _ in }

    private var lastDragLocation: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        installMagnificationRecognizer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        installMagnificationRecognizer()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        if let lastDragLocation {
            onDrag(CGSize(
                width: current.x - lastDragLocation.x,
                height: current.y - lastDragLocation.y
            ))
        }
        lastDragLocation = current
    }

    override func mouseUp(with event: NSEvent) {
        _ = event
        lastDragLocation = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func magnify(with event: NSEvent) {
        onMagnify(event.magnification)
    }

    private func installMagnificationRecognizer() {
        let recognizer = NSMagnificationGestureRecognizer(
            target: self,
            action: #selector(handleMagnification(_:))
        )
        addGestureRecognizer(recognizer)
    }

    @objc private func handleMagnification(_ recognizer: NSMagnificationGestureRecognizer) {
        onMagnify(recognizer.magnification)
        recognizer.magnification = 0
    }
}
