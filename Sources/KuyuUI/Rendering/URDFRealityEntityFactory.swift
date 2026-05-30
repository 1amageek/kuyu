import AppKit
import Foundation
import KuyuCore
import KuyuPhysics
import RealityKit

struct RenderedRobotEntity {
    let entity: Entity
    let jointBindings: [RenderJointBinding]
}

struct RenderJointBinding {
    enum Motion {
        case fixed
        case prismatic
        case revolute
    }

    let name: String
    let order: Int
    let entity: Entity
    let motion: Motion
    let basePosition: SIMD3<Float>
    let baseRotation: simd_quatf
    let axis: SIMD3<Float>
}

@MainActor
struct URDFRealityEntityFactory {
    func makeEntity(
        model: URDFKinematicModel,
        sourceURL: URL,
        scale: KuyuVector3?
    ) throws -> RenderedRobotEntity {
        let root = Entity()
        root.name = "URDFRoot"
        let descriptorScale = scale.map(axis(from:)) ?? [1, 1, 1]

        var linkEntities: [String: Entity] = [:]
        for link in model.links {
            let entity = Entity()
            entity.name = link.name
            for visual in link.visuals {
                entity.addChild(try makeVisualEntity(
                    visual,
                    sourceURL: sourceURL,
                    descriptorScale: descriptorScale
                ))
            }
            linkEntities[link.name] = entity
        }

        var bindings: [RenderJointBinding] = []
        for (index, joint) in model.joints.enumerated() {
            guard let parent = linkEntities[joint.parent],
                  let child = linkEntities[joint.child] else {
                continue
            }

            let jointEntity = Entity()
            jointEntity.name = joint.name
            let basePosition = mapPosition(joint.origin.xyz, scale: descriptorScale)
            let baseRotation = rotation(from: joint.origin.rpy)
            jointEntity.position = basePosition
            jointEntity.transform.rotation = baseRotation
            parent.addChild(jointEntity)
            jointEntity.addChild(child)

            bindings.append(RenderJointBinding(
                name: joint.name,
                order: index,
                entity: jointEntity,
                motion: motion(from: joint.type),
                basePosition: basePosition,
                baseRotation: baseRotation,
                axis: normalized(mapDirection(joint.axis))
            ))
        }

        for rootLinkName in model.rootLinkNames {
            if let rootLink = linkEntities[rootLinkName], rootLink.parent == nil {
                root.addChild(rootLink)
            }
        }

        return RenderedRobotEntity(entity: root, jointBindings: bindings)
    }

    private func makeVisualEntity(
        _ visual: URDFVisual,
        sourceURL: URL,
        descriptorScale: SIMD3<Float>
    ) throws -> Entity {
        let root = Entity()
        root.position = mapPosition(visual.origin.xyz, scale: descriptorScale)
        root.transform.rotation = rotation(from: visual.origin.rpy)
        root.addChild(try makeGeometryEntity(
            visual.geometry,
            sourceURL: sourceURL,
            descriptorScale: descriptorScale
        ))
        return root
    }

    private func makeGeometryEntity(
        _ geometry: URDFGeometry,
        sourceURL: URL,
        descriptorScale: SIMD3<Float>
    ) throws -> Entity {
        switch geometry {
        case .box(let size):
            let mappedSize = mapSize(size, scale: descriptorScale)
            return ModelEntity(
                mesh: MeshResource.generateBox(size: mappedSize),
                materials: [SimpleMaterial(color: .gray, isMetallic: true)]
            )
        case .cylinder(let radius, let length):
            return ModelEntity(
                mesh: MeshResource.generateCylinder(
                    height: Float(length) * descriptorScale.y,
                    radius: Float(radius) * max(descriptorScale.x, descriptorScale.z)
                ),
                materials: [SimpleMaterial(color: .darkGray, isMetallic: true)]
            )
        case .sphere(let radius):
            return ModelEntity(
                mesh: MeshResource.generateSphere(
                    radius: Float(radius) * max(descriptorScale.x, max(descriptorScale.y, descriptorScale.z))
                ),
                materials: [SimpleMaterial(color: .lightGray, isMetallic: true)]
            )
        case .mesh(let filename, let meshScale):
            let meshURL = resolveMeshURL(filename: filename, sourceURL: sourceURL)
            let combinedScale = descriptorScale * (meshScale.map(axis(from:)) ?? [1, 1, 1])
            if meshURL.pathExtension.lowercased() == "stl" {
                return try STLMeshEntityFactory().makeEntity(url: meshURL, scale: vector(from: combinedScale))
            }

            let entity = try ModelEntity.loadModel(contentsOf: meshURL)
            entity.scale = combinedScale
            return entity
        }
    }

