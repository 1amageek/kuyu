import Testing
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

@Test func descendingIntentProgramInterpolatesLinearly() throws {
    let program = try DescendingIntentProgram(keyframes: [
        try DescendingIntentProgram.Keyframe(time: 0.0, values: [0.0, -1.0]),
        try DescendingIntentProgram.Keyframe(time: 2.0, values: [1.0, 1.0]),
    ])

    let vector = program.vector(at: 1.0)
    #expect(vector.count == 2)
    #expect(abs(vector[0] - 0.5) < 1e-9)
    #expect(abs(vector[1] - 0.0) < 1e-9)
}

@Test func descendingIntentProgramClampsOutsideKeyframeRange() throws {
    let program = try DescendingIntentProgram(keyframes: [
        try DescendingIntentProgram.Keyframe(time: 0.2, values: [0.2]),
        try DescendingIntentProgram.Keyframe(time: 0.6, values: [0.6]),
    ])

    #expect(program.vector(at: 0.0) == [0.2])
    #expect(program.vector(at: 1.0) == [0.6])
}

@Test func descendingIntentProgramRejectsNonIncreasingTimes() throws {
    do {
        _ = try DescendingIntentProgram(keyframes: [
            try DescendingIntentProgram.Keyframe(time: 0.5, values: [0.1]),
            try DescendingIntentProgram.Keyframe(time: 0.5, values: [0.2]),
        ])
        #expect(Bool(false))
    } catch let error as DescendingIntentProgram.ProgramError {
        #expect(error == .nonIncreasingTime(index: 1))
    }
}
