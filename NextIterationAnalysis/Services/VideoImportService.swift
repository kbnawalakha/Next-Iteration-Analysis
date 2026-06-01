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

    var errorDescription: String? {
        switch self {
        case .unreadableVideo:
            return "The selected video could not be imported."
        case .missingVideoTrack:
            return "The selected file does not contain a readable video track."
        case .thumbnailGenerationFailed:
            return "The selected video thumbnail could not be generated."
        }
    }
}
