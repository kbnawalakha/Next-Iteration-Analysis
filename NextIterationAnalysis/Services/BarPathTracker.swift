import Foundation

enum TrackingMode: String, CaseIterable, Identifiable {
    case manual
    case automaticPlateDetection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .automaticPlateDetection: return "Auto Plate"
        }
    }
}

struct NormalizedPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct PlateDetectionResult {
    let point: NormalizedPoint
    let confidence: Double
    let explanation: String
}

final class AutomaticPlateDetectionService {
    func detectPlateStartPoint(videoURL: URL?, thumbnailURL: URL?) async -> PlateDetectionResult {
        // MVP heuristic: seed a likely bar-end region. Replace this service with a Vision/Core ML detector.
        PlateDetectionResult(
            point: NormalizedPoint(x: 0.68, y: 0.46),
            confidence: 0.42,
            explanation: "Automatic detection is using a first-frame heuristic. Tap the image to correct the point if needed."
        )
    }
}

final class BarPathTracker {
    func track(
        videoURL: URL?,
        startingPoint: NormalizedPoint,
        reps: Int,
        mode: TrackingMode
    ) async -> [TrackedPoint] {
        let frameCount = max(90, reps * 42)
        let cycles = Double(max(reps, 1))
        let confidenceBase = mode == .manual ? 0.82 : 0.64

        let rawPoints = (0..<frameCount).map { index in
            let progress = Double(index) / Double(frameCount - 1)
            let phase = progress * cycles * .pi * 2
            let repTravel = sin(phase - .pi / 2) * 0.18
            let drift = sin(progress * .pi * 1.4) * 0.035
            let wobble = sin(Double(index) * 0.61) * 0.006

            return TrackedPoint(
                id: UUID(),
                timestamp: progress * Double(reps) * 1.6,
                frameIndex: index,
                x: clamp(startingPoint.x + drift + wobble, 0.04, 0.96),
                y: clamp(startingPoint.y + repTravel, 0.04, 0.96),
                confidence: clamp(confidenceBase - abs(wobble), 0.1, 0.98)
            )
        }

        return SmoothingUtils.movingAverage(rawPoints)
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
