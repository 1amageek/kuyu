import Testing
@testable import kuyu

@Test(.timeLimit(.minutes(1))) func axis3ConvertsToSimd() async throws {
    let axis = Axis3(x: 1.0, y: -2.0, z: 3.5)
    #expect(axis.simd.x == 1.0)
    #expect(axis.simd.y == -2.0)
    #expect(axis.simd.z == 3.5)
}
