import Testing
import KuyuCore
import KuyuProfiles

@Test func quadrotorReferenceUsesDescriptorMassAndInertia() async throws {
    let inertial = PlantInertialProperties(
        mass: 2.4,
        inertia: Axis3(x: 0.02, y: 0.03, z: 0.04)
    )

    let parameters = try ReferenceQuadrotorParameters.reference(from: inertial, robotID: "custom-aerial")

    #expect(parameters.mass == 2.4)
    #expect(parameters.inertia == Axis3(x: 0.02, y: 0.03, z: 0.04))
    #expect(parameters.maxThrust == ReferenceQuadrotorParameters.baseline.maxThrust)
}

@Test func quadrotorReferenceAppliesSinglePropMaxThrustTuning() async throws {
    let inertial = PlantInertialProperties(
        mass: 1.2,
        inertia: Axis3(x: 0.01, y: 0.01, z: 0.02)
    )

    let parameters = try ReferenceQuadrotorParameters.reference(from: inertial, robotID: "singleprop-demo")

    #expect(parameters.maxThrust == 12.0)
}
