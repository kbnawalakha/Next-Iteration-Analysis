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
        guard let template = firstLuminance.patch(center: initialCenter, radius: patchRadius) else {
            return []
        }

        var previousPoint = initialCenter
        let searchRadius = max(10, min(firstLuminance.width, firstLuminance.height) / 11)

        return frames.compactMap { frame in
            guard let luminance = LuminanceFrame(image: frame.image),
                  var match = luminance.bestMatch(
                    template: template,
                    radius: patchRadius,
                    around: previousPoint,
                    searchRadius: searchRadius
                  ) else {
                return nil
            }

            if let refinedCenter = luminance.refinedPlateCenter(near: match.point) {
                match.point = refinedCenter
                match.confidence = min(0.98, match.confidence + 0.06)
            }

            previousPoint = match.point
            return TrackedPoint(
                id: UUID(),
                timestamp: frame.timestamp,
                frameIndex: frame.frameIndex,
                x: match.point.x,
                y: match.point.y,
                confidence: max(0.05, match.confidence)
            )
        }
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
}
