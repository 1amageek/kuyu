import Testing
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func determinismTier1RequiresTolerance() async throws {
    do {
        _ = try DeterminismConfig(tier: .tier1, tier1Tolerance: nil)
        #expect(Bool(false))
    } catch let error as DeterminismConfig.ValidationError {
        #expect(error == .missingTier1Tolerance)
    }
}

@Test(.timeLimit(.minutes(1))) func determinismTier0AllowsNil() async throws {
    let config = try DeterminismConfig(tier: .tier0, tier1Tolerance: nil)
    #expect(config.tier == .tier0)
    #expect(config.tier1Tolerance == nil)
}
