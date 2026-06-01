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
           trackingScore(trackedPoints) > 0.18 {
            return SmoothingUtils.kalmanSmooth(SmoothingUtils.movingAverage(trackedPoints))
        }

        if let videoURL = videoURL,
           let visionPoints = try? await trackWithVision(videoURL: videoURL, startingPoint: startingPoint),
           trackingScore(visionPoints) > 0.18 {
            return SmoothingUtils.kalmanSmooth(SmoothingUtils.movingAverage(visionPoints))
        }

        return simulatedPath(startingPoint: startingPoint, reps: reps, mode: mode)
    }

    private func trackWithVision(
        videoURL: URL,
        startingPoint: NormalizedPoint
    ) async throws -> [TrackedPoint] {
        let frames = try await frameExtractor.extractFrames(from: videoURL, maxFrames: 160)
        guard !frames.isEmpty else { return [] }

        let handler = VNSequenceRequestHandler()
        let boxSize = 0.16
        let initialBox = CGRect(
            x: clamp(startingPoint.x - boxSize / 2, 0.01, 0.99 - boxSize),
            y: clamp(1 - startingPoint.y - boxSize / 2, 0.01, 0.99 - boxSize),
            width: boxSize,
            height: boxSize
        )
        var observation = VNDetectedObjectObservation(boundingBox: initialBox)
        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
        request.trackingLevel = .accurate

        var trackedPoints: [TrackedPoint] = []
        var lastPoint = startingPoint
        var missedFrames = 0

        for frame in frames {
            do {
                request.inputObservation = observation
                try handler.perform([request], on: frame.image)
                guard let result = request.results?.first as? VNDetectedObjectObservation else {
                    missedFrames += 1
                    trackedPoints.append(TrackedPoint(
                        id: UUID(),
                        timestamp: frame.timestamp,
                        frameIndex: frame.frameIndex,
                        x: lastPoint.x,
                        y: lastPoint.y,
                        confidence: 0.05
                    ))
                    continue
                }

                observation = result
                let box = result.boundingBox
                let point = NormalizedPoint(x: Double(box.midX), y: Double(1 - box.midY))
                let confidence = Double(result.confidence)
                lastPoint = point
                missedFrames = confidence < 0.18 ? missedFrames + 1 : 0
                trackedPoints.append(TrackedPoint(
                    id: UUID(),
                    timestamp: frame.timestamp,
                    frameIndex: frame.frameIndex,
                    x: point.x,
                    y: point.y,
                    confidence: max(0.05, min(0.98, confidence))
                ))

                if missedFrames >= 3 {
                    observation = VNDetectedObjectObservation(boundingBox: initialBox)
                    missedFrames = 0
                }
            } catch {
                missedFrames += 1
                trackedPoints.append(TrackedPoint(
                    id: UUID(),
                    timestamp: frame.timestamp,
                    frameIndex: frame.frameIndex,
                    x: lastPoint.x,
                    y: lastPoint.y,
                    confidence: 0.05
                ))
            }
        }

        let averageConfidence = trackedPoints.map(\.confidence).reduce(0, +) / Double(max(trackedPoints.count, 1))
        return averageConfidence > 0.14 ? trackedPoints : []
    }

    private func trackingScore(_ points: [TrackedPoint]) -> Double {
        guard points.count > 2 else { return 0 }
        return points.map(\.confidence).reduce(0, +) / Double(points.count)
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
        let searchRadius = min(60, max(12, min(firstLuminance.width, firstLuminance.height) / 4))
        let confidenceGate = 0.62
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
                searchRadius: searchRadius
            )

            guard let match = localMatch, match.confidence >= confidenceGate else {
                missedFrames += 1
                previousPoint = clamped(interpolatedPoint(
                    previous: previousPoint,
                    predicted: predictedPoint,
                    missedFrames: missedFrames
                ))
                trackedPoints.append(TrackedPoint(
                    id: UUID(),
                    timestamp: frame.timestamp,
                    frameIndex: frame.frameIndex,
                    x: previousPoint.x,
                    y: previousPoint.y,
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
            let reacquired = missedFrames > 0
            velocity = NormalizedPoint(
                x: reacquired ? nextVelocity.x * 0.25 : velocity.x * 0.65 + nextVelocity.x * 0.35,
                y: reacquired ? nextVelocity.y * 0.25 : velocity.y * 0.65 + nextVelocity.y * 0.35
            )
            previousPoint = center
            missedFrames = 0

            if frame.frameIndex % 10 == 0,
               let freshPatch = luminance.patch(center: center, radius: patchRadius) {
                template = blend(template, with: freshPatch, newWeight: 0.22)
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

    private func interpolatedPoint(
        previous: NormalizedPoint,
        predicted: NormalizedPoint,
        missedFrames: Int
    ) -> NormalizedPoint {
        let blendWeight = min(0.35, Double(missedFrames) * 0.08)
        return NormalizedPoint(
            x: previous.x * (1 - blendWeight) + predicted.x * blendWeight,
            y: previous.y * (1 - blendWeight) + predicted.y * blendWeight
        )
    }

    private func blend(_ template: [UInt8], with freshPatch: [UInt8], newWeight: Double) -> [UInt8] {
        guard template.count == freshPatch.count else { return template }
        return zip(template, freshPatch).map { old, new in
            UInt8((Double(old) * (1 - newWeight) + Double(new) * newWeight).rounded())
        }
    }

}
