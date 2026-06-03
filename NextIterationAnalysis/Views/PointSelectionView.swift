import AVKit
import SwiftUI

struct PointSelectionView: View {
    let importedVideo: ImportedLiftVideo?
    let details: LiftDetails
    @StateObject private var viewModel = PointSelectionViewModel()

    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var didInitTrim = false
    @State private var trimPlayer: AVPlayer?
    @State private var selectionFrameImage: UIImage?
    @State private var detectionTask: Task<Void, Never>?
    @State private var analysisQuality: AnalysisQuality = .fast

    private var duration: Double { max(0, importedVideo?.metadata.duration ?? 0) }
    private var selectedStartTime: Double { min(trimStart, trimEnd) }

    /// The [start, end] seconds to analyze, or `nil` for the whole video.
    private var selectedRange: ClosedRange<Double>? {
        guard duration > 0 else { return nil }
        let lower = min(trimStart, trimEnd)
        let upper = max(trimStart, trimEnd)
        guard upper - lower > 0.1 else { return nil }
        let isWholeVideo = lower <= 0.05 && upper >= duration - 0.05
        return isWholeVideo ? nil : lower...upper
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Label("Auto-detected plate center", systemImage: "scope")
                        Spacer()
                        if viewModel.isDetecting {
                            ProgressView()
                        } else {
                            Text(viewModel.confidenceLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(confidenceColor)
                        }
                    }
                    .padding(.horizontal)

                    selectableFrame
                        .frame(height: max(280, proxy.size.height * 0.44))

                    if let autoDetectionMessage = viewModel.autoDetectionMessage {
                        Text(autoDetectionMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    trimControls

                    NavigationLink {
                        AnalysisProgressView(
                            viewModel: AnalysisViewModel(
                                importedVideo: importedVideo,
                                details: details,
                                startPoint: viewModel.selectedPoint,
                                trackingMode: viewModel.trackingMode,
                                usesManualStartPoint: viewModel.isManuallyAdjusted,
                                timeRange: selectedRange,
                                analysisQuality: analysisQuality
                            )
                        )
                    } label: {
                        Label("Analyze Bar Path", systemImage: "waveform.path.ecg")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)

                    Text("The plate is detected automatically. You only need to tap or drag the marker if it landed on the wrong spot — your adjusted position becomes the tracking start.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
        .onAppear {
            if !didInitTrim {
                trimStart = 0
                trimEnd = duration
                didInitTrim = true
            }
            configureTrimPlayer()
            updateTrimStartFrame(selectedStartTime, detectPlate: true)
        }
        .onDisappear {
            detectionTask?.cancel()
            trimPlayer?.pause()
            trimPlayer = nil
        }
        .navigationTitle("Plate Center")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var trimControls: some View {
        if duration > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Analyze segment", systemImage: "scissors")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(timeString(min(trimStart, trimEnd))) – \(timeString(max(trimStart, trimEnd)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                TrimRangeSelector(
                    duration: duration,
                    start: $trimStart,
                    end: $trimEnd,
                    onScrub: { startTime in
                        updateTrimStartFrame(startTime, detectPlate: false)
                    },
                    onScrubEnded: { startTime in
                        updateTrimStartFrame(startTime, detectPlate: true)
                    }
                )

                HStack {
                    Label(timeString(min(trimStart, trimEnd)), systemImage: "arrow.left.to.line")
                    Spacer()
                    Label(timeString(max(trimStart, trimEnd)), systemImage: "arrow.right.to.line")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                Picker("Analysis speed", selection: $analysisQuality) {
                    ForEach(AnalysisQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(selectedRange == nil
                         ? "Analyzing the whole clip. Trim to a single rep for the cleanest, full frame-rate tracking."
                         : "Analyzing only the selected segment at full frame rate.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if selectedRange != nil {
                        Button("Reset") {
                            trimStart = 0
                            trimEnd = duration
                        }
                        .font(.caption2)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func configureTrimPlayer() {
        guard trimPlayer == nil, let videoURL = importedVideo?.videoURL else { return }
        let player = AVPlayer(url: videoURL)
        player.seek(to: CMTime(seconds: selectedStartTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        trimPlayer = player
    }

    private func seekTrimPreview(_ seconds: Double) {
        trimPlayer?.pause()
        trimPlayer?.seek(
            to: CMTime(seconds: min(max(seconds, 0), duration), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func updateTrimStartFrame(_ seconds: Double, detectPlate: Bool) {
        seekTrimPreview(seconds)
        Task {
            await loadSelectionFrame(at: seconds)
        }
        guard detectPlate else { return }
        detectionTask?.cancel()
        detectionTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await viewModel.autoDetect(video: importedVideo, startTime: seconds)
        }
    }

    private func loadSelectionFrame(at seconds: Double) async {
        guard let videoURL = importedVideo?.videoURL else { return }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1200, height: 1200)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            do {
                let cgImage = try generator.copyCGImage(
                    at: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                    actualTime: nil
                )
                return UIImage(cgImage: cgImage)
            } catch {
                return nil
            }
        }.value

        await MainActor.run {
            if let image {
                selectionFrameImage = image
            }
        }
    }

    private var confidenceColor: Color {
        switch viewModel.confidence {
        case 0.9...1.0: return .green
        case 0.75..<0.9: return .blue
        case 0.6..<0.75: return .orange
        default: return .red
        }
    }

    private var selectableFrame: some View {
        GeometryReader { proxy in
            let imageRect = fittedImageRect(in: proxy.size)
            ZStack {
                if let selectionFrameImage {
                    Image(uiImage: selectionFrameImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let thumbnailURL = importedVideo?.thumbnailURL,
                   let uiImage = UIImage(contentsOfFile: thumbnailURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .overlay {
                            Image(systemName: "scope")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }

                Circle()
                    .fill(.red)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .position(
                        x: imageRect.minX + imageRect.width * viewModel.selectedPoint.x,
                        y: imageRect.minY + imageRect.height * viewModel.selectedPoint.y
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                updateSelection(location: location, imageRect: imageRect)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateSelection(location: value.location, imageRect: imageRect)
                    }
            )
        }
        .aspectRatio(importedVideo?.metadata.aspectRatio ?? 16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
    }

    private func fittedImageRect(in container: CGSize) -> CGRect {
        let aspectRatio = importedVideo?.metadata.aspectRatio ?? 16 / 9
        let containerRatio = container.width / max(container.height, 1)

        if containerRatio > aspectRatio {
            let width = container.height * aspectRatio
            return CGRect(x: (container.width - width) / 2, y: 0, width: width, height: container.height)
        } else {
            let height = container.width / max(aspectRatio, 0.001)
            return CGRect(x: 0, y: (container.height - height) / 2, width: container.width, height: height)
        }
    }

    private func updateSelection(location: CGPoint, imageRect: CGRect) {
        let clampedX = min(max(location.x, imageRect.minX), imageRect.maxX)
        let clampedY = min(max(location.y, imageRect.minY), imageRect.maxY)
        viewModel.selectedPoint = NormalizedPoint(
            x: Double((clampedX - imageRect.minX) / max(imageRect.width, 1)),
            y: Double((clampedY - imageRect.minY) / max(imageRect.height, 1))
        )
        viewModel.markManuallyAdjusted()
    }
}

private struct TrimRangeSelector: View {
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    var onScrub: (Double) -> Void
    var onScrubEnded: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let lower = min(start, end)
            let upper = max(start, end)
            let lowerX = xPosition(for: lower, width: width)
            let upperX = xPosition(for: upper, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 8)

                Capsule()
                    .fill(Color.accentColor.opacity(0.36))
                    .frame(width: max(0, upperX - lowerX), height: 8)
                    .offset(x: lowerX)

                trimHandle(systemImage: "arrow.left.to.line")
                    .position(x: lowerX, y: proxy.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                start = clampedSeconds(from: value.location.x, width: width)
                                onScrub(min(start, end))
                            }
                            .onEnded { _ in
                                onScrubEnded(min(start, end))
                            }
                    )

                trimHandle(systemImage: "arrow.right.to.line")
                    .position(x: upperX, y: proxy.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                end = clampedSeconds(from: value.location.x, width: width)
                                onScrub(min(start, end))
                            }
                            .onEnded { _ in
                                onScrubEnded(min(start, end))
                            }
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let seconds = clampedSeconds(from: location.x, width: width)
                if abs(seconds - start) <= abs(seconds - end) {
                    start = seconds
                } else {
                    end = seconds
                }
                let selectedStart = min(start, end)
                onScrub(selectedStart)
                onScrubEnded(selectedStart)
            }
        }
        .frame(height: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyze segment")
    }

    private func trimHandle(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.accentColor))
            .shadow(radius: 2, y: 1)
    }

    private func xPosition(for seconds: Double, width: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(seconds / duration, 0), 1) * width
    }

    private func clampedSeconds(from x: Double, width: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(x / max(width, 1), 0), 1) * duration
    }
}
