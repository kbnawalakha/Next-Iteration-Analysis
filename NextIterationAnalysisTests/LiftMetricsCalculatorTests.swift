import XCTest
@testable import NextIterationAnalysis

final class LiftMetricsCalculatorTests: XCTestCase {
    private let calculator = LiftMetricsCalculator()
    private let liftTypeInferenceService = LiftTypeInferenceService()

    func testCalculatesDisplacementAndVelocity() {
        let path = [
            point(frame: 0, time: 0, x: 0.50, y: 0.80),
            point(frame: 1, time: 0.5, x: 0.52, y: 0.55),
            point(frame: 2, time: 1.0, x: 0.54, y: 0.35),
            point(frame: 3, time: 1.5, x: 0.51, y: 0.70)
        ]

        let metrics = calculator.calculate(path: path, reps: 1)

        XCTAssertEqual(metrics.verticalDisplacement ?? 0, 0.45, accuracy: 0.0001)
        XCTAssertEqual(metrics.horizontalDisplacement ?? 0, 0.04, accuracy: 0.0001)
        XCTAssertGreaterThan(metrics.averageVelocity ?? 0, 0)
        XCTAssertGreaterThan(metrics.peakVelocity ?? 0, metrics.minimumVelocity ?? 0)
        XCTAssertEqual(metrics.pathConsistencyScore, 78, accuracy: 0.0001)
    }

    func testEmptyPathReturnsZeroScores() {
        let metrics = calculator.calculate(path: [], reps: 1)

        XCTAssertNil(metrics.verticalDisplacement)
        XCTAssertNil(metrics.horizontalDisplacement)
        XCTAssertEqual(metrics.pathConsistencyScore, 0)
        XCTAssertEqual(metrics.techniqueScore, 0)
    }

    func testVelocitySegmentsAreNormalized() {
        let path = [
            point(frame: 0, time: 0, x: 0.4, y: 0.8),
            point(frame: 1, time: 0.5, x: 0.4, y: 0.5),
            point(frame: 2, time: 1.0, x: 0.4, y: 0.4)
        ]

        let segments = calculator.velocitySegments(for: path)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.map(\.speed).max() ?? 0, 1, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(segments.map(\.speed).min() ?? 0, 1)
    }

    func testRepSegmentsExposeBottomAndOpacity() {
        let path = [
            point(frame: 0, time: 0.0, x: 0.5, y: 0.4),
            point(frame: 1, time: 0.2, x: 0.5, y: 0.8),
            point(frame: 2, time: 0.4, x: 0.5, y: 0.45),
            point(frame: 3, time: 0.6, x: 0.5, y: 0.42),
            point(frame: 4, time: 0.8, x: 0.5, y: 0.82),
            point(frame: 5, time: 1.0, x: 0.5, y: 0.43)
        ]

        let reps = calculator.repSegments(for: path, reps: 2)

        XCTAssertEqual(reps.count, 2)
        XCTAssertEqual(reps[0].bottom.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(reps[0].opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(reps[1].bottom.y, 0.82, accuracy: 0.0001)
        XCTAssertEqual(reps[1].opacity, 1.0, accuracy: 0.0001)
    }

    func testVideoMetadataAspectRatioUsesDimensions() {
        let metadata = VideoMetadata(
            duration: 1,
            fps: 30,
            resolution: "1920 x 1080",
            width: 1080,
            height: 1920,
            creationDate: nil
        )

        XCTAssertEqual(metadata.aspectRatio ?? 0, 0.5625, accuracy: 0.0001)
    }

    func testDetectsRepsFromPlateBottoms() {
        let path = [
            point(frame: 0, time: 0.0, x: 0.5, y: 0.35),
            point(frame: 1, time: 0.1, x: 0.5, y: 0.48),
            point(frame: 2, time: 0.2, x: 0.5, y: 0.72),
            point(frame: 3, time: 0.3, x: 0.5, y: 0.49),
            point(frame: 4, time: 0.4, x: 0.5, y: 0.36),
            point(frame: 5, time: 0.5, x: 0.5, y: 0.47),
            point(frame: 6, time: 0.6, x: 0.5, y: 0.74),
            point(frame: 7, time: 0.7, x: 0.5, y: 0.50),
            point(frame: 8, time: 0.8, x: 0.5, y: 0.35),
            point(frame: 9, time: 0.9, x: 0.5, y: 0.48),
            point(frame: 10, time: 1.0, x: 0.5, y: 0.73),
            point(frame: 11, time: 1.1, x: 0.5, y: 0.49),
            point(frame: 12, time: 1.2, x: 0.5, y: 0.36)
        ]

        let metrics = calculator.calculate(path: path, reps: 1, weight: 225)

        XCTAssertEqual(metrics.detectedReps, 3)
        XCTAssertNotNil(metrics.estimatedRPE)
        XCTAssertNotNil(metrics.estimatedOneRepMax)
    }

    func testEstimatedOneRepMaxUsesDetectedRepsAndRPE() {
        let path = [
            point(frame: 0, time: 0.0, x: 0.5, y: 0.35),
            point(frame: 1, time: 0.1, x: 0.5, y: 0.50),
            point(frame: 2, time: 0.2, x: 0.5, y: 0.72),
            point(frame: 3, time: 0.3, x: 0.5, y: 0.50),
            point(frame: 4, time: 0.4, x: 0.5, y: 0.35),
            point(frame: 5, time: 0.5, x: 0.5, y: 0.49),
            point(frame: 6, time: 0.6, x: 0.5, y: 0.73),
            point(frame: 7, time: 0.7, x: 0.5, y: 0.48),
            point(frame: 8, time: 0.8, x: 0.5, y: 0.36)
        ]

        let metrics = calculator.calculate(path: path, reps: 1, weight: 100)

        XCTAssertEqual(metrics.detectedReps, 2)
        XCTAssertGreaterThan(metrics.estimatedOneRepMax ?? 0, 106)
    }

    func testLiftTypeInferenceKeepsExplicitSelection() {
        let inferred = liftTypeInferenceService.inferLiftType(
            selectedLiftType: .benchPress,
            path: [
                point(frame: 0, time: 0, x: 0.5, y: 0.8),
                point(frame: 1, time: 1, x: 0.5, y: 0.3)
            ],
            poseFrames: []
        )

        XCTAssertEqual(inferred, .benchPress)
    }

    func testLiftTypeInferenceDetectsDeadliftFromLowRisingPlate() {
        let inferred = liftTypeInferenceService.inferLiftType(
            selectedLiftType: .analyzeFromVideo,
            path: [
                point(frame: 0, time: 0, x: 0.5, y: 0.82),
                point(frame: 1, time: 1, x: 0.5, y: 0.62),
                point(frame: 2, time: 2, x: 0.5, y: 0.50)
            ],
            poseFrames: []
        )

        XCTAssertEqual(inferred, .deadlift)
    }

    private func point(frame: Int, time: Double, x: Double, y: Double) -> TrackedPoint {
        TrackedPoint(id: UUID(), timestamp: time, frameIndex: frame, x: x, y: y, confidence: 0.9)
    }
}
