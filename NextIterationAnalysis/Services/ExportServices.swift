import AVFoundation
import CoreImage
import Foundation
import UIKit

final class CSVExportService {
    private let storage = LocalStorageService()

    func export(session: LiftSession) throws -> URL {
        guard let analysis = session.analysis else { throw ExportError.missingAnalysis }
        var rows = ["frameIndex,timestamp,centerX,centerY,confidence"]
        rows.append(contentsOf: analysis.trackedPath.map {
            "\($0.frameIndex),\($0.timestamp),\($0.x),\($0.y),\($0.confidence)"
        })
        let fileName = "\(session.liftType.rawValue)-\(session.id.uuidString.prefix(8))-path.csv"
        let url = try storage.makeExportURL(fileName: fileName)
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

final class AnnotatedVideoExportService {
    private let storage = LocalStorageService()

    func export(session: LiftSession, colorStyle: BarPathColorStyle = .velocity) async throws -> URL {
        guard let sourceURL = session.videoURL else { throw ExportError.missingVideo }
        guard let analysis = session.analysis else { throw ExportError.missingAnalysis }

        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.missingVideoTrack
        }
        let fps = await VideoFrameExtractor().nominalFrameRate(for: sourceURL)

        // Render at the video's true (orientation-applied) size so the export
        // matches the source and AVFoundation doesn't reject a mismatched size,
        // which was causing the annotated export to fail.
        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? CGSize(width: 1280, height: 720)
        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let orientedSize = naturalSize.applying(preferredTransform)
        let renderSize = Self.cappedRenderSize(
            CGSize(width: max(16, abs(orientedSize.width)), height: max(16, abs(orientedSize.height)))
        )

        let overlayRenderer = AnnotatedVideoOverlayRenderer(path: analysis.trackedPath, reps: session.reps, colorStyle: colorStyle)
        let videoComposition = AVMutableVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            let extent = source.extent
            guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else {
                request.finish(with: source, context: nil)
                return
            }
            let overlay = overlayRenderer.overlayImage(
                size: extent.size,
                extent: extent,
                currentTime: nil
            )
            request.finish(with: overlay.composited(over: source).cropped(to: extent), context: nil)
        }
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, Int(round(fps)))))

        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset: String
        if compatiblePresets.contains(AVAssetExportPresetHighestQuality) {
            preset = AVAssetExportPresetHighestQuality
        } else if compatiblePresets.contains(AVAssetExportPreset1280x720) {
            preset = AVAssetExportPreset1280x720
        } else if compatiblePresets.contains(AVAssetExportPresetMediumQuality) {
            preset = AVAssetExportPresetMediumQuality
        } else {
            preset = compatiblePresets.first ?? AVAssetExportPresetHighestQuality
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ExportError.exportFailed
        }

        let outputType: AVFileType = exportSession.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let fileExtension = outputType == .mp4 ? "mp4" : "mov"
        let destination = try storage.makeExportURL(fileName: "\(session.liftType.rawValue)-annotated-\(session.id.uuidString.prefix(8)).\(fileExtension)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = outputType
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        let exportBox = ExportSessionBox(exportSession)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await exportBox.export()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 90_000_000_000)
                exportBox.session.cancelExport()
                throw ExportError.exportTimedOut
            }
            try await group.next()
            group.cancelAll()
        }

        return destination
    }

    private static func cappedRenderSize(_ size: CGSize) -> CGSize {
        let maxDimension: CGFloat = 1280
        let scale = min(1, maxDimension / max(size.width, size.height, 1))
        return CGSize(
            width: max(16, (size.width * scale).rounded()),
            height: max(16, (size.height * scale).rounded())
        )
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }

    func export() async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch self.session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: self.session.error ?? ExportError.exportFailed)
                default:
                    continuation.resume(throwing: ExportError.exportFailed)
                }
            }
        }
    }
}

