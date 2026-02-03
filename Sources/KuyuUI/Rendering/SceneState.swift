import Foundation
import KuyuCore

struct RobotSceneState: Sendable, Equatable, Identifiable {
    let id: String
    let position: Axis3
    let velocity: Axis3
    let orientation: QuaternionSnapshot
    let angularVelocity: Axis3
}

struct SceneState: Sendable, Equatable {
    let time: Double
    let robots: [RobotSceneState]
}

struct RenderAssetInfo: Sendable, Equatable {
    let name: String
    let url: URL
    let format: RenderMeshFormat
}
