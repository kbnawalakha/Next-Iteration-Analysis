import SwiftUI

struct PointSelectionView: View {
    let importedVideo: ImportedLiftVideo?
    let details: LiftDetails
    @StateObject private var viewModel = PointSelectionViewModel()

    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var didInitTrim = false
    @State private var trimThumbnails: [UIImage] = []

    private var duration: Double { max(0, importedVideo?.metadata.duration ?? 0) }

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
                        timeRange: selectedRange
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
        .padding(.vertical)
        .onAppear {
            if !didInitTrim {
                trimStart = 0
                trimEnd = duration
                didInitTrim = true
            }
        }
        .task {
            await viewModel.autoDetect(video: importedVideo)
        }
        .task {
            if let url = importedVideo?.videoURL {
                trimThumbnails = await VideoFrameExtractor().thumbnails(from: url, count: 8)
            }
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

                filmstrip

                HStack(spacing: 8) {
                    Text("Start").font(.caption).foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
                    Slider(value: $trimStart, in: 0...duration)
                }
                HStack(spacing: 8) {
                    Text("End").font(.caption).foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
                    Slider(value: $trimEnd, in: 0...duration)
                }

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

    // Visual filmstrip of the clip so the segment is chosen against real frames
    // rather than a blind slider. The selected range is highlighted.
    @ViewBuilder
    private var filmstrip: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let lowerFraction = duration > 0 ? min(trimStart, trimEnd) / duration : 0
            let upperFraction = duration > 0 ? max(trimStart, trimEnd) / duration : 1
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if trimThumbnails.isEmpty {
                        Rectangle().fill(Color.secondary.opacity(0.15))
                    } else {
                        ForEach(Array(trimThumbnails.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: width / CGFloat(trimThumbnails.count), height: 60)
                                .clipped()
                        }
                    }
                }

                Rectangle()
                    .fill(.black.opacity(0.55))
                    .frame(width: max(0, lowerFraction * width))
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .frame(width: max(0, (1 - upperFraction) * width))
                    .offset(x: upperFraction * width)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: max(0, (upperFraction - lowerFraction) * width))
                    .offset(x: lowerFraction * width)
            }
            .frame(height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: 60)
    }

    private func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
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
                if let thumbnailURL = importedVideo?.thumbnailURL,
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
        .padding(.horizontal)
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
