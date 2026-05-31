import SwiftUI

struct SideBySideComparisonView: View {
    let current: LiftSession
    let previous: LiftSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Side-by-Side Comparison")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                comparisonCard(title: "Current", session: current)
                comparisonCard(title: "Previous", session: previous)
            }

            if let previous {
                DeltaRow(
                    label: "Technique",
                    current: current.analysis?.metrics.techniqueScore ?? 0,
                    previous: previous.analysis?.metrics.techniqueScore ?? 0,
                    suffix: "%"
                )
                DeltaRow(
                    label: "Path consistency",
                    current: current.analysis?.metrics.pathConsistencyScore ?? 0,
                    previous: previous.analysis?.metrics.pathConsistencyScore ?? 0,
                    suffix: "%"
                )
            } else {
                ContentUnavailableView("No prior matching lift", systemImage: "rectangle.split.2x1", description: Text("Save another \(current.liftType.displayName.lowercased()) analysis to compare paths, scores, and recommendations."))
            }
        }
    }

    private func comparisonCard(title: String, session: LiftSession?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(session.map { Formatting.weight($0.weight, unit: $0.unit) } ?? "No data")
                .font(.headline)
            Text(session.map { "\($0.reps) reps" } ?? "--")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VelocityBarPathOverlay(path: session?.analysis?.trackedPath ?? [])
                .frame(height: 130)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DeltaRow: View {
    let label: String
    let current: Double
    let previous: Double
    let suffix: String

    var body: some View {
        let delta = current - previous
        HStack {
            Text(label)
            Spacer()
            Text("\(delta >= 0 ? "+" : "")\(delta.clean)\(suffix)")
                .foregroundStyle(delta >= 0 ? .green : .orange)
                .font(.headline)
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
