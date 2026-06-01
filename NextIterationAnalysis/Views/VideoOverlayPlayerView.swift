import AVKit
import SwiftUI

struct VideoOverlayPlayerView: View {
    let session: LiftSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Video Overlay")
                .font(.headline)

            ZStack {
                if let videoURL = session.videoURL {
                    VideoPlayer(player: AVPlayer(url: videoURL))
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "play.rectangle")
                                    .font(.largeTitle)
                                Text("Sample overlay preview")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                        }
                }

                VelocityBarPathOverlay(path: session.analysis?.trackedPath ?? [], reps: session.reps)
                    .allowsHitTesting(false)
            }
            .aspectRatio(session.videoAspectRatio ?? 16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Label("Slow playback", systemImage: "tortoise")
                Spacer()
                Label("Frame scrub", systemImage: "slider.horizontal.3")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct VelocityBarPathOverlay: View {
    let path: [TrackedPoint]
    var reps: Int = 1
    private let calculator = LiftMetricsCalculator()

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let repSegments = calculator.repSegments(for: path, reps: reps)
                let velocityByFrame = Dictionary(uniqueKeysWithValues: calculator.velocitySegments(for: path).map {
                    ($0.to.frameIndex, $0.speed)
                })

                if repSegments.isEmpty {
                    drawVelocitySegments(calculator.velocitySegments(for: path), opacity: 1, context: &context, size: size)
                } else {
                    for rep in repSegments {
                        let segments = calculator.velocitySegments(for: rep.points).map { segment in
                            VelocitySegment(
                                from: segment.from,
                                to: segment.to,
                                speed: velocityByFrame[segment.to.frameIndex] ?? segment.speed
                            )
                        }
                        drawVelocitySegments(segments, opacity: rep.opacity, context: &context, size: size)

                        let bottomPoint = point(rep.bottom, in: size)
                        context.stroke(
                            Path(ellipseIn: CGRect(x: bottomPoint.x - 7, y: bottomPoint.y - 7, width: 14, height: 14)),
                            with: .color(.white.opacity(rep.opacity)),
                            lineWidth: 2
                        )
                    }
                }

                if let current = path.last {
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: point(current, in: size).x - 6,
                            y: point(current, in: size).y - 6,
                            width: 12,
                            height: 12
                        )),
                        with: .color(.white)
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func drawVelocitySegments(
        _ segments: [VelocitySegment],
        opacity: Double,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for segment in segments {
            var segmentPath = Path()
            segmentPath.move(to: point(segment.from, in: size))
            segmentPath.addLine(to: point(segment.to, in: size))
            context.stroke(
                segmentPath,
                with: .color(color(for: segment.speed).opacity(opacity)),
                style: StrokeStyle(lineWidth: opacity >= 1 ? 5 : 3, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func point(_ trackedPoint: TrackedPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: trackedPoint.x * size.width, y: trackedPoint.y * size.height)
    }

    private func color(for speed: Double) -> Color {
        switch speed {
        case 0..<0.34: return .red
        case 0.34..<0.67: return .yellow
        default: return .green
        }
    }
}
