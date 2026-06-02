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

        if let colorFrame = PlateColorFrame(image: image),
           let colorCandidate = colorFrame.likelyPlateCandidate() {
            if let fittedCenter = LuminanceFrame(image: image)?.fittedPlate(near: colorCandidate.point)?.center {
                return PlateDetectionResult(
                    point: fittedCenter,
                    confidence: colorCandidate.confidence,
                    explanation: "Automatic detection segmented the colored plate region, then refined it to a fitted plate center. Drag to correct if needed."
                )
            }
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
                return label == "0" || label == "1" || label.contains("plate") || label.contains("barbell") || label.contains("bar")
            }
            .max { $0.confidence < $1.confidence }

        guard let candidate = candidate else { return nil }
        let box = candidate.boundingBox
        let detectedCenter = NormalizedPoint(
            x: Double(box.midX),
            y: Double(1 - box.midY)
        )
        guard let fittedCenter = LuminanceFrame(image: image)?.fittedPlate(near: detectedCenter)?.center else {
            return nil
        }
        return PlateDetectionResult(
            point: fittedCenter,
            confidence: Double(candidate.confidence),
            explanation: "Automatic detection used the bundled PlateBarbellDetector Core ML model, then refined the detected region to a fitted plate center. Drag to correct if needed."
        )
    }
}

struct PlateColorFrame {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(image: CGImage, maxWidth: Int = 260) {
        let scale = min(1, Double(maxWidth) / Double(max(image.width, 1)))
        let targetWidth = max(48, Int(Double(image.width) * scale))
        let targetHeight = max(48, Int(Double(image.height) * scale))
        var buffer = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)

        guard let context = CGContext(
            data: &buffer,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        self.width = targetWidth
        self.height = targetHeight
        self.pixels = buffer
    }

    func likelyPlateCandidate() -> PlateDetectionResult? {
        var visited = [Bool](repeating: false, count: width * height)
        var best: PlateColorComponent?

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard !visited[index], isPlateColoredPixel(x: x, y: y) else { continue }
                let component = floodFill(fromX: x, y: y, visited: &visited)
                guard component.area >= max(45, width * height / 450),
                      component.aspectRatio >= 0.45,
                      component.aspectRatio <= 2.2,
                      component.centerY < Double(height) * 0.72 else {
                    continue
                }

                if best == nil || component.score > (best?.score ?? 0) {
                    best = component
                }
            }
        }

        guard let best else { return nil }
        let point = NormalizedPoint(
            x: best.centerX / Double(width),
            y: best.centerY / Double(height)
        )
        return PlateDetectionResult(
            point: point,
            confidence: min(0.9, max(0.62, best.score)),
            explanation: "Automatic detection selected the largest saturated circular plate-like region and fitted its color-segment center. Drag to correct if needed."
        )
    }

    private func floodFill(fromX startX: Int, y startY: Int, visited: inout [Bool]) -> PlateColorComponent {
        var stack = [(startX, startY)]
        var area = 0
        var sumX = 0.0
        var sumY = 0.0
        var minX = startX
        var maxX = startX
        var minY = startY
        var maxY = startY
        var saturationTotal = 0.0

        while let (x, y) = stack.popLast() {
            guard x >= 0, x < width, y >= 0, y < height else { continue }
            let index = y * width + x
            guard !visited[index], isPlateColoredPixel(x: x, y: y) else { continue }
            visited[index] = true

            let saturation = pixelHSV(x: x, y: y).saturation
            area += 1
            sumX += Double(x)
            sumY += Double(y)
            saturationTotal += saturation
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)

            stack.append((x + 1, y))
            stack.append((x - 1, y))
            stack.append((x, y + 1))
            stack.append((x, y - 1))
        }

        let boxWidth = max(1, maxX - minX + 1)
        let boxHeight = max(1, maxY - minY + 1)
        let fillRatio = Double(area) / Double(boxWidth * boxHeight)
        let aspect = Double(boxWidth) / Double(boxHeight)
        let averageSaturation = saturationTotal / Double(max(area, 1))
        let areaScore = min(1, Double(area) / Double(max(width * height / 30, 1)))
        let roundnessScore = max(0, 1 - abs(1 - aspect) * 0.45)
        let score = averageSaturation * 0.35 + fillRatio * 0.25 + areaScore * 0.25 + roundnessScore * 0.15

        return PlateColorComponent(
            area: area,
            centerX: sumX / Double(max(area, 1)),
            centerY: sumY / Double(max(area, 1)),
            aspectRatio: aspect,
            score: score
        )
    }

    private func isPlateColoredPixel(x: Int, y: Int) -> Bool {
        let hsv = pixelHSV(x: x, y: y)
        guard hsv.saturation > 0.28, hsv.value > 0.18 else { return false }
        let hue = hsv.hue
        let isGreen = hue >= 55 && hue <= 175
        let isBlue = hue >= 185 && hue <= 255
        let isRed = hue <= 22 || hue >= 335
        let isYellow = hue >= 35 && hue <= 58
        return isGreen || isBlue || isRed || isYellow
    }

    private func pixelHSV(x: Int, y: Int) -> (hue: Double, saturation: Double, value: Double) {
        let index = (y * width + x) * 4
        let red = Double(pixels[index]) / 255
        let green = Double(pixels[index + 1]) / 255
        let blue = Double(pixels[index + 2]) / 255
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        let saturation = maxValue == 0 ? 0 : delta / maxValue

        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maxValue == red {
            hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == green {
            hue = 60 * ((blue - red) / delta + 2)
        } else {
            hue = 60 * ((red - green) / delta + 4)
        }

        return (hue < 0 ? hue + 360 : hue, saturation, maxValue)
    }
}

