import Foundation

final class LocalStorageService {
    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var sessionsURL: URL {
        documentsDirectory.appendingPathComponent("lift_sessions.json")
    }

    func saveSessions(_ sessions: [LiftSession]) throws {
        let data = try JSONEncoder.liftPath.encode(sessions)
        try data.write(to: sessionsURL, options: [.atomic])
    }

    func loadSessions() throws -> [LiftSession] {
        guard fileManager.fileExists(atPath: sessionsURL.path) else { return [] }
        let data = try Data(contentsOf: sessionsURL)
        return try JSONDecoder.liftPath.decode([LiftSession].self, from: data)
    }

    func makeImportURL(for sourceURL: URL) throws -> URL {
        let folder = documentsDirectory.appendingPathComponent("ImportedVideos", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(UUID().uuidString).\(sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension)")
    }

    func makeExportURL(fileName: String) throws -> URL {
        let folder = documentsDirectory.appendingPathComponent("Exports", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }
}

extension JSONEncoder {
    static var liftPath: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var liftPath: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
