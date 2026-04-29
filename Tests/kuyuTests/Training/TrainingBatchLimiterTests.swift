import KuyuMLX
import Testing

@Test func trainingBatchLimiterSamplesAcrossWholeInterleavedRange() {
    let batches = Array(0..<30)
    let selected = TrainingBatchLimiter(limit: 5).select(batches)

    #expect(selected == [0, 7, 15, 22, 29])
}

@Test func trainingBatchLimiterKeepsAllBatchesWhenLimitDoesNotApply() {
    let batches = Array(0..<4)
    let selected = TrainingBatchLimiter(limit: 4).select(batches)

    #expect(selected == batches)
}

@Test func trainingBatchLimiterHonorsCurrentCount() {
    let batches = Array(0..<10)
    let selected = TrainingBatchLimiter(limit: 5, currentCount: 3).select(batches)

    #expect(selected == [0, 9])
}
