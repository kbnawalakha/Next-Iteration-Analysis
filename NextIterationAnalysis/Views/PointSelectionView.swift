import SwiftUI

struct PointSelectionView: View {
    let importedVideo: ImportedLiftVideo?
    let details: LiftDetails
    @StateObject private var viewModel = PointSelectionViewModel()

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Detected plate center", systemImage: "scope")
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

            NavigationLink {
                AnalysisProgressView(
                    viewModel: AnalysisViewModel(
                        importedVideo: importedVideo,
                        details: details,
                        startPoint: viewModel.selectedPoint,
                        trackingMode: viewModel.trackingMode
                    )
                )
            } label: {
                Label("Analyze Plate Center Path", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            Text("Confirm the target is centered on the visible weight plate. Drag the marker if the detected center is off.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(.vertical)
        .task {
            await viewModel.autoDetect(video: importedVideo)
        }
        .navigationTitle("Plate Center")
        .navigationBarTitleDisplayMode(.inline)
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
                        x: proxy.size.width * viewModel.selectedPoint.x,
                        y: proxy.size.height * viewModel.selectedPoint.y
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                viewModel.selectedPoint = NormalizedPoint(
                    x: Double(location.x / max(proxy.size.width, 1)),
                    y: Double(location.y / max(proxy.size.height, 1))
                )
                viewModel.markManuallyAdjusted()
            }
        }
        .aspectRatio(importedVideo?.metadata.aspectRatio ?? 16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}
