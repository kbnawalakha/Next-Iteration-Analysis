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

    static func kalmanSmooth(_ points: [TrackedPoint]) -> [TrackedPoint] {
        guard points.count > 2 else { return points }

        var estimateX = points[0].x
        var estimateY = points[0].y
        var errorX = 1.0
        var errorY = 1.0
        let processNoise = 0.002
        let measurementNoise = 0.018

        return points.map { point in
            errorX += processNoise
            errorY += processNoise

            let gainX = errorX / (errorX + measurementNoise)
            let gainY = errorY / (errorY + measurementNoise)

            estimateX += gainX * (point.x - estimateX)
            estimateY += gainY * (point.y - estimateY)
            errorX *= 1 - gainX
            errorY *= 1 - gainY

            return TrackedPoint(
                id: point.id,
                timestamp: point.timestamp,
                frameIndex: point.frameIndex,
                x: estimateX,
                y: estimateY,
                confidence: point.confidence
            )
        }
    }
}
