import XCTest
@testable import NextIterationAnalysis

final class LiftMetricsCalculatorTests: XCTestCase {
    private let calculator = LiftMetricsCalculator()

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

    private func point(frame: Int, time: Double, x: Double, y: Double) -> TrackedPoint {
        TrackedPoint(id: UUID(), timestamp: time, frameIndex: frame, x: x, y: y, confidence: 0.9)
    }
}
