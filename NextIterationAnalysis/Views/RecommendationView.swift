import SwiftUI

struct RecommendationView: View {
    let session: LiftSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Weight")
                .font(.headline)

            if let recommendation = session.analysis?.recommendation {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Formatting.weight(recommendation.suggestedWeight, unit: session.unit))
                            .font(.largeTitle.weight(.bold))
                        Text(recommendation.recommendationType.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(recommendation.reason)
                        .foregroundStyle(.secondary)

                    HStack {
                        option("Conservative", recommendation.conservativeOption)
                        option("Aggressive", recommendation.aggressiveOption)
                    }
                }
                .padding()
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func option(_ label: String, _ weight: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Formatting.weight(weight, unit: session.unit))
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