    private func motion(from type: URDFJointType) -> RenderJointBinding.Motion {
        switch type {
        case .continuous, .revolute:
            return .revolute
        case .prismatic:
            return .prismatic
        case .fixed, .floating, .planar:
            return .fixed
        }
    }

    private func resolveMeshURL(filename: String, sourceURL: URL) -> URL {
        if filename.hasPrefix("/") {
            return URL(fileURLWithPath: filename)
        }

        if filename.hasPrefix("package://") {
            let stripped = String(filename.dropFirst("package://".count))
            let parts = stripped.split(separator: "/", maxSplits: 1).map(String.init)
            let relative = parts.count == 2 ? parts[1] : stripped
            let packageRoot = sourceURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            return packageRoot.appendingPathComponent(relative)
        }

        return sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(filename)
    }
}

@MainActor
struct STLMeshEntityFactory {
    enum LoaderError: Error, Equatable {
        case invalidData
        case invalidTriangleCount
        case unsupportedEncoding
    }

    func makeEntity(url: URL, scale: KuyuVector3?) throws -> Entity {
        let triangles = try parseTriangles(url: url, scale: scale.map(axis(from:)) ?? [1, 1, 1])
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(triangles.count * 3)
        normals.reserveCapacity(triangles.count * 3)
        indices.reserveCapacity(triangles.count * 3)

        for triangle in triangles {
            for vertex in triangle.vertices {
                positions.append(vertex)
                normals.append(triangle.normal)
                indices.append(UInt32(indices.count))
            }
        }

        var descriptor = MeshDescriptor(name: url.deletingPathExtension().lastPathComponent)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        return ModelEntity(
            mesh: mesh,
            materials: [SimpleMaterial(color: .gray, isMetallic: true)]
        )
    }

    private struct Triangle {
        let normal: SIMD3<Float>
        let vertices: [SIMD3<Float>]
    }

    private func parseTriangles(url: URL, scale: SIMD3<Float>) throws -> [Triangle] {
        let data = try Data(contentsOf: url)
        if isBinarySTL(data) {
            return try parseBinarySTL(data, scale: scale)
        }
        return try parseASCIISTL(data, scale: scale)
    }

    private func isBinarySTL(_ data: Data) -> Bool {
        guard data.count >= 84 else { return false }
        let count = Int(readUInt32(data, offset: 80))
        return data.count == 84 + (count * 50)
    }

    private func parseBinarySTL(_ data: Data, scale: SIMD3<Float>) throws -> [Triangle] {
        guard data.count >= 84 else {
            throw LoaderError.invalidData
        }
        let count = Int(readUInt32(data, offset: 80))
        guard count >= 0, data.count == 84 + (count * 50) else {
            throw LoaderError.invalidTriangleCount
        }

        var triangles: [Triangle] = []
        triangles.reserveCapacity(count)
        var offset = 84
        for _ in 0..<count {
            let normal = normalized(mapDirection(
                SIMD3<Float>(
                    readFloat(data, offset: offset),
                    readFloat(data, offset: offset + 4),
                    readFloat(data, offset: offset + 8)
                )
            ))
            offset += 12

            var vertices: [SIMD3<Float>] = []
            vertices.reserveCapacity(3)
            for _ in 0..<3 {
                let raw = SIMD3<Float>(
                    readFloat(data, offset: offset),
                    readFloat(data, offset: offset + 4),
                    readFloat(data, offset: offset + 8)
                )
                vertices.append(mapPosition(raw * scale))
                offset += 12
            }
            offset += 2
            triangles.append(Triangle(normal: normal, vertices: vertices))
        }
        return triangles
    }

