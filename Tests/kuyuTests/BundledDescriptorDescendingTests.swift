import Foundation
import Testing
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

@Test func bundledSinglePropDescriptorDefinesDescendingChannels() async throws {
    let loaded = try loadBundledDescriptor(relativePath: "Sources/KuyuUI/Resources/Models/SingleProp/singleprop.model.json")
    let descriptor = loaded.descriptor

    #expect(descriptor.signals.descending?.count == 1)
    #expect(descriptor.control.descendingChannels == ["intent.thrust"])
}

@Test func bundledQuadDescriptorDefinesDescendingChannels() async throws {
    let loaded = try loadBundledDescriptor(relativePath: "Sources/KuyuUI/Resources/Models/QuadRef/quadref.model.json")
    let descriptor = loaded.descriptor

    #expect(descriptor.signals.descending?.count == 4)
    #expect(descriptor.control.descendingChannels == [
        "intent.thrust",
        "intent.roll",
        "intent.pitch",
        "intent.yaw",
    ])
}

private func loadBundledDescriptor(relativePath: String) throws -> LoadedRobotDescriptor {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let packageRoot = testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let descriptorPath = packageRoot.appendingPathComponent(relativePath).path
    return try RobotDescriptorLoader().loadDescriptor(path: descriptorPath)
}
