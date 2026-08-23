import KuyuCore
import KuyuPhysics
import SwiftUI

public struct RobotModelPreviewWindowContentView: View {
    private let robotManifestPath: String

    @State private var renderInfo: RenderAssetInfo?
    @State private var loadError: String?

    public init(robotManifestPath: String = KuyuUIModelPaths.defaultRoArmM1RobotManifestPath()) {
        self.robotManifestPath = robotManifestPath
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if let renderInfo {
                WorldRealityView(
                    roll: 0,
                    pitch: 0,
                    yaw: 0,
                    position: Axis3(x: 0, y: 0, z: 0),
                    label: renderInfo.name,
                    renderInfo: renderInfo
                )
            } else {
                ProgressView("Loading model")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(8)
            }
        }
        .task {
            loadModel()
        }
    }

    private func loadModel() {
        do {
            let loaded = try KuyuModelLoader().loadRobot(path: robotManifestPath)
            let loader = KuyuModelLoader()
            if let asset = loader.primaryRenderAsset(robot: loaded) {
                renderInfo = RenderAssetInfo(
                    name: asset.name,
                    url: loader.resolveRenderAsset(asset, baseURL: loaded.baseURL),
                    format: asset.format,
                    scale: asset.scale
                )
                return
            }

            loadError = "No renderable model asset"
        } catch {
            loadError = "\(error)"
        }
    }
}
#Preview {
    RobotModelPreviewWindowContentView()
        .frame(width: 800, height: 560)
}
