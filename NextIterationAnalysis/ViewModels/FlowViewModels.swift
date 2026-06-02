import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class VideoImportViewModel: ObservableObject {
    @Published var selectedItem: PhotosPickerItem?
    @Published var importedVideo: ImportedLiftVideo?
    @Published var isImporting = false
    @Published var isReducingVideo = false
    @Published var compressionQuality: VideoCompressionQuality = .medium
    @Published var errorMessage: String?
    @Published var videoMessage: String?

    private let importService = VideoImportService()

    func importSelectedVideo() async {
        guard let selectedItem = selectedItem else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            importedVideo = try await importService.importVideo(from: selectedItem)
            videoMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reduceVideoSize() async {
        guard let importedVideo else { return }
        isReducingVideo = true
        errorMessage = nil
        videoMessage = nil
        defer { isReducingVideo = false }

        do {
            let reducedVideo = try await importService.reducedSizeVideo(
                from: importedVideo,
                quality: compressionQuality
            )
            self.importedVideo = reducedVideo
            videoMessage = "Using reduced \(compressionQuality.displayName.lowercased()) video for analysis and export."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class LiftDetailsViewModel: ObservableObject {
    @Published var details = LiftDetails()

    var canAnalyze: Bool {
        details.weight > 0 && details.reps > 0
    }
}

enum AnalysisStep: String, CaseIterable, Identifiable {
    case loadingVideo = "Loading video"
    case extractingFrames = "Extracting frames"
    case detectingPose = "Detecting lifter pose"
    case detectingPlate = "Detecting barbell/plates"
    case trackingPath = "Tracking movement path"
    case calculatingMetrics = "Calculating metrics"
    case generatingFeedback = "Generating technique feedback"
    case recommendingWeight = "Creating next-weight recommendation"

    var id: String { rawValue }
}

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published var currentStep: AnalysisStep = .loadingVideo
    @Published var completedSteps: Set<AnalysisStep> = []
    @Published var session: LiftSession?
    @Published var errorMessage: String?
    @Published var exportMessage: String?
    @Published var exportedURL: URL?

    let importedVideo: ImportedLiftVideo?
    let details: LiftDetails
    let startPoint: NormalizedPoint
    let trackingMode: TrackingMode

    private let tracker = BarPathTracker()
    private let poseDetectionService = PoseDetectionService()
    private let metricsCalculator = LiftMetricsCalculator()
    private let ruleEngine = TechniqueRuleEngine()
    private let liftTypeInferenceService = LiftTypeInferenceService()
    private let recommendationService = WeightRecommendationService()
    private let aiService = AIAnalysisService()
    private let csvExportService = CSVExportService()
    private let annotatedVideoExportService = AnnotatedVideoExportService()

    init(
        importedVideo: ImportedLiftVideo?,
        details: LiftDetails,
        startPoint: NormalizedPoint,
        trackingMode: TrackingMode
    ) {
        self.importedVideo = importedVideo
        self.details = details
        self.startPoint = startPoint
        self.trackingMode = trackingMode
    }

    func runAnalysis() async {
        errorMessage = nil

        do {
            try await step(.loadingVideo)
            try await step(.extractingFrames)
            try await step(.detectingPose)
            let poseFrames = await poseDetectionService.detectPoseFrames(videoURL: importedVideo?.videoURL)

            try await step(.detectingPlate)
            try await step(.trackingPath)
            let path = await tracker.track(
                videoURL: importedVideo?.videoURL,
                startingPoint: startPoint,
                reps: details.reps,
                mode: trackingMode
            )

            try await step(.calculatingMetrics)
            let metrics = metricsCalculator.calculate(path: path, reps: details.reps, weight: details.weight)
            let analyzedLiftType = liftTypeInferenceService.inferLiftType(
                selectedLiftType: details.liftType,
                path: path,
                poseFrames: poseFrames
            )
            var analyzedDetails = details
            analyzedDetails.liftType = analyzedLiftType
            analyzedDetails.reps = metrics.detectedReps ?? details.reps
            analyzedDetails.rpe = details.rpe ?? metrics.estimatedRPE

            try await step(.generatingFeedback)
            var critique = ruleEngine.critique(details: analyzedDetails, metrics: metrics, trackingMode: trackingMode)
            critique = await aiService.refineCritique(
                videoURL: importedVideo?.videoURL,
                details: analyzedDetails,
                metrics: metrics,
                poseFrames: poseFrames,
                critique: critique
            )

            try await step(.recommendingWeight)
            let recommendation = recommendationService.recommend(details: analyzedDetails, metrics: metrics)
            let confidence = path.map(\.confidence).reduce(0, +) / Double(max(path.count, 1)) * 100

            session = LiftSession(
                id: UUID(),
                createdAt: .now,
                videoURL: importedVideo?.videoURL,
                thumbnailURL: importedVideo?.thumbnailURL,
                videoAspectRatio: importedVideo?.metadata.aspectRatio,
                liftType: analyzedLiftType,
                weight: details.weight,
                unit: details.unit,
                reps: analyzedDetails.reps,
                rpe: analyzedDetails.rpe,
                goal: details.goal,
                notes: details.notes.isEmpty ? nil : details.notes,
                analysis: LiftAnalysis(
                    trackedPath: path,
                    poseFrames: poseFrames,
                    metrics: metrics,
                    critique: critique,
                    recommendation: recommendation,
                    confidenceScore: confidence
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCSV() {
        guard let session = session else { return }
        do {
            let url = try csvExportService.export(session: session)
            exportMessage = "CSV exported to \(url.lastPathComponent)"
            exportedURL = url
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    func exportAnnotatedVideo(colorStyle: BarPathColorStyle = .velocity) async {
        guard let session = session else { return }
        do {
            let url = try await annotatedVideoExportService.export(session: session, colorStyle: colorStyle)
            exportMessage = "Annotated video exported to \(url.lastPathComponent)"
            exportedURL = url
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    private func step(_ step: AnalysisStep) async throws {
        currentStep = step
        try await Task.sleep(nanoseconds: 350_000_000)
        completedSteps.insert(step)
    }
}

@MainActor
final class PointSelectionViewModel: ObservableObject {
    @Published var trackingMode: TrackingMode = .automaticPlateDetection
    @Published var selectedPoint = NormalizedPoint(x: 0.5, y: 0.5)
    @Published var autoDetectionMessage: String?
    @Published var confidenceLabel: String = "Low"
    @Published var confidence: Double = 0
    @Published var isDetecting = false

    private let detector = AutomaticPlateDetectionService()

    func autoDetect(video: ImportedLiftVideo?) async {
        isDetecting = true
        defer { isDetecting = false }
        trackingMode = .automaticPlateDetection
        let result = await detector.detectPlateStartPoint(videoURL: video?.videoURL, thumbnailURL: video?.thumbnailURL)
        selectedPoint = result.point
        confidence = result.confidence
        confidenceLabel = result.confidenceLabel
        autoDetectionMessage = "\(result.explanation) Confidence \(result.confidenceLabel) (\(Formatting.percent(result.confidence * 100)))."
    }

    func markManuallyAdjusted() {
        trackingMode = .automaticPlateDetection
        confidence = min(confidence, 0.74)
        confidenceLabel = confidence > 0 ? "Manual Adjust" : "Adjusted"
        autoDetectionMessage = "Plate center adjusted. The tracker will follow this center point across the lift."
    }
}
