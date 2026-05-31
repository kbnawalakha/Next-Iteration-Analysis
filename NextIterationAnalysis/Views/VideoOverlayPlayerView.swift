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

                VelocityBarPathOverlay(path: session.analysis?.trackedPath ?? [])
                    .allowsHitTesting(false)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
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
    private let calculator = LiftMetricsCalculator()

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let segments = calculator.velocitySegments(for: path)
                for segment in segments {
                    var segmentPath = Path()
                    segmentPath.move(to: point(segment.from, in: size))
                    segmentPath.addLine(to: point(segment.to, in: size))
                    context.stroke(segmentPath, with: .color(color(for: segment.speed)), lineWidth: 4)
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
