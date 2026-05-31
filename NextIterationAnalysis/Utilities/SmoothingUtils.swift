import Foundation

enum SmoothingUtils {
    static func movingAverage(_ points: [TrackedPoint], window: Int = 5) -> [TrackedPoint] {
        guard points.count > 2, window > 1 else { return points }

        return points.enumerated().map { index, point in
            let lower = max(0, index - window / 2)
            let upper = min(points.count - 1, index + window / 2)
            let slice = points[lower...upper]
            let x = slice.map(\.x).reduce(0, +) / Double(slice.count)
            let y = slice.map(\.y).reduce(0, +) / Double(slice.count)

            return TrackedPoint(
                id: point.id,
                timestamp: point.timestamp,
                frameIndex: point.frameIndex,
                x: x,
                y: y,
                confidence: point.confidence
            )
        }
    }
}
