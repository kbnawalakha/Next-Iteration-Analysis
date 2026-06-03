import SwiftUI

/// Drives CSV / annotated-video export directly from a `LiftSession` so export
/// works for any session (including saved history), not only immediately after
/// a fresh analysis. Surfaces progress so the button no longer appears to do
/// nothing while a long export runs.
@MainActor
final class SessionExportController: ObservableObject {
    @Published var isExporting = false
    @Published var exportedURL: URL?
    @Published var message: String?

    private let csvExportService = CSVExportService()
    private let annotatedVideoExportService = AnnotatedVideoExportService()

    func exportCSV(session: LiftSession) {
        do {
            let url = try csvExportService.export(session: session)
            exportedURL = url
            message = "CSV ready: \(url.lastPathComponent)"
        } catch {
            message = error.localizedDescription
        }
    }

    func exportVideo(session: LiftSession, colorStyle: BarPathColorStyle) async {
        guard !isExporting else { return }
        isExporting = true
        message = "Exporting annotated video…"
        defer { isExporting = false }
        do {
            let url = try await annotatedVideoExportService.export(session: session, colorStyle: colorStyle)
            exportedURL = url
            message = "Video ready: \(url.lastPathComponent)"
        } catch {
            message = error.localizedDescription
        }
    }
}

struct AnalysisResultsView: View {
    let session: LiftSession
    var analysisViewModel: AnalysisViewModel?

    @State private var colorStyle: BarPathColorStyle = .velocity
    @StateObject private var exporter = SessionExportController()

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    videoSection(minHeight: proxy.size.height * 0.5)
                    statsSection
                }
                .padding()
            }
        }
        .navigationTitle(session.liftType.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Video and export

    private func videoSection(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoOverlayPlayerView(
                session: session,
                colorStyle: $colorStyle,
                minVideoHeight: max(260, minHeight)
            )
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button {
                    exporter.exportCSV(session: session)
                } label: {
                    Label("CSV", systemImage: "tablecells")
                }

                Button {
                    Task { await exporter.exportVideo(session: session, colorStyle: colorStyle) }
                } label: {
                    if exporter.isExporting {
                        ProgressView()
                    } else {
                        Label("Export Video", systemImage: "film")
                    }
                }
                .disabled(exporter.isExporting || session.videoURL == nil)

                if let exportedURL = exporter.exportedURL {
                    ShareLink(item: exportedURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            if let message = exporter.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Stats (reps, metrics, critique, recommendation)

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            MetricsView(session: session)
            TechniqueCritiqueView(critique: session.analysis?.critique)
            RecommendationView(session: session)

            Text("This analysis is an estimate based on video and may be inaccurate. Use it as a training aid, not as medical advice or a replacement for a qualified coach. Stop lifting if you feel pain or unsafe.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

}
