import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NavigationLink {
                        VideoImportView()
                    } label: {
                        Label("Analyze New Lift", systemImage: "video.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    summaryGrid

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Progress Trend")
                            .font(.headline)
                        TrendPlaceholderView(sessions: appState.sessions)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent Analyses")
                            .font(.headline)

                        if appState.sessions.isEmpty {
                            ContentUnavailableView("No analyses yet", systemImage: "chart.xyaxis.line", description: Text("Import a lift video to start tracking."))
                        } else {
                            ForEach(appState.sessions) { session in
                                NavigationLink {
                                    AnalysisResultsView(session: session)
                                } label: {
                                    RecentLiftRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Next Iteration Analysis")
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach([LiftType.squat, .benchPress, .deadlift, .overheadPress]) { lift in
                let latest = appState.sessions.first { $0.liftType == lift }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest \(lift.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(latest.map { Formatting.weight($0.weight, unit: $0.unit) } ?? "No data")
                        .font(.title3.weight(.semibold))
                    Text(latest?.createdAt.shortLiftDate ?? "Record a set")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct RecentLiftRow: View {
    let session: LiftSession

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.liftType.displayName)
                    .font(.headline)
                Text("\(Formatting.weight(session.weight, unit: session.unit)) x \(session.reps) reps")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let score = session.analysis?.metrics.techniqueScore {
                Text(Formatting.percent(score))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(score >= 80 ? .green : .orange)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

private struct TrendPlaceholderView: View {
    let sessions: [LiftSession]

    var body: some View {
        Canvas { context, size in
            let values = sessions.prefix(8).reversed().map { $0.analysis?.metrics.techniqueScore ?? 70 }
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                    y: size.height - size.height * CGFloat(value / 100)
                )
            }

            var path = Path()
            if let first = points.first {
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 3)
        }
        .frame(height: 130)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
