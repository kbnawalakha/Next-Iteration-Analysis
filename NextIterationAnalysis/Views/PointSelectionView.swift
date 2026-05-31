import SwiftUI

struct PointSelectionView: View {
    let importedVideo: ImportedLiftVideo?
    let details: LiftDetails
    @StateObject private var viewModel = PointSelectionViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Picker("Tracking", selection: $viewModel.trackingMode) {
                ForEach(TrackingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: viewModel.trackingMode) { mode in
                if mode == .automaticPlateDetection {
                    Task { await viewModel.autoDetect(video: importedVideo) }
                }
            }

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
                Label("Analyze", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            Text("Analysis is approximate. Poor lighting, camera movement, or occlusion can reduce accuracy.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(.vertical)
        .navigationTitle("Track Bar")
        .navigationBarTitleDisplayMode(.inline)
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
                if viewModel.trackingMode == .automaticPlateDetection {
                    viewModel.autoDetectionMessage = "Auto point corrected manually."
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}
