import Foundation
import RealityKit
import KuyuCore

/// Main-actor cache of loaded robot render entities.
///
/// Workspace switches destroy and rebuild the SwiftUI view tree, which resets
/// per-view `@State` and would otherwise re-parse robot assets from disk on
/// every switch. This cache keeps one immutable template per asset and hands
/// out recursive clones, rebinding joint entities by name so each clone is
/// independently animatable.
@MainActor
final class RobotEntityCache {
    enum CacheError: Error, Equatable {
        case jointEntityNotFound(String)
    }

    static let shared = RobotEntityCache()

    private struct Key: Hashable {
        let url: URL
        let scale: SIMD3<Double>?

        init(_ info: RenderAssetInfo) {
            url = info.url
            scale = info.scale.map { SIMD3<Double>($0.x, $0.y, $0.z) }
        }
    }

    private var templates: [Key: RenderedRobotEntity] = [:]
    private var inFlightLoads: [Key: Task<RenderedRobotEntity, any Error>] = [:]

    private init() {}

    /// Returns a freshly cloned entity tree for the asset, loading and caching
    /// the template on first use. Concurrent requests for the same asset share
    /// a single load.
    func renderedEntity(for info: RenderAssetInfo) async throws -> RenderedRobotEntity {
        let key = Key(info)
        if let template = templates[key] {
            return try instantiate(template)
        }
        if let inFlight = inFlightLoads[key] {
            return try instantiate(try await inFlight.value)
        }
        let load = Task { @MainActor in
            try await RenderSystem().loadRobotEntity(info: info)
        }
        inFlightLoads[key] = load
        defer { inFlightLoads[key] = nil }
        let template = try await load.value
        templates[key] = template
        return try instantiate(template)
    }

    func removeAll() {
        templates.removeAll()
    }

    private func instantiate(_ template: RenderedRobotEntity) throws -> RenderedRobotEntity {
        let clone = template.entity.clone(recursive: true)
        let bindings = try template.jointBindings.map { binding -> RenderJointBinding in
            guard let entity = clone.findEntity(named: binding.name) else {
                throw CacheError.jointEntityNotFound(binding.name)
            }
            return RenderJointBinding(
                name: binding.name,
                order: binding.order,
                entity: entity,
                motion: binding.motion,
                basePosition: binding.basePosition,
                baseRotation: binding.baseRotation,
                axis: binding.axis
            )
        }
        return RenderedRobotEntity(entity: clone, jointBindings: bindings)
    }
}
