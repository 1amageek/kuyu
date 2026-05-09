import Foundation
import KuyuPhysics
import ManasCore

public struct ManasMLXModelBundleManifestBuilder: Sendable {
    public init() {}

    public func build(
        bundleID: String,
        createdAt: Date,
        parentBundleID: String? = nil,
        manifest: ManasMLXModelManifest,
        descriptor: RobotDescriptor?,
        checkpointRoot: URL,
        runtimeContractOverride: ManasModelBundleRuntimeContract? = nil
    ) throws -> ManasModelBundleManifest {
        let configHash = try ConfigHash.hash(manifest)
        let descriptorHash = try descriptor.map(ConfigHash.hash) ?? "descriptor-unbound"
        var components = [
            try component(
                role: .modelConfig,
                path: "model.json",
                contentType: "application/json",
                checkpointRoot: checkpointRoot
            ),
            try component(
                role: .coreWeights,
                path: "core.safetensors",
                contentType: "application/vnd.safetensors",
                checkpointRoot: checkpointRoot
            )
        ]

        if manifest.reflexConfig != nil {
            components.append(try component(
                role: .reflexWeights,
                path: "reflex.safetensors",
                contentType: "application/vnd.safetensors",
                checkpointRoot: checkpointRoot
            ))
        }

        return ManasModelBundleManifest(
            bundleID: bundleID,
            createdAt: createdAt,
            parentBundleID: parentBundleID,
            runtimeContract: runtimeContractOverride ?? .init(
                descriptorHash: descriptorHash,
                configHash: configHash,
                observationSchemaID: "trunk-vector-\(manifest.coreConfig.inputSize)",
                driveSemanticsID: "drive-intent-\(manifest.coreConfig.driveCount)",
                motorNerveProfileID: descriptor?.robot.robotID
            ),
            components: components
        )
    }

    private func component(
        role: ManasModelBundleComponentRole,
        path: String,
        contentType: String,
        checkpointRoot: URL
    ) throws -> ManasModelBundleComponent {
        let url = checkpointRoot.appendingPathComponent(path, isDirectory: false)
        let data = try Data(contentsOf: url)
        return ManasModelBundleComponent(
            role: role,
            path: path,
            contentType: contentType,
            required: true,
            byteCount: data.count,
            fnv1a64: ManasModelBundleValidator.fnv1a64Hex(for: data)
        )
    }
}
