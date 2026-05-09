public extension LearningCampaignRunConfig {
    func optimizedForMachine(
        _ capacity: LearningCampaignMachineCapacity = .current()
    ) -> LearningCampaignRunConfig {
        let recommendation = capacity.recommendation(
            population: population,
            suiteCount: suites.count,
            episodes: episodes
        )
        var updated = self
        updated.workers = recommendation.workerCount
        updated.candidateEvaluationConcurrency = recommendation.candidateEvaluationConcurrency
        return updated
    }
}
