import SwiftUI

struct TechniqueCritiqueView: View {
    let critique: TechniqueCritique?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Technique Critique")
                .font(.headline)

            Text(critique?.summary ?? "Run an analysis to generate coaching feedback.")
                .foregroundStyle(.secondary)

            if let positives = critique?.positives, !positives.isEmpty {
                section("What Looked Good", positives, icon: "checkmark.circle")
            }

            if let issues = critique?.issues, !issues.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Main Issues")
                        .font(.subheadline.weight(.semibold))
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(issue.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(issue.severity.rawValue.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(color(for: issue.severity))
                            }
                            Text(issue.explanation)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Label(issue.cue, systemImage: "target")
                                .font(.footnote)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            if let focus = critique?.nextSessionFocus, !focus.isEmpty {
                section("Next Session Focus", focus, icon: "list.bullet.clipboard")
            }
        }
    }

    private func section(_ title: String, _ items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: icon)
                    .font(.footnote)
            }
        }
    }

    private func color(for severity: IssueSeverity) -> Color {
        switch severity {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
}
