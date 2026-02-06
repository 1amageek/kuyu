import Foundation
import KuyuCore
import KuyuProfiles

public struct BodySceneState: Sendable, Equatable, Identifiable {
    public let id: String
    let position: Axis3
    let velocity: Axis3
    let orientation: QuaternionSnapshot
    let angularVelocity: Axis3
}

public struct SceneState: Sendable, Equatable {
    let time: Double
    let bodies: [BodySceneState]
}

public struct RenderAssetInfo: Sendable, Equatable {
    let name: String
    let url: URL
    let format: RenderMeshFormat
}
