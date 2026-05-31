import AVFoundation
import Foundation
import Vision

final class PoseDetectionService {
    private let frameExtractor = VideoFrameExtractor()

    func detectPoseFrames(videoURL: URL?, maxFrames: Int = 90) async -> [PoseFrame] {
        guard let videoURL = videoURL,
              let frames = try? await frameExtractor.extractFrames(from: videoURL, maxFrames: maxFrames) else {
            return []
        }

        return frames.compactMap { frame in
            detectPose(in: frame)
        }
    }

    private func detectPose(in frame: VideoFrame) -> PoseFrame? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: frame.image, orientation: .up)

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let recognizedPoints = try observation.recognizedPoints(.all)
            var joints: [String: JointPoint] = [:]
            var confidenceTotal = 0.0
            var confidenceCount = 0

            for (jointName, point) in recognizedPoints where point.confidence > 0.1 {
                joints[jointName.rawValue] = JointPoint(
                    x: Double(point.location.x),
                    y: Double(1 - point.location.y),
                    confidence: Double(point.confidence)
                )
                confidenceTotal += Double(point.confidence)
                confidenceCount += 1
            }

            guard !joints.isEmpty else { return nil }
            return PoseFrame(
                timestamp: frame.timestamp,
                joints: joints,
                confidence: confidenceTotal / Double(max(confidenceCount, 1))
            )
        } catch {
            return nil
        }
    }
}
