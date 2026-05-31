import AVFoundation
import Foundation

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

    func export(session: LiftSession) async throws -> URL {
        guard let sourceURL = session.videoURL else { throw ExportError.missingVideo }
        guard session.analysis != nil else { throw ExportError.missingAnalysis }

        // The MVP export preserves the original video as a shareable file. A production pass can
        // replace this with AVVideoCompositionCoreAnimationTool path rendering.
        let destination = try storage.makeExportURL(fileName: "\(session.liftType.rawValue)-annotated-\(session.id.uuidString.prefix(8)).mov")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}

enum ExportError: LocalizedError {
    case missingAnalysis
    case missingVideo

    var errorDescription: String? {
        switch self {
        case .missingAnalysis: return "Run an analysis before exporting."
        case .missingVideo: return "The source video is unavailable."
        }
    }
}
