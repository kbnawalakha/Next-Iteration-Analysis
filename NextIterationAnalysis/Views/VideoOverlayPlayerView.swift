import AVKit
import SwiftUI

struct VideoOverlayPlayerView: View {
    let session: LiftSession
    @State private var player: AVPlayer?
    @State private var playbackTime = 0.0
    @State private var timeObserver: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Video Overlay")
                .font(.headline)

            ZStack {
                if session.videoURL != nil {
                    VideoPlayer(player: player)
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

                VelocityBarPathOverlay(
                    path: session.analysis?.trackedPath ?? [],
                    reps: session.reps,
                    currentTime: playbackTime
                )
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
        .onAppear(perform: configurePlayer)
        .onDisappear(perform: tearDownPlayer)
    }

    private func configurePlayer() {
        guard player == nil, let videoURL = session.videoURL else { return }
        let newPlayer = AVPlayer(url: videoURL)
        let observer = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            queue: .main
        ) { time in
            playbackTime = time.seconds.isFinite ? time.seconds : 0
        }
        player = newPlayer
        timeObserver = observer
    }

    private func tearDownPlayer() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player = nil
    }
}

struct VelocityBarPathOverlay: View {
    let path: [TrackedPoint]
    var reps: Int = 1
    var currentTime: Double?
    private let calculator = LiftMetricsCalculator()

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let visiblePath = visiblePath()
                let repSegments = calculator.repSegments(for: visiblePath, reps: reps)
                let velocityByFrame = Dictionary(uniqueKeysWithValues: calculator.velocitySegments(for: visiblePath).map {
                    ($0.to.frameIndex, $0.speed)
                })

                if repSegments.isEmpty {
                    drawVelocitySegments(calculator.velocitySegments(for: visiblePath), opacity: 1, context: &context, size: size)
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

                if let current = visiblePath.last {
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

    private func visiblePath() -> [TrackedPoint] {
        guard let currentTime else { return path }
        let visible = path.filter { $0.timestamp <= currentTime }
        if visible.count > 1 { return visible }
        return Array(path.prefix(min(path.count, 2)))
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
                with: .color((opacity >= 1 ? Color.white : Color.gray).opacity(opacity)),
                style: StrokeStyle(lineWidth: opacity >= 1 ? 6 : 3, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func point(_ trackedPoint: TrackedPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: trackedPoint.x * size.width, y: trackedPoint.y * size.height)
    }

}
