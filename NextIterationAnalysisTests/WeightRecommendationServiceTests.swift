import XCTest
@testable import NextIterationAnalysis

final class WeightRecommendationServiceTests: XCTestCase {
    private let service = WeightRecommendationService()

    func testStrongLowRPELiftIncreasesWeight() {
        let details = LiftDetails(liftType: .squat, weight: 225, unit: .lb, reps: 5, rpe: 7.5, goal: .strength)
        let metrics = LiftMetrics(
            detectedReps: 5,
            estimatedRPE: 7.8,
            estimatedOneRepMax: 270,
            verticalDisplacement: 0.5,
            horizontalDisplacement: 0.03,
            averageVelocity: 0.4,
            peakVelocity: 0.7,
            minimumVelocity: 0.3,
            pathConsistencyScore: 92,
            techniqueScore: 88
        )

        let recommendation = service.recommend(details: details, metrics: metrics)

        XCTAssertEqual(recommendation.recommendationType, .increase)
        XCTAssertEqual(recommendation.suggestedWeight, 235)
    }

    func testModerateTechniqueRepeatsWeight() {
        let details = LiftDetails(liftType: .benchPress, weight: 185, unit: .lb, reps: 5, rpe: 8.5, goal: .strength)
        let metrics = LiftMetrics(
            detectedReps: 5,
            estimatedRPE: 8.5,
            estimatedOneRepMax: 220,
            verticalDisplacement: 0.4,
            horizontalDisplacement: 0.08,
            averageVelocity: 0.3,
            peakVelocity: 0.5,
            minimumVelocity: 0.2,
            pathConsistencyScore: 76,
            techniqueScore: 74
        )

        let recommendation = service.recommend(details: details, metrics: metrics)

        XCTAssertEqual(recommendation.recommendationType, .repeatLoad)
        XCTAssertEqual(recommendation.suggestedWeight, 185)
    }

    func testLowTechniqueDecreasesWeight() {
        let details = LiftDetails(liftType: .deadlift, weight: 315, unit: .lb, reps: 3, rpe: 9.5, goal: .strength)
        let metrics = LiftMetrics(
            detectedReps: 3,
            estimatedRPE: 9.5,
            estimatedOneRepMax: 340,
            verticalDisplacement: 0.5,
            horizontalDisplacement: 0.2,
            averageVelocity: 0.2,
            peakVelocity: 0.4,
            minimumVelocity: 0.08,
            pathConsistencyScore: 52,
            techniqueScore: 60
        )

        let recommendation = service.recommend(details: details, metrics: metrics)

        XCTAssertEqual(recommendation.recommendationType, .decrease)
        XCTAssertEqual(recommendation.suggestedWeight, 305)
    }
}
