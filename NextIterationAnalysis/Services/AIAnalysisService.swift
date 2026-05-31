import Foundation

struct AIBackendConfiguration {
    var endpoint: URL?
    var apiKey: String?
    var allowsRawVideoUpload: Bool = false
}

final class AIAnalysisService {
    var configuration = AIBackendConfiguration(endpoint: nil, apiKey: nil, allowsRawVideoUpload: false)

    func refineCritique(
        videoURL: URL?,
        details: LiftDetails,
        metrics: LiftMetrics,
        critique: TechniqueCritique
    ) async -> TechniqueCritique {
        guard configuration.endpoint != nil else {
            return critique
        }

        // Backend-ready seam for full AI video understanding. Keep video upload opt-in because
        // training footage is sensitive and can contain bystanders or gym location details.
        return TechniqueCritique(
            summary: critique.summary,
            positives: critique.positives,
            issues: critique.issues,
            nextSessionFocus: critique.nextSessionFocus
        )
    }
}
