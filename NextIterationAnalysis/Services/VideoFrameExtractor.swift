import AVFoundation
import CoreGraphics
import Foundation
import UIKit

struct VideoFrame {
    let timestamp: Double
    let frameIndex: Int
    let image: CGImage
    let nominalFrameRate: Double
}

final class VideoFrameExtractor {
    func nominalFrameRate(for url: URL) async -> Double {
        (try? await Self.videoFrameRate(for: AVURLAsset(url: url))) ?? 30
    }

    /// Extracts frames for tracking. By default it samples at the video's own
    /// frame rate (one sample per source frame) so the tracked path and overlay
    /// line up exactly with playback and so fast movement isn't skipped — the
    /// previous fixed 160-frame cap left large gaps between samples, which made
    /// the tracker lose the plate on quick reps. `maxFrames` only acts as a
    /// memory safety cap for very long clips; pair it with `timeRange` (trim)
    /// to keep full-fps fidelity on a long video.
    func extractFrames(
        from url: URL,
        maxFrames: Int = 600,
        timeRange: ClosedRange<Double>? = nil,
        maxImageDimension: Int = 640,
        usesExactTiming: Bool = true
    ) async throws -> [VideoFrame] {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let fullDuration = try await asset.load(.duration).seconds
            guard fullDuration.isFinite, fullDuration > 0 else { return [] }

            let start = max(0, timeRange?.lowerBound ?? 0)
            let end = min(fullDuration, timeRange?.upperBound ?? fullDuration)
            let span = end - start
            guard span > 0 else { return [] }

            let fps = try await Self.videoFrameRate(for: asset)
            // One sample per source frame across the (optionally trimmed) span.
            let nativeFrameCount = max(1, Int((span * max(fps, 1)).rounded()))
            let frameCount = min(max(1, maxFrames), nativeFrameCount)
            let step = span / Double(frameCount)

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let boundedMaxDimension = max(160, maxImageDimension)
            generator.maximumSize = CGSize(width: CGFloat(boundedMaxDimension), height: CGFloat(boundedMaxDimension))
            let tolerance = usesExactTiming
                ? CMTime.zero
                : CMTime(seconds: max(0.01, step * 0.5), preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance

            return (0..<frameCount).compactMap { index in
                // Sample the centre of each frame interval within the span.
                let seconds = start + (Double(index) + 0.5) * step
                let time = CMTime(seconds: seconds, preferredTimescale: 600)

                do {
                    var actualTime = CMTime.zero
                    let image = try generator.copyCGImage(at: time, actualTime: &actualTime)
                    let resolvedSeconds = actualTime.seconds.isFinite ? actualTime.seconds : seconds
                    return VideoFrame(
                        timestamp: max(0, resolvedSeconds - start),
                        frameIndex: index,
                        image: image,
                        nominalFrameRate: fps
                    )
                } catch {
                    return nil
                }
            }
        }.value
    }

    func firstFrame(from url: URL) async throws -> VideoFrame? {
        try await firstFrame(from: url, at: 0)
    }

    func firstFrame(from url: URL, at seconds: Double) async throws -> VideoFrame? {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 900, height: 900)

            var actualTime = CMTime.zero
            let requestedTime = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            let image = try generator.copyCGImage(at: requestedTime, actualTime: &actualTime)
            return VideoFrame(
                timestamp: 0,
                frameIndex: 0,
                image: image,
                nominalFrameRate: try await Self.videoFrameRate(for: asset)
            )
        }.value
    }

    func imageFromFile(_ url: URL) -> CGImage? {
        UIImage(contentsOfFile: url.path)?.cgImage
    }

    private static func videoFrameRate(for asset: AVURLAsset) async throws -> Double {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let nominalFrameRate = try await tracks.first?.load(.nominalFrameRate) ?? 0
        return Double(nominalFrameRate > 0 ? nominalFrameRate : 30)
    }
}

struct LuminanceFrame {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(image: CGImage, maxWidth: Int = 240) {
        let scale = min(1, Double(maxWidth) / Double(max(image.width, 1)))
        let targetWidth = max(48, Int(Double(image.width) * scale))
        let targetHeight = max(48, Int(Double(image.height) * scale))
        var buffer = [UInt8](repeating: 0, count: targetWidth * targetHeight)

