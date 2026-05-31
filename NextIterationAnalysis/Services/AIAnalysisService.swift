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
        poseFrames: [PoseFrame],
        critique: TechniqueCritique
    ) async -> TechniqueCritique {
        guard let endpoint = configuration.endpoint else {
            return critique
        }

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey = configuration.apiKey {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            let payload = AIAnalysisPayload(
                liftType: details.liftType.rawValue,
                weight: details.weight,
                unit: details.unit.rawValue,
                reps: details.reps,
                rpe: details.rpe,
                goal: details.goal.rawValue,
                metrics: metrics,
                poseFrameCount: poseFrames.count,
                averagePoseConfidence: poseFrames.map(\.confidence).average,
                ruleBasedCritique: critique,
                rawVideo: rawVideoPayload(videoURL: videoURL)
            )

            request.httpBody = try JSONEncoder.liftPath.encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return critique
            }

            return try JSONDecoder.liftPath.decode(TechniqueCritique.self, from: data)
        } catch {
            return critique
        }
    }

    private func rawVideoPayload(videoURL: URL?) -> RawVideoPayload? {
        guard configuration.allowsRawVideoUpload,
              let videoURL = videoURL,
              let data = try? Data(contentsOf: videoURL) else {
            return nil
        }

        return RawVideoPayload(
            fileName: videoURL.lastPathComponent,
            contentType: "video/quicktime",
            base64Data: data.base64EncodedString()
        )
    }
}

private struct AIAnalysisPayload: Codable {
    let liftType: String
    let weight: Double
    let unit: String
    let reps: Int
    let rpe: Double?
    let goal: String
    let metrics: LiftMetrics
    let poseFrameCount: Int
    let averagePoseConfidence: Double
    let ruleBasedCritique: TechniqueCritique
    let rawVideo: RawVideoPayload?
}

private struct RawVideoPayload: Codable {
    let fileName: String
    let contentType: String
    let base64Data: String
}

private extension Array where Element == Double {
    var average: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
}
