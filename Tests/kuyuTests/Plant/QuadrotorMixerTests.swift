import Testing
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func quadrotorMixerBalancesEqualThrusts() async throws {
    let mixer = QuadrotorMixer(armLength: 0.12, yawCoefficient: 0.02)
    let thrusts = try MotorThrusts(f1: 1, f2: 1, f3: 1, f4: 1)
    let mix = mixer.mix(thrusts: thrusts)

    #expect(mix.forceBody.z == 4)
    #expect(mix.forceBody.x == 0)
    #expect(mix.forceBody.y == 0)
    #expect(mix.torqueBody.x == 0)
    #expect(mix.torqueBody.y == 0)
    #expect(mix.torqueBody.z == 0)
}