        guard let context = CGContext(
            data: &buffer,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
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
        let radius = max(7, min(width, height) / 22)
        var bestScore = 0.0
        var bestPoint: NormalizedPoint?

        let minX = Int(Double(width) * 0.25)
        let maxX = Int(Double(width) * 0.92)
        let minY = Int(Double(height) * 0.12)
        let maxY = Int(Double(height) * 0.82)

        for y in stride(from: minY, through: maxY, by: max(3, radius / 2)) {
            for x in stride(from: minX, through: maxX, by: max(3, radius / 2)) {
                let score = circularContrastScore(centerX: x, centerY: y, radius: radius)
                if score > bestScore {
                    bestScore = score
                    bestPoint = NormalizedPoint(x: Double(x) / Double(width), y: Double(y) / Double(height))
                }
            }
        }

        guard let bestPoint = bestPoint, bestScore > 0.12 else { return nil }
        let center = refinedPlateCenter(near: bestPoint) ?? bestPoint
        return PlateDetectionResult(
            point: center,
            confidence: max(0.2, min(0.88, bestScore)),
            explanation: "Automatic detection selected the strongest round high-contrast plate candidate and fitted its center. Drag to correct if it chose the wrong plate."
        )
    }

    func refinedPlateCenter(near point: NormalizedPoint) -> NormalizedPoint? {
        fittedPlate(near: point)?.center
    }

    func fittedPlate(
        near point: NormalizedPoint,
        expectedRadiusPixels: Double? = nil,
        maxCenterDistancePixels: Double? = nil
    ) -> PlateFit? {
        let approximateRadius = max(7, min(width, height) / 22)
        let centerX = Int(point.x * Double(width))
        let centerY = Int(point.y * Double(height))
        let searchRadius = Int(max(6, maxCenterDistancePixels ?? Double(approximateRadius) * 2.2))
        let expectedRadius = expectedRadiusPixels ?? Double(approximateRadius)
        let radiusCandidates: [Double]
        if let expectedRadiusPixels {
            radiusCandidates = [
                expectedRadiusPixels * 0.72,
                expectedRadiusPixels * 0.88,
                expectedRadiusPixels,
                expectedRadiusPixels * 1.16,
                expectedRadiusPixels * 1.32
            ]
        } else {
            let frameBase = Double(min(width, height))
            radiusCandidates = [
                expectedRadius * 0.70,
                expectedRadius,
                expectedRadius * 1.35,
                frameBase * 0.075,
                frameBase * 0.10,
                frameBase * 0.13
            ]
        }
        let radii = Array(Set(radiusCandidates.map { max(5, Int($0.rounded())) })).sorted()

        var bestScore = 0.0
        var bestFit: PlateFit?

        for y in stride(from: max(0, centerY - searchRadius), through: min(height - 1, centerY + searchRadius), by: 2) {
            for x in stride(from: max(0, centerX - searchRadius), through: min(width - 1, centerX + searchRadius), by: 2) {
                for radius in radii {
                    let contrast = circularContrastScore(centerX: x, centerY: y, radius: radius)
                    let circularity = radialEdgeConsistency(centerX: x, centerY: y, radius: radius)
                    let sleeve = centerSleeveScore(centerX: x, centerY: y, radius: radius)
                    let radiusPenalty = expectedRadiusPixels.map { max(0, 1 - abs(Double(radius) - $0) / max($0, 1)) } ?? 1
                    let dx = Double(x - centerX)
                    let dy = Double(y - centerY)
                    let distance = (dx * dx + dy * dy).squareRoot()
                    let proximity = max(0, 1 - distance / max(Double(searchRadius), 1))
                    let score = contrast * 0.38 + circularity * 0.28 + sleeve * 0.20 + radiusPenalty * 0.06 + proximity * 0.08
                    if score > bestScore {
                        bestScore = score
                        bestFit = PlateFit(
                            center: NormalizedPoint(x: Double(x) / Double(width), y: Double(y) / Double(height)),
                            radiusPixels: Double(radius),
                            circularity: circularity,
                            areaPixels: Double.pi * Double(radius * radius),
                            confidence: max(0.05, min(0.96, score))
                        )
                    }
                }
            }
        }

        guard let bestFit,
              bestScore > 0.18,
              bestFit.circularity > 0.18,
              bestFit.areaPixels > 80 else {
            return nil
        }
        return bestFit
    }

