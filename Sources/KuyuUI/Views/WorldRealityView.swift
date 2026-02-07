import RealityKit
import SwiftUI
import KuyuCore

public struct WorldRealityView: View {
    let roll: Double
    let pitch: Double
    let yaw: Double
    let position: Axis3
    let label: String
    let renderInfo: RenderAssetInfo?

    @State private var rootEntity: Entity?
    @State private var proxyEntity: Entity?
    @State private var loadedEntity: Entity?
    @State private var loadedURL: URL?
    @State private var loadFailed = false
    @State private var cameraEntity: PerspectiveCamera?
    @State private var cameraYaw: Float = 0.6
    @State private var cameraPitch: Float = 1.1
    @State private var cameraDistance: Float = 3.2
    @State private var cameraTarget = SIMD3<Float>(0, 0.15, 0)
    @State private var lastDrag: CGSize?
    @State private var zoomStart: Float?
    private let renderSystem = RenderSystem()
    private static let defaultCameraYaw: Float = 0.6
    private static let defaultCameraPitch: Float = 1.1
    private static let defaultCameraDistance: Float = 3.2
    private static let defaultCameraTarget = SIMD3<Float>(0, 0.15, 0)
    private static let baseHeight: Float = 0.18

    public var body: some View {
        RealityView { content in
            let world = makeWorld()
            content.add(world)

            let root = Entity()
            root.name = "RobotRoot"
            root.addChild(makeBody())
            let proxy = makeProxy()
            root.addChild(proxy)
            root.position = realityPosition()

            content.add(root)
            rootEntity = root
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
            updateCamera()
        }
        .onChange(of: renderInfo?.url) { _, _ in
            guard let info = renderInfo, !loadFailed else { return }
            loadRenderAssetIfNeeded(info: info)
        }
        .onAppear {
            if let info = renderInfo, !loadFailed { loadRenderAssetIfNeeded(info: info) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0.0)
                    .onChanged { value in
                        if let lastDrag {
                            let dx = Float(value.translation.width - lastDrag.width)
                            let dy = Float(value.translation.height - lastDrag.height)
                            cameraYaw -= dx * 0.01
                            cameraPitch = max(0.15, min(1.2, cameraPitch - dy * 0.01))
                        }
                        lastDrag = value.translation
                    }
                    .onEnded { _ in
                        lastDrag = nil
                    }
                )
                .simultaneousGesture(MagnificationGesture()
                    .onChanged { value in
                        if zoomStart == nil {
                            zoomStart = cameraDistance
                        }
                        if let zoomStart {
                            let target = zoomStart / Float(value)
                            cameraDistance = max(0.6, min(4.0, target))
                        }
                    }
                    .onEnded { _ in
                        zoomStart = nil
                    }
                )
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

        let axes = makeAxes(length: 1.2)
        axes.position = [0, 0.001, 0]
        world.addChild(axes)

        let obstacles = makeObstacles()
        world.addChild(obstacles)

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

    private func makeObstacles() -> Entity {
        let root = Entity()
        let material = SimpleMaterial(color: .init(white: 0.25, alpha: 1.0), isMetallic: false)

        let boxMesh = MeshResource.generateBox(size: [0.3, 0.2, 0.3])
        let box1 = ModelEntity(mesh: boxMesh, materials: [material])
        box1.position = [1.0, 0.1, -0.8]
        root.addChild(box1)

        let box2 = ModelEntity(mesh: boxMesh, materials: [material])
        box2.position = [-0.9, 0.1, 0.9]
        root.addChild(box2)

        let box3 = ModelEntity(mesh: boxMesh, materials: [material])
        box3.position = [0.8, 0.1, 0.9]
        root.addChild(box3)

        return root
    }

    private func loadRenderAssetIfNeeded(info: RenderAssetInfo) {
        guard loadedURL != info.url else { return }
        loadedURL = info.url
        Task {
            do {
                let entity = try await renderSystem.loadEntity(info: info)
                await MainActor.run {
                    loadedEntity = entity
                    if let proxyEntity {
                        rootEntity?.removeChild(proxyEntity)
                    }
                    rootEntity?.addChild(entity)
                }
            } catch {
                await MainActor.run {
                    loadFailed = true
                }
            }
        }
    }

    private var statusLine: String {
        guard let renderInfo else { return "Proxy (no render asset)" }
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
