import Foundation

final class LiftMetricsCalculator {
    func calculate(path: [TrackedPoint], reps: Int) -> LiftMetrics {
        guard path.count > 1 else {
            return LiftMetrics(
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
            let dt = max(current.timestamp - previous.timestamp, 0.001)
            let dx = current.x - previous.x
            let dy = current.y - previous.y
            return sqrt(dx * dx + dy * dy) / dt
        }

        let averageVelocity = velocities.reduce(0, +) / Double(max(velocities.count, 1))
        let peakVelocity = velocities.max() ?? 0
        let minimumVelocity = velocities.min() ?? 0
        let pathConsistency = max(0, 100 - horizontal * 550)
        let techniqueScore = max(35, min(98, pathConsistency - Double(max(reps - 5, 0)) * 1.5))

        return LiftMetrics(
            verticalDisplacement: vertical,
            horizontalDisplacement: horizontal,
            averageVelocity: averageVelocity,
            peakVelocity: peakVelocity,
            minimumVelocity: minimumVelocity,
            pathConsistencyScore: pathConsistency,
            techniqueScore: techniqueScore
        )
    }

    func velocitySegments(for path: [TrackedPoint]) -> [VelocitySegment] {
        guard path.count > 1 else { return [] }
        let raw = zip(path.dropFirst(), path).map { current, previous in
            let dt = max(current.timestamp - previous.timestamp, 0.001)
            let speed = hypot(current.x - previous.x, current.y - previous.y) / dt
            return VelocitySegment(from: previous, to: current, speed: speed)
        }
        let maxSpeed = raw.map(\.speed).max() ?? 1
        return raw.map { VelocitySegment(from: $0.from, to: $0.to, speed: $0.speed / maxSpeed) }
    }
}

struct VelocitySegment: Identifiable {
    let id = UUID()
    let from: TrackedPoint
    let to: TrackedPoint
    let speed: Double
}
