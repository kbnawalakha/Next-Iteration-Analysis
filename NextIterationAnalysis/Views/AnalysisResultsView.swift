import SwiftUI

struct AnalysisResultsView: View {
    let session: LiftSession
    var analysisViewModel: AnalysisViewModel?

    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = "results"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("View", selection: $selectedTab) {
                    Text("Results").tag("results")
                    Text("Compare").tag("compare")
                }
                .pickerStyle(.segmented)

                if selectedTab == "compare" {
                    SideBySideComparisonView(current: session, previous: previousComparableSession)
                } else {
                    resultsContent
                }
            }
            .padding()
        }
        .navigationTitle(session.liftType.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var resultsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VideoOverlayPlayerView(session: session)

            MetricsView(session: session)
            TechniqueCritiqueView(critique: session.analysis?.critique)
            RecommendationView(session: session)

            VStack(alignment: .leading, spacing: 10) {
                Text("Export")
                    .font(.headline)

                HStack {
                    Button {
                        analysisViewModel?.exportCSV()
                    } label: {
                        Label("CSV", systemImage: "tablecells")
                    }

                    Button {
                        Task { await analysisViewModel?.exportAnnotatedVideo() }
                    } label: {
                        Label("Video", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.bordered)

                if let exportedURL = analysisViewModel?.exportedURL {
                    ShareLink(item: exportedURL) {
                        Label("Share Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if analysisViewModel == nil {
                    Text("Open exports immediately after a new analysis. Saved sessions keep the metrics and path.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = analysisViewModel?.exportMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text("This analysis is an estimate based on video and may be inaccurate. Use it as a training aid, not as medical advice or a replacement for a qualified coach. Stop lifting if you feel pain or unsafe.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var previousComparableSession: LiftSession? {
        appState.sessions.first { $0.id != session.id && $0.liftType == session.liftType }
    }
}
