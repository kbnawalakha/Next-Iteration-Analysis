import Foundation

final class WeightRecommendationService {
    private let metricsCalculator = LiftMetricsCalculator()

    func recommend(details: LiftDetails, metrics: LiftMetrics, path: [TrackedPoint] = []) -> WeightRecommendation {
        let increment = increment(for: details.liftType, unit: details.unit)
        let currentWeight = details.weight
        let rpe = details.rpe ?? metrics.estimatedRPE ?? 8
        let score = metrics.techniqueScore
        let readiness = formReadinessScore(details: details, metrics: metrics, path: path)

        if let increase = suggestedIncrease(unit: details.unit, readiness: readiness, rpe: rpe) {
            return WeightRecommendation(
                suggestedWeight: currentWeight + increase,
                recommendationType: .increase,
                reason: "Bar speed stayed strong and the rep paths overlapped well, so form looks ready for a heavier set.",
                conservativeOption: currentWeight + min(increase, increment),
                aggressiveOption: currentWeight + increase
            )
        }

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

    private func suggestedIncrease(unit: WeightUnit, readiness: Double, rpe: Double) -> Double? {
        let small = unit == .lb ? 5.0 : 2.5
        let medium = unit == .lb ? 10.0 : 5.0
        let large = unit == .lb ? 15.0 : 7.5

        if readiness >= 0.86, rpe <= 7.5 { return large }
        if readiness >= 0.78, rpe <= 8.0 { return medium }
        if readiness >= 0.68, rpe <= 8.5 { return small }
        return nil
    }

    private func formReadinessScore(details: LiftDetails, metrics: LiftMetrics, path: [TrackedPoint]) -> Double {
        let technique = min(1, max(0, metrics.techniqueScore / 100))
        let efficiency = min(1, max(0, metrics.pathEfficiency ?? 0))
        let overlap = repOverlapScore(path: path, reps: metrics.detectedReps ?? details.reps)
        let speed = speedConsistencyScore(path: path, reps: metrics.detectedReps ?? details.reps)

        return min(1, max(0, technique * 0.30 + overlap * 0.30 + speed * 0.25 + efficiency * 0.15))
    }

    private func repOverlapScore(path: [TrackedPoint], reps: Int) -> Double {
        let segments = metricsCalculator.repSegments(for: path, reps: max(1, reps))
            .map(\.points)
            .filter { $0.count >= 3 }
        guard segments.count >= 2 else { return 0.55 }

        let sampleCount = 16
        let sampledReps = segments.map { sample(points: $0, count: sampleCount) }
        var totalDeviation = 0.0

        for sampleIndex in 0..<sampleCount {
            let xs = sampledReps.map { $0[sampleIndex].x }
            let ys = sampledReps.map { $0[sampleIndex].y }
            let meanX = xs.reduce(0, +) / Double(xs.count)
            let meanY = ys.reduce(0, +) / Double(ys.count)
            let deviation = zip(xs, ys).map { x, y in
                let dx = x - meanX
                let dy = y - meanY
                return sqrt(dx * dx + dy * dy)
            }.reduce(0, +) / Double(xs.count)
            totalDeviation += deviation
        }

        let averageDeviation = totalDeviation / Double(sampleCount)
        return min(1, max(0, 1 - averageDeviation / 0.045))
    }

    private func speedConsistencyScore(path: [TrackedPoint], reps: Int) -> Double {
        let segments = metricsCalculator.repSegments(for: path, reps: max(1, reps))
            .map(\.points)
            .filter { $0.count >= 2 }
        guard segments.count >= 2 else { return 0.55 }

        let repSpeeds = segments.map { points in
            zip(points.dropFirst(), points).map { current, previous in
                rawSpeed(from: previous, to: current)
            }.reduce(0, +) / Double(max(points.count - 1, 1))
        }.filter { $0.isFinite && $0 > 0 }

        guard let first = repSpeeds.first, first > 0, let last = repSpeeds.last else { return 0.55 }
        let mean = repSpeeds.reduce(0, +) / Double(repSpeeds.count)
        let variance = repSpeeds.map { speed in
            let diff = speed - mean
            return diff * diff
        }.reduce(0, +) / Double(repSpeeds.count)
        let consistency = max(0, 1 - sqrt(variance) / max(mean, 0.0001))
        let retention = min(1, max(0, last / first))
        return min(1, consistency * 0.65 + retention * 0.35)
    }

    private func sample(points: [TrackedPoint], count: Int) -> [NormalizedPoint] {
        guard let first = points.first else { return [] }
        guard points.count > 1, count > 1 else {
            return Array(repeating: NormalizedPoint(x: first.x, y: first.y), count: max(1, count))
        }

        return (0..<count).map { index in
            let position = Double(index) * Double(points.count - 1) / Double(count - 1)
            let lower = min(points.count - 1, max(0, Int(position.rounded(.down))))
            let upper = min(points.count - 1, lower + 1)
            let progress = position - Double(lower)
            let start = points[lower]
            let end = points[upper]
            return NormalizedPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
        }
    }

    private func rawSpeed(from previous: TrackedPoint, to current: TrackedPoint) -> Double {
        let dt = max(current.timestamp - previous.timestamp, 0.001)
        let dx = current.x - previous.x
        let dy = current.y - previous.y
        return sqrt(dx * dx + dy * dy) / dt
    }
}