private struct PlateColorComponent {
    let area: Int
    let centerX: Double
    let centerY: Double
    let aspectRatio: Double
    let score: Double
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
           let trackedPoints = try? await trackWithPlateCenterFitting(videoURL: videoURL, startingPoint: startingPoint),
           trackingScore(trackedPoints) > 0.18 {
            return preserveInitialPoint(
                SmoothingUtils.kalmanSmooth(SmoothingUtils.movingAverage(trackedPoints)),
                startingPoint: startingPoint
            )
        }

        if videoURL != nil {
            return correctionRequiredPath(startingPoint: startingPoint)
        }

        return simulatedPath(startingPoint: startingPoint, reps: reps, mode: mode)
    }

    private func trackWithPlateCenterFitting(
        videoURL: URL,
        startingPoint: NormalizedPoint
    ) async throws -> [TrackedPoint] {
        let frames = try await frameExtractor.extractFrames(from: videoURL, maxFrames: 160)
        guard let firstFrame = frames.first,
              let firstLuminance = LuminanceFrame(image: firstFrame.image) else {
            return []
        }

        let anchorSearchRadius = max(10, min(firstLuminance.width, firstLuminance.height) / 12)
        guard let initialFit = firstLuminance.fittedPlate(
            near: startingPoint,
            maxCenterDistancePixels: Double(anchorSearchRadius)
        ) else {
            return []
        }

        var previousPoint = initialFit.center
        var previousRadius = initialFit.radiusPixels
        var velocity = NormalizedPoint(x: 0, y: 0)
        var missedFrames = 0
        var trackedPoints: [TrackedPoint] = [
            TrackedPoint(
                id: UUID(),
                timestamp: firstFrame.timestamp,
                frameIndex: firstFrame.frameIndex,
                x: previousPoint.x,
                y: previousPoint.y,
                confidence: max(0.72, initialFit.confidence)
            )
        ]

        for frame in frames.dropFirst() {
            guard let luminance = LuminanceFrame(image: frame.image) else { continue }
            let maxJumpPixels = max(10, min(60, previousRadius * 1.15))
            let predictedPoint = pointWithinPixelRadius(
                clamped(NormalizedPoint(
                    x: previousPoint.x + velocity.x,
                    y: previousPoint.y + velocity.y
                )),
                anchor: previousPoint,
                maxPixels: maxJumpPixels,
                frameWidth: luminance.width,
                frameHeight: luminance.height
            )

            let refit = luminance.fittedPlate(
                near: predictedPoint,
                expectedRadiusPixels: previousRadius,
                maxCenterDistancePixels: maxJumpPixels
            )

            guard let fit = refit,
                  isConsistentPlateFit(
                    fit,
                    previousPoint: previousPoint,
                    previousRadiusPixels: previousRadius,
                    maxJumpPixels: maxJumpPixels,
                    frameWidth: luminance.width,
                    frameHeight: luminance.height
                  ) else {
                missedFrames += 1
                velocity = NormalizedPoint(x: velocity.x * 0.35, y: velocity.y * 0.35)
                trackedPoints.append(TrackedPoint(
                    id: UUID(),
                    timestamp: frame.timestamp,
                    frameIndex: frame.frameIndex,
                    x: previousPoint.x,
                    y: previousPoint.y,
                    confidence: missedFrames <= 5 ? 0.12 : 0.04
                ))
                continue
            }

            let nextVelocity = NormalizedPoint(
                x: fit.center.x - previousPoint.x,
                y: fit.center.y - previousPoint.y
            )
            velocity = NormalizedPoint(
                x: velocity.x * 0.72 + nextVelocity.x * 0.28,
                y: velocity.y * 0.72 + nextVelocity.y * 0.28
            )
            previousPoint = fit.center
            previousRadius = previousRadius * 0.82 + fit.radiusPixels * 0.18
            missedFrames = 0

            trackedPoints.append(TrackedPoint(
                id: UUID(),
                timestamp: frame.timestamp,
                frameIndex: frame.frameIndex,
                x: fit.center.x,
                y: fit.center.y,
                confidence: max(0.2, min(0.96, fit.confidence))
            ))
        }

        return trackedPoints
    }

    private func trackingScore(_ points: [TrackedPoint]) -> Double {
        guard points.count > 2 else { return 0 }
        return points.map(\.confidence).reduce(0, +) / Double(points.count)
    }

    private func preserveInitialPoint(_ points: [TrackedPoint], startingPoint: NormalizedPoint) -> [TrackedPoint] {
        guard let first = points.first else { return points }
        var corrected = points
        corrected[0] = TrackedPoint(
            id: first.id,
            timestamp: first.timestamp,
            frameIndex: first.frameIndex,
            x: startingPoint.x,
            y: startingPoint.y,
            confidence: max(first.confidence, 0.82)
        )
        return corrected
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

    private func isConsistentPlateFit(
        _ fit: PlateFit,
        previousPoint: NormalizedPoint,
        previousRadiusPixels: Double,
        maxJumpPixels: Double,
        frameWidth: Int,
        frameHeight: Int
    ) -> Bool {
        let distancePixels = pixelDistance(
            from: fit.center,
            to: previousPoint,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )
        let radiusRatio = fit.radiusPixels / max(previousRadiusPixels, 1)
        let areaRatio = fit.areaPixels / max(Double.pi * previousRadiusPixels * previousRadiusPixels, 1)

        return distancePixels <= maxJumpPixels
            && radiusRatio >= 0.58
            && radiusRatio <= 1.58
            && areaRatio >= 0.34
            && areaRatio <= 2.5
            && fit.circularity >= 0.18
            && fit.confidence >= 0.2
    }

    private func pointWithinPixelRadius(
        _ point: NormalizedPoint,
        anchor: NormalizedPoint,
        maxPixels: Double,
        frameWidth: Int,
        frameHeight: Int
    ) -> NormalizedPoint {
        let dx = (point.x - anchor.x) * Double(frameWidth)
        let dy = (point.y - anchor.y) * Double(frameHeight)
        let distance = hypot(dx, dy)
        guard distance > maxPixels, distance > 0 else { return point }
        let scale = maxPixels / distance
        return clamped(NormalizedPoint(
            x: anchor.x + (point.x - anchor.x) * scale,
            y: anchor.y + (point.y - anchor.y) * scale
        ))
    }

    private func pixelDistance(
        from first: NormalizedPoint,
        to second: NormalizedPoint,
        frameWidth: Int,
        frameHeight: Int
    ) -> Double {
        hypot(
            (first.x - second.x) * Double(frameWidth),
            (first.y - second.y) * Double(frameHeight)
        )
    }

    private func correctionRequiredPath(startingPoint: NormalizedPoint) -> [TrackedPoint] {
        [
            TrackedPoint(
                id: UUID(),
                timestamp: 0,
                frameIndex: 0,
                x: startingPoint.x,
                y: startingPoint.y,
                confidence: 0.03
            )
        ]
    }

}