    private func parseASCIISTL(_ data: Data, scale: SIMD3<Float>) throws -> [Triangle] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw LoaderError.unsupportedEncoding
        }

        var triangles: [Triangle] = []
        var currentNormal = SIMD3<Float>(0, 1, 0)
        var vertices: [SIMD3<Float>] = []

        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if parts.count == 5, parts[0] == "facet", parts[1] == "normal",
               let x = Float(parts[2]), let y = Float(parts[3]), let z = Float(parts[4]) {
                currentNormal = normalized(mapDirection([x, y, z]))
            } else if parts.count == 4, parts[0] == "vertex",
                      let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                vertices.append(mapPosition(SIMD3<Float>(x, y, z) * scale))
                if vertices.count == 3 {
                    triangles.append(Triangle(normal: currentNormal, vertices: vertices))
                    vertices.removeAll(keepingCapacity: true)
                }
            }
        }

        guard !triangles.isEmpty else {
            throw LoaderError.invalidData
        }
        return triangles
    }

    private func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        data.withUnsafeBytes { pointer in
            UInt32(littleEndian: pointer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    private func readFloat(_ data: Data, offset: Int) -> Float {
        data.withUnsafeBytes { pointer in
            let bits = UInt32(littleEndian: pointer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            return Float(bitPattern: bits)
        }
    }
}

private func axis(from vector: KuyuVector3) -> SIMD3<Float> {
    SIMD3<Float>(Float(vector.x), Float(vector.y), Float(vector.z))
}

private func axis(from vector: Axis3) -> SIMD3<Float> {
    SIMD3<Float>(Float(vector.x), Float(vector.y), Float(vector.z))
}

private func vector(from axis: SIMD3<Float>) -> KuyuVector3 {
    KuyuVector3(x: Double(axis.x), y: Double(axis.y), z: Double(axis.z))
}

private func mapPosition(_ axis: Axis3, scale: SIMD3<Float>) -> SIMD3<Float> {
    mapPosition(SIMD3<Float>(
        Float(axis.x) * scale.x,
        Float(axis.y) * scale.y,
        Float(axis.z) * scale.z
    ))
}

private func mapSize(_ axis: Axis3, scale: SIMD3<Float>) -> SIMD3<Float> {
    let scaled = SIMD3<Float>(
        Float(axis.x) * scale.x,
        Float(axis.y) * scale.y,
        Float(axis.z) * scale.z
    )
    return [scaled.x, scaled.z, scaled.y]
}

private func mapPosition(_ vector: SIMD3<Float>) -> SIMD3<Float> {
    [vector.x, vector.z, vector.y]
}

private func mapDirection(_ axis: Axis3) -> SIMD3<Float> {
    mapDirection(SIMD3<Float>(Float(axis.x), Float(axis.y), Float(axis.z)))
}

private func mapDirection(_ vector: SIMD3<Float>) -> SIMD3<Float> {
    [vector.x, vector.z, vector.y]
}

private func rotation(from rpy: Axis3) -> simd_quatf {
    let roll = simd_quatf(angle: Float(rpy.x), axis: mapDirection(SIMD3<Float>(1, 0, 0)))
    let pitch = simd_quatf(angle: Float(rpy.y), axis: mapDirection(SIMD3<Float>(0, 1, 0)))
    let yaw = simd_quatf(angle: Float(rpy.z), axis: mapDirection(SIMD3<Float>(0, 0, 1)))
    return yaw * pitch * roll
}

private func normalized(_ vector: SIMD3<Float>) -> SIMD3<Float> {
    let length = simd_length(vector)
    guard length > 0 else { return [1, 0, 0] }
    return vector / length
}
