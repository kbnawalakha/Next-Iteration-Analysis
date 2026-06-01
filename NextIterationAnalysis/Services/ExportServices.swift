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

    func export(session: LiftSession) async throws -> URL {
        guard let sourceURL = session.videoURL else { throw ExportError.missingVideo }
        guard let analysis = session.analysis else { throw ExportError.missingAnalysis }

        let asset = AVURLAsset(url: sourceURL)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw ExportError.missingVideoTrack
        }
        let fps = await VideoFrameExtractor().nominalFrameRate(for: sourceURL)

        let overlayRenderer = AnnotatedVideoOverlayRenderer(path: analysis.trackedPath, reps: session.reps)
        let videoComposition = AVMutableVideoComposition(asset: asset) { request in
            let source = request.sourceImage.clampedToExtent()
            let extent = source.extent
            let overlay = overlayRenderer.overlayImage(size: extent.size, extent: extent)
            request.finish(with: overlay.composited(over: source).cropped(to: extent), context: nil)
        }
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, Int(round(fps)))))

        let destination = try storage.makeExportURL(fileName: "\(session.liftType.rawValue)-annotated-\(session.id.uuidString.prefix(8)).mp4")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1280x720
        ) else {
            throw ExportError.exportFailed
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition

        let exportBox = ExportSessionBox(exportSession)
        try await withCheckedThrowingContinuation { continuation in
            exportBox.session.exportAsynchronously {
                switch exportBox.session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportBox.session.error ?? ExportError.exportFailed)
                default:
                    continuation.resume(throwing: ExportError.exportFailed)
                }
            }
        }

        return destination
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

final class AnnotatedVideoOverlayRenderer: @unchecked Sendable {
    private let path: [TrackedPoint]
    private let reps: Int
    private let metricsCalculator = LiftMetricsCalculator()
    private let lock = NSLock()
    private var overlayCache: [String: CIImage] = [:]

    init(path: [TrackedPoint], reps: Int) {
        self.path = path
        self.reps = reps
    }

    func overlayImage(size: CGSize, extent: CGRect) -> CIImage {
        let cacheKey = "\(Int(size.width))x\(Int(size.height))-\(path.count)-\(reps)"
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
            drawVelocityPath(size: size, path: path, reps: reps)
            drawWatermark(size: size)
        }

        let overlay = CIImage(image: image)?
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: size.height))
            ?? CIImage.empty()

        lock.lock()
        overlayCache[cacheKey] = overlay
        lock.unlock()
        return overlay.transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
    }

    private func drawVelocityPath(size: CGSize, path: [TrackedPoint], reps: Int) {
        let repSegments = metricsCalculator.repSegments(for: path, reps: reps)
        if repSegments.isEmpty {
            drawVelocitySegments(metricsCalculator.velocitySegments(for: path), opacity: 1, size: size)
        } else {
            for rep in repSegments {
                drawVelocitySegments(metricsCalculator.velocitySegments(for: rep.points), opacity: rep.opacity, size: size)
                let bottom = cgPoint(rep.bottom, renderSize: size)
                let marker = UIBezierPath(ovalIn: CGRect(x: bottom.x - 9, y: bottom.y - 9, width: 18, height: 18))
                UIColor.white.withAlphaComponent(rep.opacity).setStroke()
                marker.lineWidth = 3
                marker.stroke()
            }
        }

        guard let current = path.last else { return }
        let point = cgPoint(current, renderSize: size)
        let marker = UIBezierPath(ovalIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
        UIColor.white.setFill()
        UIColor.systemRed.setStroke()
        marker.lineWidth = 4
        marker.fill()
        marker.stroke()
    }

    private func drawVelocitySegments(_ segments: [VelocitySegment], opacity: Double, size: CGSize) {
        for segment in segments {
            let line = UIBezierPath()
            line.move(to: cgPoint(segment.from, renderSize: size))
            line.addLine(to: cgPoint(segment.to, renderSize: size))
            line.lineWidth = max(opacity >= 1 ? 6 : 4, size.width * 0.006)
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            color(for: segment.speed).withAlphaComponent(opacity).setStroke()
            line.stroke()
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

    private func color(for normalizedSpeed: Double) -> UIColor {
        switch normalizedSpeed {
        case 0..<0.34: return .systemRed
        case 0.34..<0.67: return .systemYellow
        default: return .systemGreen
        }
    }

}

enum ExportError: LocalizedError {
    case missingAnalysis
    case missingVideo
    case missingVideoTrack
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingAnalysis: return "Run an analysis before exporting."
        case .missingVideo: return "The source video is unavailable."
        case .missingVideoTrack: return "The video track could not be read."
        case .exportFailed: return "The annotated video export failed."
        }
    }
}
