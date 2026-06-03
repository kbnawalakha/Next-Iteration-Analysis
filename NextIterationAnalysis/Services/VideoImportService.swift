import AVFoundation
import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let didAccess = received.file.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    received.file.stopAccessingSecurityScopedResource()
                }
            }

            let pathExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(pathExtension)")
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

final class VideoImportService {
    private let storage = LocalStorageService()

    func importVideo(from item: PhotosPickerItem) async throws -> ImportedLiftVideo {
        guard let pickedMovie = try await item.loadTransferable(type: PickedMovie.self) else {
            throw VideoImportError.unreadableVideo
        }

        return try await importVideo(fromLocalURL: pickedMovie.url)
    }

    func importVideo(fromLocalURL sourceURL: URL) async throws -> ImportedLiftVideo {
        try await Task.detached(priority: .userInitiated) {
            let destination = try self.storage.makeImportURL(for: sourceURL)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)

            let metadata = try await self.metadata(for: destination)
            let thumbnailURL = try? await self.generateThumbnail(for: destination)

            return ImportedLiftVideo(videoURL: destination, thumbnailURL: thumbnailURL, metadata: metadata)
        }.value
    }

    func reducedSizeVideo(from importedVideo: ImportedLiftVideo, quality: VideoCompressionQuality = .medium) async throws -> ImportedLiftVideo {
        let sourceURL = importedVideo.videoURL
        let asset = AVURLAsset(url: sourceURL)
        let destination = try storage.makeImportURL(for: URL(fileURLWithPath: "compressed.mp4"))
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: quality.presetName) else {
            throw VideoImportError.compressionFailed
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? VideoImportError.compressionFailed)
                default:
                    continuation.resume(throwing: VideoImportError.compressionFailed)
                }
            }
        }

        let metadata = try await metadata(for: destination)
        let thumbnailURL = try? await generateThumbnail(for: destination)
        return ImportedLiftVideo(videoURL: destination, thumbnailURL: thumbnailURL, metadata: metadata)
    }

    func trimmedVideo(from importedVideo: ImportedLiftVideo, timeRange: ClosedRange<Double>) async throws -> ImportedLiftVideo {
        let sourceURL = importedVideo.videoURL
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration).seconds
        let start = max(0, min(timeRange.lowerBound, duration))
        let end = max(start + 0.1, min(timeRange.upperBound, duration))

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoImportError.trimFailed
        }

        let outputType: AVFileType = exportSession.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let fileExtension = outputType == .mp4 ? "mp4" : "mov"
        let destination = try storage.makeImportURL(for: URL(fileURLWithPath: "trimmed.\(fileExtension)"))
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = outputType
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )
        exportSession.shouldOptimizeForNetworkUse = true

        let exportBox = VideoExportSessionBox(exportSession)
        try await exportBox.export(error: VideoImportError.trimFailed)

        let metadata = try await metadata(for: destination)
        let thumbnailURL = try? await generateThumbnail(for: destination)
        return ImportedLiftVideo(videoURL: destination, thumbnailURL: thumbnailURL, metadata: metadata)
    }

    private func metadata(for url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw VideoImportError.missingVideoTrack
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let displaySize = Self.transformedSize(naturalSize, transform: preferredTransform)
        let fps = try await track.load(.nominalFrameRate)
        let resolution = "\(Int(displaySize.width)) x \(Int(displaySize.height))"

        return VideoMetadata(
            duration: duration.isFinite ? duration : 0,
            fps: fps.isFinite ? Double(fps) : 0,
            resolution: resolution,
            width: Double(displaySize.width),
            height: Double(displaySize.height),
            creationDate: nil
        )
    }

    private func generateThumbnail(for url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)
        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        let data = try Self.jpegData(from: cgImage, maxDimension: 900)
        let destination = try storage.makeExportURL(fileName: "\(UUID().uuidString)-thumbnail.jpg")
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    private static func jpegData(from image: CGImage, maxDimension: CGFloat) throws -> Data {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxDimension / max(width, height, 1))
        let size = CGSize(width: max(1, width * scale), height: max(1, height * scale))

        let renderer = UIGraphicsImageRenderer(size: size)
        let thumbnail = renderer.image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }

        guard let data = thumbnail.jpegData(compressionQuality: 0.82), !data.isEmpty else {
            throw VideoImportError.thumbnailGenerationFailed
        }
        return data
    }

    private static func transformedSize(_ size: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }
}

enum VideoImportError: LocalizedError {
    case unreadableVideo
    case missingVideoTrack
    case thumbnailGenerationFailed
    case compressionFailed
    case trimFailed

    var errorDescription: String? {
        switch self {
        case .unreadableVideo:
            return "The selected video could not be imported."
        case .missingVideoTrack:
            return "The selected file does not contain a readable video track."
        case .thumbnailGenerationFailed:
            return "The selected video thumbnail could not be generated."
        case .compressionFailed:
            return "The selected video could not be reduced."
        case .trimFailed:
            return "The selected video segment could not be trimmed."
        }
    }
}

private final class VideoExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }

    func export(error fallbackError: Error) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch self.session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: self.session.error ?? fallbackError)
                default:
                    continuation.resume(throwing: fallbackError)
                }
            }
        }
    }
}

enum VideoCompressionQuality: String, CaseIterable, Identifiable {
    case medium
    case small

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .medium: return "Medium"
        case .small: return "Small"
        }
    }

    var presetName: String {
        switch self {
        case .medium: return AVAssetExportPreset1280x720
        case .small: return AVAssetExportPreset960x540
        }
    }
}
