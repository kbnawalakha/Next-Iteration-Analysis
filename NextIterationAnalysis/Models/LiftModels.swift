import Foundation

enum LiftType: String, Codable, CaseIterable, Identifiable {
    case analyzeFromVideo
    case squat
    case benchPress
    case deadlift
    case overheadPress
    case clean
    case snatch
    case row
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .analyzeFromVideo: return "Analyze From Video"
        case .benchPress: return "Bench Press"
        case .overheadPress: return "Overhead Press"
        default: return rawValue.capitalized
        }
    }

    var isVideoInferred: Bool {
        self == .analyzeFromVideo
    }
}

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case lb
    case kg

    var id: String { rawValue }
}

enum TrainingGoal: String, Codable, CaseIterable, Identifiable {
    case strength
    case hypertrophy
    case technique
    case peaking

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct LiftSession: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let videoURL: URL?
    let thumbnailURL: URL?
    let videoAspectRatio: Double?
    let liftType: LiftType
    let weight: Double
    let unit: WeightUnit
    let reps: Int
    let rpe: Double?
    let goal: TrainingGoal
    let notes: String?
    var analysis: LiftAnalysis?
}

struct LiftAnalysis: Codable {
    let trackedPath: [TrackedPoint]
    let poseFrames: [PoseFrame]
    let metrics: LiftMetrics
    let critique: TechniqueCritique
    let recommendation: WeightRecommendation
    let confidenceScore: Double
}

struct TrackedPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Double
    let frameIndex: Int
    let x: Double
    let y: Double
    let confidence: Double
}

struct PoseFrame: Codable {
    let timestamp: Double
    let joints: [String: JointPoint]
    let confidence: Double
}

struct JointPoint: Codable {
    let x: Double
    let y: Double
    let confidence: Double
}

struct LiftMetrics: Codable {
    let detectedReps: Int?
    let estimatedRPE: Double?
    let estimatedOneRepMax: Double?
    let verticalDisplacement: Double?
    let horizontalDisplacement: Double?
    let averageVelocity: Double?
    let peakVelocity: Double?
    let minimumVelocity: Double?
    let totalDistance: Double?
    let pathEfficiency: Double?
    let pathConsistencyScore: Double
    let techniqueScore: Double
}

struct TechniqueCritique: Codable {
    let summary: String
    let positives: [String]
    let issues: [TechniqueIssue]
    let nextSessionFocus: [String]
}

struct TechniqueIssue: Codable, Identifiable {
    let id: UUID
    let title: String
    let severity: IssueSeverity
    let explanation: String
    let cue: String
}

enum IssueSeverity: String, Codable {
    case low
    case medium
    case high
}

struct WeightRecommendation: Codable {
    let suggestedWeight: Double
    let recommendationType: RecommendationType
    let reason: String
    let conservativeOption: Double
    let aggressiveOption: Double
}

enum RecommendationType: String, Codable {
    case increase
    case repeatLoad = "repeat"
    case decrease

    var displayName: String { rawValue.capitalized }
}

struct VideoMetadata: Codable {
    let duration: Double
    let fps: Double
    let resolution: String
    let width: Double?
    let height: Double?
    let creationDate: Date?

    var aspectRatio: Double? {
        if let width, let height, height > 0 {
            return width / height
        }

        let parts = resolution
            .replacingOccurrences(of: " ", with: "")
            .split(separator: "x")
            .compactMap { Double($0) }

        guard parts.count == 2, parts[1] > 0 else { return nil }
        return parts[0] / parts[1]
    }
}

struct ImportedLiftVideo {
    let videoURL: URL
    let thumbnailURL: URL?
    let metadata: VideoMetadata
}

struct LiftDetails {
    var liftType: LiftType = .analyzeFromVideo
    var weight: Double = 135
    var unit: WeightUnit = .lb
    var reps: Int = 5
    var rpe: Double?
    var goal: TrainingGoal = .strength
    var notes: String = ""
}
