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

    func extractFrames(from url: URL, maxFrames: Int = 120) async throws -> [VideoFrame] {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { return [] }

            let fps = try await Self.videoFrameRate(for: asset)
            let naturalFrameCount = max(1, Int(duration * max(fps, 1)))
            let frameCount = min(maxFrames, naturalFrameCount)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

            return (0..<frameCount).compactMap { index in
                let progress = Double(index) / Double(max(frameCount - 1, 1))
                let seconds = progress * duration
                let time = CMTime(seconds: seconds, preferredTimescale: 600)

                do {
                    var actualTime = CMTime.zero
                    let image = try generator.copyCGImage(at: time, actualTime: &actualTime)
                    return VideoFrame(
                        timestamp: actualTime.seconds.isFinite ? actualTime.seconds : seconds,
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
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 900, height: 900)

            var actualTime = CMTime.zero
            let image = try generator.copyCGImage(at: .zero, actualTime: &actualTime)
            return VideoFrame(
                timestamp: actualTime.seconds.isFinite ? actualTime.seconds : 0,
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

    func patch(center: NormalizedPoint, radius: Int) -> [UInt8]? {
        let centerX = Int(center.x * Double(width))
        let centerY = Int(center.y * Double(height))
        guard centerX - radius >= 0, centerY - radius >= 0, centerX + radius < width, centerY + radius < height else {
            return nil
        }

        var patch: [UInt8] = []
        patch.reserveCapacity((radius * 2 + 1) * (radius * 2 + 1))
        for y in (centerY - radius)...(centerY + radius) {
            let offset = y * width
            for x in (centerX - radius)...(centerX + radius) {
                patch.append(pixels[offset + x])
            }
        }
        return patch
    }

    func bestMatch(
        template: [UInt8],
        radius: Int,
        around previous: NormalizedPoint,
        searchRadius: Int
    ) -> (point: NormalizedPoint, confidence: Double)? {
        guard template.count == (radius * 2 + 1) * (radius * 2 + 1) else { return nil }

        let previousX = Int(previous.x * Double(width))
        let previousY = Int(previous.y * Double(height))
        let minX = max(radius, previousX - searchRadius)
        let maxX = min(width - radius - 1, previousX + searchRadius)
        let minY = max(radius, previousY - searchRadius)
        let maxY = min(height - radius - 1, previousY + searchRadius)
        guard minX <= maxX, minY <= maxY else { return nil }

        var bestCorrelation = -Double.greatestFiniteMagnitude
        var bestX = previousX
        var bestY = previousY

        for y in stride(from: minY, through: maxY, by: 2) {
            for x in stride(from: minX, through: maxX, by: 2) {
                let correlation = normalizedCrossCorrelation(template: template, centerX: x, centerY: y, radius: radius)
                if correlation > bestCorrelation {
                    bestCorrelation = correlation
                    bestX = x
                    bestY = y
                }
            }
        }

        let confidence = max(0.05, min(0.98, (bestCorrelation + 1) / 2))
        return (
            NormalizedPoint(x: Double(bestX) / Double(width), y: Double(bestY) / Double(height)),
            confidence
        )
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
        let approximateRadius = max(7, min(width, height) / 22)
        let centerX = Int(point.x * Double(width))
        let centerY = Int(point.y * Double(height))
        let searchRadius = max(6, approximateRadius / 2)

        var bestScore = 0.0
        var bestPoint: NormalizedPoint?

        for y in stride(from: centerY - searchRadius, through: centerY + searchRadius, by: 2) {
            for x in stride(from: centerX - searchRadius, through: centerX + searchRadius, by: 2) {
                let score = circularContrastScore(centerX: x, centerY: y, radius: approximateRadius)
                if score > bestScore {
                    bestScore = score
                    bestPoint = NormalizedPoint(x: Double(x) / Double(width), y: Double(y) / Double(height))
                }
            }
        }

        guard bestScore > 0.1 else { return nil }
        return bestPoint
    }

    private func normalizedCrossCorrelation(template: [UInt8], centerX: Int, centerY: Int, radius: Int) -> Double {
        let count = max(template.count, 1)
        let templateMean = template.reduce(0) { $0 + Double($1) } / Double(count)
        var patchMean = 0.0
        var index = 0
        for y in (centerY - radius)...(centerY + radius) {
            let offset = y * width
            for x in (centerX - radius)...(centerX + radius) {
                patchMean += Double(pixels[offset + x])
                index += 1
            }
        }
        patchMean /= Double(count)

        index = 0
        var numerator = 0.0
        var templateVariance = 0.0
        var patchVariance = 0.0
        for y in (centerY - radius)...(centerY + radius) {
            let offset = y * width
            for x in (centerX - radius)...(centerX + radius) {
                let templateDelta = Double(template[index]) - templateMean
                let patchDelta = Double(pixels[offset + x]) - patchMean
                numerator += templateDelta * patchDelta
                templateVariance += templateDelta * templateDelta
                patchVariance += patchDelta * patchDelta
                index += 1
            }
        }

        let denominator = sqrt(templateVariance * patchVariance)
        guard denominator > 0 else { return -1 }
        return numerator / denominator
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
}