final class AnnotatedVideoOverlayRenderer: @unchecked Sendable {
    private let path: [TrackedPoint]
    private let reps: Int
    private let colorStyle: BarPathColorStyle
    private let metricsCalculator = LiftMetricsCalculator()
    private let lock = NSLock()
    private var overlayCache: [String: CIImage] = [:]

    init(path: [TrackedPoint], reps: Int, colorStyle: BarPathColorStyle = .velocity) {
        self.path = path
        self.reps = reps
        self.colorStyle = colorStyle
    }

    func overlayImage(size: CGSize, extent: CGRect, currentTime: Double? = nil) -> CIImage {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return CIImage.empty()
        }
        let visiblePath = visiblePath(through: currentTime)
        let cacheFrame = visiblePath.last?.frameIndex ?? -1
        let cacheTime = Int(((currentTime ?? -1) * 1000).rounded())
        let cacheKey = "\(Int(size.width))x\(Int(size.height))-\(visiblePath.count)-\(cacheFrame)-\(cacheTime)-\(reps)-\(colorStyle.rawValue)"
        lock.lock()
        if let cached = overlayCache[cacheKey] {
            lock.unlock()
            return cached.transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
        }
        lock.unlock()

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            drawVelocityPath(size: size, visiblePath: visiblePath, currentTime: currentTime)
            drawWatermark(size: size)
        }

        let overlay = CIImage(image: image)?
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: size.height))
            ?? CIImage.empty()

        lock.lock()
        overlayCache[cacheKey] = overlay
        if overlayCache.count > 90 {
            overlayCache.removeAll(keepingCapacity: true)
        }
        lock.unlock()
        return overlay.transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
    }

    private func visiblePath(through currentTime: Double?) -> [TrackedPoint] {
        guard let currentTime else { return path }
        return frameAlignedPath(from: path, at: currentTime)
    }

    private func drawVelocityPath(size: CGSize, visiblePath: [TrackedPoint], currentTime: Double?) {
        let repSegments = visibleSegments(through: currentTime)
        if repSegments.isEmpty {
            drawVelocitySegments(metricsCalculator.velocitySegments(for: visiblePath), opacity: 1, size: size)
        } else {
            for rep in repSegments {
                drawVelocitySegments(metricsCalculator.velocitySegments(for: rep.points), opacity: rep.opacity, size: size)
                let bottom = cgPoint(rep.bottom, renderSize: size)
                let markerSize = max(8.0, size.width * 0.022)
                let marker = UIBezierPath(ovalIn: CGRect(x: bottom.x - markerSize / 2, y: bottom.y - markerSize / 2, width: markerSize, height: markerSize))
                UIColor.white.withAlphaComponent(rep.opacity * 0.9).setStroke()
                marker.lineWidth = 1.5
                marker.stroke()
            }
        }

        guard let current = visiblePath.last else { return }
        let point = cgPoint(current, renderSize: size)
        let dotSize = max(8.0, size.width * 0.02)
        let marker = UIBezierPath(ovalIn: CGRect(x: point.x - dotSize / 2, y: point.y - dotSize / 2, width: dotSize, height: dotSize))
        UIColor.white.setFill()
        marker.fill()
    }

    private func visibleSegments(through currentTime: Double?) -> [RepPathSegment] {
        let fullSegments = metricsCalculator.repSegments(for: path, reps: reps)
        guard let currentTime else { return fullSegments }
        return fullSegments.compactMap { segment in
            let visiblePoints = visiblePath(from: segment.points, through: currentTime)
            guard visiblePoints.count > 1, visiblePoints.first?.timestamp ?? 0 <= currentTime else { return nil }
            let active = (visiblePoints.last?.timestamp ?? 0) < (segment.points.last?.timestamp ?? 0)
            return RepPathSegment(
                index: segment.index,
                points: visiblePoints,
                bottom: visiblePoints.max(by: { $0.y < $1.y }) ?? segment.bottom,
                opacity: active ? 1.0 : 0.28
            )
        }
    }

    private func visiblePath(from points: [TrackedPoint], through currentTime: Double) -> [TrackedPoint] {
        frameAlignedPath(from: points, at: currentTime)
    }

    private func drawVelocitySegments(_ segments: [VelocitySegment], opacity: Double, size: CGSize) {
        for segment in segments {
            let line = UIBezierPath()
            line.move(to: cgPoint(segment.from, renderSize: size))
            line.addLine(to: cgPoint(segment.to, renderSize: size))
            line.lineWidth = max(opacity >= 1 ? 7 : 3.5, size.width * (opacity >= 1 ? 0.007 : 0.004))
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            let strokeColor = Self.pathColor(for: segment.speed, style: colorStyle)
            strokeColor.withAlphaComponent(opacity).setStroke()
            line.stroke()
        }
    }

    /// Bar path color for the exported annotated video. Mirrors
    /// `VelocityBarPathOverlay.pathColor(for:style:)` so the in-app overlay and
    /// the exported video match. `.velocity` is vivid green while moving,
    /// shifting toward yellow/orange/red through slow sticking points;
    /// `.solidGreen` always returns the same green.
    static func pathColor(for normalizedSpeed: Double, style: BarPathColorStyle) -> UIColor {
        let green = UIColor(hue: CGFloat(1.0 / 3.0), saturation: 0.95, brightness: 0.95, alpha: 1)
        switch style {
        case .solidGreen:
            return green
        case .velocity:
            let speed = min(1, max(0, normalizedSpeed))
            let eased = pow(speed, 0.6)
            // UIColor hue space: 0.0 = red, ~0.166 = yellow, 0.333 = green.
            let hue = eased * (1.0 / 3.0)
            return UIColor(hue: CGFloat(hue), saturation: 0.95, brightness: 0.95, alpha: 1)
        }
    }

    private func drawWatermark(size: CGSize) {
        let rect = CGRect(x: 16, y: 16, width: min(360, size.width - 32), height: 44)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        UIColor.black.withAlphaComponent(0.42).setFill()
        path.fill()

        let text = "Next Iteration Analysis"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: max(18, size.width * 0.028)),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func cgPoint(_ point: TrackedPoint, renderSize: CGSize) -> CGPoint {
        CGPoint(x: point.x * renderSize.width, y: point.y * renderSize.height)
    }

    private func frameAlignedPath(
        from points: [TrackedPoint],
        at playbackTime: Double
    ) -> [TrackedPoint] {
        guard let first = points.first else { return [] }
        guard points.count > 1 else { return points }

        let timelineTime = playbackTime
        if timelineTime <= first.timestamp {
            return [first]
        }

        guard let nextIndex = points.firstIndex(where: { $0.timestamp >= timelineTime }) else {
            return points
        }

        if nextIndex == 0 {
            return [first]
        }

        let previous = points[nextIndex - 1]
        let next = points[nextIndex]
        let duration = max(next.timestamp - previous.timestamp, 0.0001)
        let progress = min(1, max(0, (timelineTime - previous.timestamp) / duration))
        let interpolated = TrackedPoint(
            id: UUID(),
            timestamp: timelineTime,
            frameIndex: next.frameIndex,
            x: previous.x + (next.x - previous.x) * progress,
            y: previous.y + (next.y - previous.y) * progress,
            confidence: previous.confidence + (next.confidence - previous.confidence) * progress
        )

        var visible = Array(points.prefix(nextIndex))
        visible.append(interpolated)
        return visible
    }

}

enum ExportError: LocalizedError {
    case missingAnalysis
    case missingVideo
    case missingVideoTrack
    case exportFailed
    case exportTimedOut

    var errorDescription: String? {
        switch self {
        case .missingAnalysis: return "Run an analysis before exporting."
        case .missingVideo: return "The source video is unavailable."
        case .missingVideoTrack: return "The video track could not be read."
        case .exportFailed: return "The annotated video export failed."
        case .exportTimedOut: return "The annotated video export took too long and was cancelled. Try trimming the clip shorter, then export again."
        }
    }
}
