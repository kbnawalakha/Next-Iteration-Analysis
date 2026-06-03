import AVKit
import SwiftUI

/// How the bar path line is colored. `velocity` is the documented
/// velocity-colored gradient; `solidGreen` draws a single flat green line.
enum BarPathColorStyle: String, CaseIterable, Identifiable {
    case velocity
    case solidGreen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .velocity: return "Velocity"
        case .solidGreen: return "Solid Green"
        }
    }
}

struct VideoOverlayPlayerView: View {
    let session: LiftSession
    @Binding var colorStyle: BarPathColorStyle
    var minVideoHeight: CGFloat?
    @State private var player: AVPlayer?
    @State private var playbackTime = 0.0
    @State private var timeObserver: Any?

    init(
        session: LiftSession,
        colorStyle: Binding<BarPathColorStyle> = .constant(.velocity),
        minVideoHeight: CGFloat? = nil
    ) {
        self.session = session
        self._colorStyle = colorStyle
        self.minVideoHeight = minVideoHeight
    }

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
                    currentTime: playbackTime,
                    colorStyle: colorStyle
                )
                    .allowsHitTesting(false)
            }
            .aspectRatio(session.videoAspectRatio ?? 16 / 9, contentMode: .fit)
            .frame(minHeight: minVideoHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Picker("Bar path color", selection: $colorStyle) {
                ForEach(BarPathColorStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)

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
            forInterval: CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600),
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
    var colorStyle: BarPathColorStyle = .velocity
    private let calculator = LiftMetricsCalculator()

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let visiblePath = visiblePath(from: path)
                let fullRepSegments = calculator.repSegments(for: path, reps: reps)
                let visibleRepSegments = visibleSegments(from: fullRepSegments)
                let velocityByFrame = Dictionary(uniqueKeysWithValues: calculator.velocitySegments(for: path).map {
                    ($0.to.frameIndex, $0.speed)
                })

                if visibleRepSegments.isEmpty {
                    drawVelocitySegments(calculator.velocitySegments(for: visiblePath), opacity: 1, context: &context, size: size)
                } else {
                    for rep in visibleRepSegments {
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
                            Path(ellipseIn: CGRect(x: bottomPoint.x - 4, y: bottomPoint.y - 4, width: 8, height: 8)),
                            with: .color(.white.opacity(rep.opacity * 0.9)),
                            lineWidth: 1
                        )
                    }
                }

                if let current = visiblePath.last {
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: point(current, in: size).x - 4,
                            y: point(current, in: size).y - 4,
                            width: 8,
                            height: 8
                        )),
                        with: .color(.white)
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func visiblePath(from points: [TrackedPoint]) -> [TrackedPoint] {
        guard let currentTime else { return points }
        return frameAlignedPath(from: points, at: currentTime)
    }

    private func visibleSegments(from segments: [RepPathSegment]) -> [RepPathSegment] {
        guard let currentTime else { return segments }
        return segments.compactMap { segment in
            let visiblePoints = frameAlignedPath(from: segment.points, at: currentTime)
            guard visiblePoints.count > 1, visiblePoints.first?.timestamp ?? 0 <= currentTime else { return nil }
            let active = (visiblePoints.last?.timestamp ?? 0) < (segment.points.last?.timestamp ?? 0)
            return RepPathSegment(
                index: segment.index,
                points: visiblePoints,
                bottom: visiblePoints.max(by: { $0.y < $1.y }) ?? segment.bottom,
                opacity: active ? 1.0 : 0.28
            )
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
                with: .color(Self.pathColor(for: segment.speed, style: colorStyle).opacity(opacity)),
                style: StrokeStyle(lineWidth: opacity >= 1 ? 3 : 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// Maps a normalized speed (0...1) to the bar path color for the chosen style.
    /// `.velocity` reads vivid green while the bar is moving and shifts toward
    /// yellow/orange/red through slow "sticking" points (the documented
    /// velocity-colored path); `.solidGreen` always returns the same green.
    static func pathColor(for normalizedSpeed: Double, style: BarPathColorStyle) -> Color {
        let green = Color(hue: 1.0 / 3.0, saturation: 0.95, brightness: 0.95)
        switch style {
        case .solidGreen:
            return green
        case .velocity:
            let speed = min(1, max(0, normalizedSpeed))
            // Bias toward green so steady reps render predominantly green.
            let eased = pow(speed, 0.6)
            // SwiftUI hue space: 0.0 = red, ~0.166 = yellow, 0.333 = green.
            let hue = eased * (1.0 / 3.0)
            return Color(hue: hue, saturation: 0.95, brightness: 0.95)
        }
    }

    private func point(_ trackedPoint: TrackedPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: trackedPoint.x * size.width, y: trackedPoint.y * size.height)
    }

    private func frameAlignedPath(
        from points: [TrackedPoint],
        at playbackTime: Double
    ) -> [TrackedPoint] {
        guard let first = points.first else { return [] }
        guard points.count > 1 else { return points }

        let timelineTime = playbackTime
        if timelineTime <= first.timestamp {
            return [first]
        }

        guard let nextIndex = points.firstIndex(where: { $0.timestamp >= timelineTime }) else {
            return points
        }

        if nextIndex == 0 {
            return [first]
        }

        let previous = points[nextIndex - 1]
        let next = points[nextIndex]
        let duration = max(next.timestamp - previous.timestamp, 0.0001)
        let progress = min(1, max(0, (timelineTime - previous.timestamp) / duration))
        let interpolated = TrackedPoint(
            id: UUID(),
            timestamp: timelineTime,
            frameIndex: next.frameIndex,
            x: previous.x + (next.x - previous.x) * progress,
            y: previous.y + (next.y - previous.y) * progress,
            confidence: previous.confidence + (next.confidence - previous.confidence) * progress
        )

        var visible = Array(points.prefix(nextIndex))
        visible.append(interpolated)
        return visible
    }

}
