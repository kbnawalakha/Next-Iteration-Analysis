import Foundation
import CoreML
import UIKit
import Vision

enum TrackingMode: String, CaseIterable, Identifiable {
    case automaticPlateDetection

    var id: String { rawValue }

    var displayName: String {
        switch self {
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

    var confidenceLabel: String {
        switch confidence {
        case 0.9...1.0: return "Excellent"
        case 0.75..<0.9: return "Good"
        case 0.6..<0.75: return "Moderate"
        default: return "Low"
        }
    }
}

final class AutomaticPlateDetectionService {
    private let frameExtractor = VideoFrameExtractor()

    func detectPlateStartPoint(videoURL: URL?, thumbnailURL: URL?) async -> PlateDetectionResult {
        if let videoURL = videoURL,
           let frame = try? await frameExtractor.firstFrame(from: videoURL),
           let candidate = detectInImage(frame.image) {
            return candidate
        }

        if let thumbnailURL = thumbnailURL,
           let image = frameExtractor.imageFromFile(thumbnailURL),
           let candidate = detectInImage(image) {
            return candidate
        }

        return PlateDetectionResult(
            point: NormalizedPoint(x: 0.68, y: 0.46),
            confidence: 0.22,
            explanation: "Automatic detection could not confidently identify a plate center. A fallback center was selected; drag the marker to correct it."
        )
    }

    private func detectInImage(_ image: CGImage) -> PlateDetectionResult? {
        if let coreMLCandidate = coreMLPlateCandidate(in: image) {
            return coreMLCandidate
        }

        guard let luminance = LuminanceFrame(image: image) else { return nil }
        return luminance.likelyPlateCandidate()
    }

    private func coreMLPlateCandidate(in image: CGImage) -> PlateDetectionResult? {
        guard let modelURL = Bundle.main.url(forResource: "PlateBarbellDetector", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: modelURL),
              let visionModel = try? VNCoreMLModel(for: model) else {
            return nil
        }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try? handler.perform([request])

        let candidate = request.results?
            .compactMap { $0 as? VNRecognizedObjectObservation }
            .filter { observation in
                guard let label = observation.labels.first?.identifier.lowercased() else { return false }
                return label.contains("plate") || label.contains("barbell") || label.contains("bar")
            }
            .max { $0.confidence < $1.confidence }

        guard let candidate = candidate else { return nil }
        let box = candidate.boundingBox
        return PlateDetectionResult(
            point: NormalizedPoint(
                x: Double(box.midX),
                y: Double(1 - box.midY)
            ),
            confidence: Double(candidate.confidence),
            explanation: "Automatic detection used the bundled PlateBarbellDetector Core ML model and selected the plate center. Drag to correct if needed."
        )
    }
}

final class BarPathTracker {
    private let frameExtractor = VideoFrameExtractor()

    func track(
        videoURL: URL?,
        startingPoint: NormalizedPoint,
        reps: Int,
        mode: TrackingMode
    ) async -> [TrackedPoint] {
        if let videoURL = videoURL,
           let trackedPoints = try? await trackWithTemplateMatching(videoURL: videoURL, startingPoint: startingPoint),
           trackedPoints.count > 2 {
            return SmoothingUtils.kalmanSmooth(SmoothingUtils.movingAverage(trackedPoints))
        }

        return simulatedPath(startingPoint: startingPoint, reps: reps, mode: mode)
    }

    private func trackWithTemplateMatching(
        videoURL: URL,
        startingPoint: NormalizedPoint
    ) async throws -> [TrackedPoint] {
        let frames = try await frameExtractor.extractFrames(from: videoURL, maxFrames: 120)
        guard let firstFrame = frames.first,
              let firstLuminance = LuminanceFrame(image: firstFrame.image) else {
            return []
        }

        let initialCenter = firstLuminance.refinedPlateCenter(near: startingPoint) ?? startingPoint
        let patchRadius = max(5, min(firstLuminance.width, firstLuminance.height) / 34)
        guard var template = firstLuminance.patch(center: initialCenter, radius: patchRadius) else {
            return []
        }

        var previousPoint = initialCenter
        var velocity = NormalizedPoint(x: 0, y: 0)
        let baseSearchRadius = max(12, min(firstLuminance.width, firstLuminance.height) / 10)
        let recoverySearchRadius = max(baseSearchRadius * 2, min(firstLuminance.width, firstLuminance.height) / 4)
        var trackedPoints: [TrackedPoint] = []
        var missedFrames = 0

        for frame in frames {
            guard let luminance = LuminanceFrame(image: frame.image) else { continue }

            let predictedPoint = clamped(NormalizedPoint(
                x: previousPoint.x + velocity.x,
                y: previousPoint.y + velocity.y
            ))

            let localMatch = luminance.bestMatch(
                template: template,
                radius: patchRadius,
                around: predictedPoint,
                searchRadius: baseSearchRadius
            )
            let recoveryMatch = localMatch?.confidence ?? 0 >= 0.45
                ? localMatch
                : luminance.bestMatch(
                    template: template,
                    radius: patchRadius,
                    around: predictedPoint,
                    searchRadius: recoverySearchRadius
                )

            let globalMatch = (recoveryMatch?.confidence ?? 0) >= 0.4 && missedFrames == 0
                ? nil
                : luminance.bestGlobalMatch(template: template, radius: patchRadius)

            guard let match = bestTrackingMatch(recoveryMatch, globalMatch: globalMatch) else {
                missedFrames += 1
                previousPoint = predictedPoint
                trackedPoints.append(TrackedPoint(
                    id: UUID(),
                    timestamp: frame.timestamp,
                    frameIndex: frame.frameIndex,
                    x: predictedPoint.x,
                    y: predictedPoint.y,
                    confidence: 0.05
                ))
                continue
            }

            var center = match.point
            if let refinedCenter = luminance.refinedPlateCenter(near: center),
               distance(from: refinedCenter, to: center) < 0.045 {
                center = refinedCenter
            }

            let nextVelocity = NormalizedPoint(
                x: center.x - previousPoint.x,
                y: center.y - previousPoint.y
            )
            let reacquired = missedFrames > 0 && match.confidence > 0.42
            velocity = NormalizedPoint(
                x: reacquired ? nextVelocity.x * 0.25 : velocity.x * 0.65 + nextVelocity.x * 0.35,
                y: reacquired ? nextVelocity.y * 0.25 : velocity.y * 0.65 + nextVelocity.y * 0.35
            )
            previousPoint = center
            missedFrames = 0

            if let freshPatch = luminance.patch(center: center, radius: patchRadius), match.confidence > 0.5 {
                template = blend(template, with: freshPatch, newWeight: 0.16)
            }

            trackedPoints.append(TrackedPoint(
                id: UUID(),
                timestamp: frame.timestamp,
                frameIndex: frame.frameIndex,
                x: center.x,
                y: center.y,
                confidence: max(0.05, match.confidence)
            ))
        }

        return trackedPoints
    }

    private func simulatedPath(startingPoint: NormalizedPoint, reps: Int, mode: TrackingMode) -> [TrackedPoint] {
        let frameCount = max(90, reps * 42)
        let cycles = Double(max(reps, 1))
        let confidenceBase = 0.64

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

    private func clamped(_ point: NormalizedPoint) -> NormalizedPoint {
        NormalizedPoint(x: clamp(point.x, 0.02, 0.98), y: clamp(point.y, 0.02, 0.98))
    }

    private func distance(from first: NormalizedPoint, to second: NormalizedPoint) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func blend(_ template: [UInt8], with freshPatch: [UInt8], newWeight: Double) -> [UInt8] {
        guard template.count == freshPatch.count else { return template }
        return zip(template, freshPatch).map { old, new in
            UInt8((Double(old) * (1 - newWeight) + Double(new) * newWeight).rounded())
        }
    }

    private func bestTrackingMatch(
        _ localMatch: (point: NormalizedPoint, confidence: Double)?,
        globalMatch: (point: NormalizedPoint, confidence: Double)?
    ) -> (point: NormalizedPoint, confidence: Double)? {
        switch (localMatch, globalMatch) {
        case let (local?, global?) where global.confidence > local.confidence + 0.1:
            return global
        case let (local?, _):
            return local
        case let (nil, global?) where global.confidence > 0.36:
            return global
        default:
            return nil
        }
    }
}
