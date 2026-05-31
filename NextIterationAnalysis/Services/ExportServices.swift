import AVFoundation
import Foundation
import QuartzCore
import UIKit

final class CSVExportService {
    private let storage = LocalStorageService()

    func export(session: LiftSession) throws -> URL {
        guard let analysis = session.analysis else { throw ExportError.missingAnalysis }
        var rows = ["frameIndex,timestamp,x,y,confidence"]
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
    private let metricsCalculator = LiftMetricsCalculator()

    func export(session: LiftSession) async throws -> URL {
        guard let sourceURL = session.videoURL else { throw ExportError.missingVideo }
        guard let analysis = session.analysis else { throw ExportError.missingAnalysis }

        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw ExportError.missingVideoTrack }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.exportFailed
        }

        let duration = try await asset.load(.duration)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let renderSize = transformedSize(naturalSize, transform: preferredTransform)
        compositionVideoTrack.preferredTransform = preferredTransform

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.animationTool = animationTool(renderSize: renderSize, path: analysis.trackedPath)

        let destination = try storage.makeExportURL(fileName: "\(session.liftType.rawValue)-annotated-\(session.id.uuidString.prefix(8)).mp4")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition

        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? ExportError.exportFailed)
                default:
                    continuation.resume(throwing: ExportError.exportFailed)
                }
            }
        }

        return destination
    }

    private func animationTool(renderSize: CGSize, path: [TrackedPoint]) -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        let overlayLayer = CALayer()

        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = parentLayer.bounds
        overlayLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        addVelocityPath(to: overlayLayer, renderSize: renderSize, path: path)
        addWatermark(to: overlayLayer, renderSize: renderSize)

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private func addVelocityPath(to layer: CALayer, renderSize: CGSize, path: [TrackedPoint]) {
        let segments = metricsCalculator.velocitySegments(for: path)
        for segment in segments {
            let line = UIBezierPath()
            line.move(to: cgPoint(segment.from, renderSize: renderSize))
            line.addLine(to: cgPoint(segment.to, renderSize: renderSize))

            let shape = CAShapeLayer()
            shape.path = line.cgPath
            shape.strokeColor = color(for: segment.speed).cgColor
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = max(5, renderSize.width * 0.006)
            shape.lineCap = .round
            shape.lineJoin = .round
            layer.addSublayer(shape)
        }

        guard let current = path.last else { return }
        let marker = CAShapeLayer()
        let point = cgPoint(current, renderSize: renderSize)
        marker.path = UIBezierPath(
            ovalIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
        ).cgPath
        marker.fillColor = UIColor.white.cgColor
        marker.strokeColor = UIColor.systemRed.cgColor
        marker.lineWidth = 4
        layer.addSublayer(marker)
    }

    private func addWatermark(to layer: CALayer, renderSize: CGSize) {
        let text = CATextLayer()
        text.string = "Next Iteration Analysis"
        text.fontSize = max(18, renderSize.width * 0.028)
        text.foregroundColor = UIColor.white.cgColor
        text.backgroundColor = UIColor.black.withAlphaComponent(0.42).cgColor
        text.alignmentMode = .center
        text.contentsScale = UIScreen.main.scale
        text.cornerRadius = 8
        text.frame = CGRect(x: 16, y: 16, width: min(360, renderSize.width - 32), height: 44)
        layer.addSublayer(text)
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

    private func transformedSize(_ size: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
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
