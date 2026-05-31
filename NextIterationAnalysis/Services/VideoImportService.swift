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
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(received.file.pathExtension)")
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

        let destination = try storage.makeImportURL(for: pickedMovie.url)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: pickedMovie.url, to: destination)

        let metadata = try await metadata(for: destination)
        let thumbnailURL = try? await generateThumbnail(for: destination)

        return ImportedLiftVideo(videoURL: destination, thumbnailURL: thumbnailURL, metadata: metadata)
    }

    private func metadata(for url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = tracks.first
        let naturalSize = try await track?.load(.naturalSize) ?? .zero
        let fps = try await track?.load(.nominalFrameRate) ?? 0
        let resolution = "\(Int(abs(naturalSize.width))) x \(Int(abs(naturalSize.height)))"

        return VideoMetadata(
            duration: duration.isFinite ? duration : 0,
            fps: Double(fps),
            resolution: resolution,
            creationDate: nil
        )
    }

    private func generateThumbnail(for url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        let image = UIImage(cgImage: cgImage)
        let data = image.jpegData(compressionQuality: 0.85) ?? Data()
        let destination = try storage.makeExportURL(fileName: "\(UUID().uuidString)-thumbnail.jpg")
        try data.write(to: destination, options: [.atomic])
        return destination
    }
}

enum VideoImportError: LocalizedError {
    case unreadableVideo

    var errorDescription: String? {
        "The selected video could not be imported."
    }
}
