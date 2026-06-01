import Foundation

final class WeightRecommendationService {
    func recommend(details: LiftDetails, metrics: LiftMetrics) -> WeightRecommendation {
        let increment = increment(for: details.liftType, unit: details.unit)
        let currentWeight = details.weight
        let rpe = details.rpe ?? metrics.estimatedRPE ?? 8
        let score = metrics.techniqueScore

        if score >= 85, rpe <= 8 {
            return WeightRecommendation(
                suggestedWeight: currentWeight + increment,
                recommendationType: .increase,
                reason: "Technique looked strong and effort was manageable.",
                conservativeOption: currentWeight + increment / 2,
                aggressiveOption: currentWeight + increment * 1.5
            )
        }

        if score >= 70, rpe <= 9 {
            return WeightRecommendation(
                suggestedWeight: currentWeight,
                recommendationType: .repeatLoad,
                reason: "Repeat this weight until the movement path looks cleaner.",
                conservativeOption: currentWeight - increment / 2,
                aggressiveOption: currentWeight + increment / 2
            )
        }

        return WeightRecommendation(
            suggestedWeight: max(0, currentWeight - increment),
            recommendationType: .decrease,
            reason: "Technique quality or effort suggests reducing load and focusing on execution.",
            conservativeOption: max(0, currentWeight - increment * 1.5),
            aggressiveOption: currentWeight
        )
    }

    private func increment(for liftType: LiftType, unit: WeightUnit) -> Double {
        switch liftType {
        case .deadlift, .squat:
            return unit == .lb ? 10 : 5
        case .benchPress, .overheadPress:
            return unit == .lb ? 5 : 2.5
        default:
            return unit == .lb ? 5 : 2.5
        }
    }
}
