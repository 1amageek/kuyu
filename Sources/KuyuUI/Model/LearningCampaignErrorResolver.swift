enum LearningCampaignErrorResolver {
    static func resolve(
        input: String?,
        execution: String?,
        artifact: String?
    ) -> String? {
        input ?? execution ?? artifact
    }
}