    private func circularContrastScore(centerX: Int, centerY: Int, radius: Int) -> Double {
        guard centerX - radius * 2 >= 0, centerY - radius * 2 >= 0,
              centerX + radius * 2 < width, centerY + radius * 2 < height else {
            return 0
        }

        var innerTotal = 0
        var innerCount = 0
        var ringTotal = 0
        var ringCount = 0
        let innerSquared = radius * radius
        let outerSquared = radius * radius * 4

        for y in (centerY - radius * 2)...(centerY + radius * 2) {
            let offset = y * width
            for x in (centerX - radius * 2)...(centerX + radius * 2) {
                let dx = x - centerX
                let dy = y - centerY
                let distance = dx * dx + dy * dy
                if distance <= innerSquared {
                    innerTotal += Int(pixels[offset + x])
                    innerCount += 1
                } else if distance <= outerSquared {
                    ringTotal += Int(pixels[offset + x])
                    ringCount += 1
                }
            }
        }

        guard innerCount > 0, ringCount > 0 else { return 0 }
        let inner = Double(innerTotal) / Double(innerCount)
        let ring = Double(ringTotal) / Double(ringCount)
        let contrast = abs(inner - ring) / 255
        let darknessBias = max(0, 1 - inner / 255)
        return contrast * 0.75 + darknessBias * 0.25
    }

    private func centerSleeveScore(centerX: Int, centerY: Int, radius: Int) -> Double {
        let centerRadius = max(2, Int((Double(radius) * 0.22).rounded()))
        let sleeveOuterRadius = max(centerRadius + 2, Int((Double(radius) * 0.48).rounded()))
        guard centerX - sleeveOuterRadius >= 0, centerY - sleeveOuterRadius >= 0,
              centerX + sleeveOuterRadius < width, centerY + sleeveOuterRadius < height else {
            return 0
        }

        var centerTotal = 0
        var centerCount = 0
        var plateTotal = 0
        var plateCount = 0
        let centerSquared = centerRadius * centerRadius
        let outerSquared = sleeveOuterRadius * sleeveOuterRadius

        for y in (centerY - sleeveOuterRadius)...(centerY + sleeveOuterRadius) {
            let offset = y * width
            for x in (centerX - sleeveOuterRadius)...(centerX + sleeveOuterRadius) {
                let dx = x - centerX
                let dy = y - centerY
                let distance = dx * dx + dy * dy
                if distance <= centerSquared {
                    centerTotal += Int(pixels[offset + x])
                    centerCount += 1
                } else if distance <= outerSquared {
                    plateTotal += Int(pixels[offset + x])
                    plateCount += 1
                }
            }
        }

        guard centerCount > 0, plateCount > 0 else { return 0 }
        let center = Double(centerTotal) / Double(centerCount)
        let plate = Double(plateTotal) / Double(plateCount)
        let contrast = min(1, abs(center - plate) / 95)
        let sleeveBias = max(0, 1 - min(center, plate) / max(max(center, plate), 1))
        return min(1, contrast * 0.78 + sleeveBias * 0.22)
    }

    private func radialEdgeConsistency(centerX: Int, centerY: Int, radius: Int) -> Double {
        guard centerX - radius * 2 >= 0, centerY - radius * 2 >= 0,
              centerX + radius * 2 < width, centerY + radius * 2 < height else {
            return 0
        }

        let sampleCount = 32
        var scores: [Double] = []
        scores.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let angle = Double(index) / Double(sampleCount) * .pi * 2
            let dx = cos(angle)
            let dy = sin(angle)
            let innerX = centerX + Int((Double(radius) * 0.62 * dx).rounded())
            let innerY = centerY + Int((Double(radius) * 0.62 * dy).rounded())
            let ringX = centerX + Int((Double(radius) * dx).rounded())
            let ringY = centerY + Int((Double(radius) * dy).rounded())
            let outerX = centerX + Int((Double(radius) * 1.36 * dx).rounded())
            let outerY = centerY + Int((Double(radius) * 1.36 * dy).rounded())
            let inner = Double(pixels[innerY * width + innerX])
            let ring = Double(pixels[ringY * width + ringX])
            let outer = Double(pixels[outerY * width + outerX])
            scores.append(min(1, abs(ring - inner) / 90) * 0.55 + min(1, abs(ring - outer) / 90) * 0.45)
        }

        let mean = scores.reduce(0, +) / Double(scores.count)
        let coverage = Double(scores.filter { $0 > 0.12 }.count) / Double(sampleCount)
        return min(1, mean * 0.55 + coverage * 0.45)
    }
}

struct PlateFit {
    let center: NormalizedPoint
    let radiusPixels: Double
    let circularity: Double
    let areaPixels: Double
    let confidence: Double
}
