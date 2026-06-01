import Foundation

final class LiftMetricsCalculator {
    func calculate(path: [TrackedPoint], reps: Int, weight: Double? = nil) -> LiftMetrics {
        guard path.count > 1 else {
            return LiftMetrics(
                detectedReps: nil,
                estimatedRPE: nil,
                estimatedOneRepMax: nil,
                verticalDisplacement: nil,
                horizontalDisplacement: nil,
                averageVelocity: nil,
                peakVelocity: nil,
                minimumVelocity: nil,
                pathConsistencyScore: 0,
                techniqueScore: 0
            )
        }

        let xs = path.map(\.x)
        let ys = path.map(\.y)
        let horizontal = (xs.max() ?? 0) - (xs.min() ?? 0)
        let vertical = (ys.max() ?? 0) - (ys.min() ?? 0)
        let velocities = zip(path.dropFirst(), path).map { current, previous in
            rawSpeed(from: previous, to: current)
        }

        let averageVelocity = velocities.reduce(0, +) / Double(max(velocities.count, 1))
        let peakVelocity = velocities.max() ?? 0
        let minimumVelocity = velocities.min() ?? 0
        let pathConsistency = max(0, 100 - horizontal * 550)
        let detectedReps = detectReps(path: path, fallbackReps: reps)
        let techniqueScore = max(35, min(98, pathConsistency - Double(max(detectedReps - 5, 0)) * 1.5))
        let estimatedRPE = estimateRPE(path: path, reps: detectedReps, techniqueScore: techniqueScore)
        let estimatedOneRepMax = estimateOneRepMax(weight: weight, reps: detectedReps, rpe: estimatedRPE)

        return LiftMetrics(
            detectedReps: detectedReps,
            estimatedRPE: estimatedRPE,
            estimatedOneRepMax: estimatedOneRepMax,
            verticalDisplacement: vertical,
            horizontalDisplacement: horizontal,
            averageVelocity: averageVelocity,
            peakVelocity: peakVelocity,
            minimumVelocity: minimumVelocity,
            pathConsistencyScore: pathConsistency,
            techniqueScore: techniqueScore
        )
    }

    func detectReps(path: [TrackedPoint], fallbackReps: Int) -> Int {
        let bottoms = detectedBottomIndices(path: path, fallbackReps: fallbackReps)
        if !bottoms.isEmpty {
            return max(1, min(bottoms.count, 20))
        }

        guard path.count > 8 else { return max(fallbackReps, 1) }

        let smoothed = SmoothingUtils.movingAverage(path, window: 3)
        let ys = smoothed.map(\.y)
        guard let minY = ys.min(), let maxY = ys.max() else { return max(fallbackReps, 1) }
        let range = maxY - minY
        guard range > 0.05 else { return max(fallbackReps, 1) }

        let netTravel = abs((smoothed.first?.y ?? 0) - (smoothed.last?.y ?? 0))
        return netTravel > range * 0.45 ? 1 : max(fallbackReps, 1)
    }

    func velocitySegments(for path: [TrackedPoint]) -> [VelocitySegment] {
        guard path.count > 1 else { return [] }
        let raw = zip(path.dropFirst(), path).map { current, previous in
            let speed = rawSpeed(from: previous, to: current)
            return VelocitySegment(from: previous, to: current, speed: speed)
        }
        let maxSpeed = raw.map(\.speed).max() ?? 1
        return raw.map { VelocitySegment(from: $0.from, to: $0.to, speed: $0.speed / maxSpeed) }
    }

