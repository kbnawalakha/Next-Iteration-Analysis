import SwiftUI

struct MetricsView: View {
    let session: LiftSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("Weight", Formatting.weight(session.weight, unit: session.unit))
                metric("Reps", "\(session.reps)")
                metric("Vertical", meter(session.analysis?.metrics.verticalDisplacement))
                metric("Horizontal", meter(session.analysis?.metrics.horizontalDisplacement))
                metric("Avg Speed", speed(session.analysis?.metrics.averageVelocity))
                metric("Peak Speed", speed(session.analysis?.metrics.peakVelocity))
                metric("Path Score", Formatting.percent(session.analysis?.metrics.pathConsistencyScore ?? 0))
                metric("Technique", Formatting.percent(session.analysis?.metrics.techniqueScore ?? 0))
                metric("Confidence", Formatting.percent(session.analysis?.confidenceScore ?? 0))
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func meter(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return "\(String(format: "%.2f", value)) norm"
    }

    private func speed(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return "\(String(format: "%.2f", value))/s"
    }
}