    func repSegments(for path: [TrackedPoint], reps: Int) -> [RepPathSegment] {
        guard path.count > 2, reps > 0 else { return [] }

        let bottoms = detectedBottomIndices(path: path, fallbackReps: reps)
        if bottoms.count >= 1 {
            return bottoms.enumerated().compactMap { repIndex, bottomIndex in
                let previousBottom = repIndex > 0 ? bottoms[repIndex - 1] : nil
                let nextBottom = repIndex < bottoms.count - 1 ? bottoms[repIndex + 1] : nil
                let start = previousBottom.map { max(0, ($0 + bottomIndex) / 2) } ?? 0
                let end = nextBottom.map { min(path.count - 1, (bottomIndex + $0) / 2) } ?? (path.count - 1)
                guard start < end, bottomIndex >= start, bottomIndex <= end else { return nil }

                let repPoints = Array(path[start...end])
                let opacity: Double = repIndex == bottoms.count - 1 ? 1 : 0.5

                return RepPathSegment(
                    index: repIndex,
                    points: repPoints,
                    bottom: path[bottomIndex],
                    opacity: opacity
                )
            }
        }

        let count = path.count
        return (0..<reps).compactMap { repIndex in
            let start = Int((Double(repIndex) / Double(reps)) * Double(count - 1))
            let end = Int((Double(repIndex + 1) / Double(reps)) * Double(count - 1))
            guard start < end, start < count else { return nil }
            let boundedEnd = min(end, count - 1)
            let repPoints = Array(path[start...boundedEnd])
            guard let bottom = repPoints.max(by: { $0.y < $1.y }) else { return nil }

            let opacity: Double
            if repIndex == reps - 1 {
                opacity = 1
            } else {
                opacity = 0.5
            }

            return RepPathSegment(
                index: repIndex,
                points: repPoints,
                bottom: bottom,
                opacity: opacity
            )
        }
    }

    private func estimateRPE(path: [TrackedPoint], reps: Int, techniqueScore: Double) -> Double? {
        let repSegments = repSegments(for: path, reps: reps)
        guard !repSegments.isEmpty else { return nil }

        let repPeakSpeeds = repSegments.map { segment in
            zip(segment.points.dropFirst(), segment.points).map { current, previous in
                rawSpeed(from: previous, to: current)
            }.max() ?? 0
        }
        guard let firstPeak = repPeakSpeeds.first, firstPeak > 0 else { return nil }
        let lastPeak = repPeakSpeeds.last ?? firstPeak
        let velocityLoss = max(0, min(1, (firstPeak - lastPeak) / firstPeak))
        let techniquePenalty = max(0, (85 - techniqueScore) / 85)
        let repPenalty = min(1.2, Double(max(reps - 5, 0)) * 0.18)
        let rpe = 6.2 + velocityLoss * 2.4 + techniquePenalty * 1.3 + repPenalty
        return min(10, max(6, (rpe * 10).rounded() / 10))
    }

    private func estimateOneRepMax(weight: Double?, reps: Int, rpe: Double?) -> Double? {
        guard let weight, weight > 0, reps > 0 else { return nil }
        let repsInReserve = max(0, 10 - (rpe ?? 8))
        let effectiveReps = Double(reps) + repsInReserve
        return weight * (1 + effectiveReps / 30)
    }

    private func detectedBottomIndices(path: [TrackedPoint], fallbackReps: Int) -> [Int] {
        guard path.count > 8 else { return [] }

        let smoothed = SmoothingUtils.movingAverage(path, window: 3)
        let ys = smoothed.map(\.y)
        guard let minY = ys.min(), let maxY = ys.max() else { return [] }
        let range = maxY - minY
        guard range > 0.05 else { return [] }

        let minimumGap = max(4, smoothed.count / max(fallbackReps * 3, 6))
        let prominence = range * 0.22
        var bottoms: [Int] = []

        for index in 1..<(smoothed.count - 1) {
            let previous = smoothed[index - 1].y
            let current = smoothed[index].y
            let next = smoothed[index + 1].y
            let localDrop = current - min(previous, next)
            let descent = current - ys[max(0, index - minimumGap)]
            let ascent = current - ys[min(ys.count - 1, index + minimumGap)]
            guard current >= previous,
                  current > next,
                  current - minY >= prominence,
                  max(localDrop, min(descent, ascent)) >= prominence * 0.2 else {
                continue
            }

            if let last = bottoms.last, index - last < minimumGap {
                if current > smoothed[last].y {
                    bottoms[bottoms.count - 1] = index
                }
            } else {
                bottoms.append(index)
            }
        }

        return bottoms
    }

    private func rawSpeed(from previous: TrackedPoint, to current: TrackedPoint) -> Double {
        let dt = max(current.timestamp - previous.timestamp, 0.001)
        let dx = current.x - previous.x
        let dy = current.y - previous.y
        return sqrt(dx * dx + dy * dy) / dt
    }
}

struct VelocitySegment: Identifiable {
    let id = UUID()
    let from: TrackedPoint
    let to: TrackedPoint
    let speed: Double
}

struct RepPathSegment: Identifiable {
    let id = UUID()
    let index: Int
    let points: [TrackedPoint]
    let bottom: TrackedPoint
    let opacity: Double
}
