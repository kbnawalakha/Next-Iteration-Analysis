import SwiftUI

struct LiftDetailsView: View {
    let importedVideo: ImportedLiftVideo?
    @StateObject private var viewModel = LiftDetailsViewModel()

    var body: some View {
        Form {
            Section("Lift") {
                Picker("Lift type", selection: $viewModel.details.liftType) {
                    ForEach(LiftType.allCases) { lift in
                        Text(lift.displayName).tag(lift)
                    }
                }

                Picker("Goal", selection: $viewModel.details.goal) {
                    ForEach(TrainingGoal.allCases) { goal in
                        Text(goal.displayName).tag(goal)
                    }
                }
            }

            Section("Load") {
                TextField("Weight", value: $viewModel.details.weight, format: .number)
                    .keyboardType(.decimalPad)

                Picker("Unit", selection: $viewModel.details.unit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                // Reps are no longer entered by hand — they're counted from the
                // bar path during analysis and shown on the results screen.
                LabeledContent("Reps") {
                    Label("Counted automatically", systemImage: "wand.and.stars")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("RPE optional", value: $viewModel.details.rpe, format: .number)
                    .keyboardType(.decimalPad)
            }

            Section("Notes") {
                TextField("Set notes", text: $viewModel.details.notes, axis: .vertical)
                    .lineLimit(3...5)
            }

            Section {
                NavigationLink("Confirm Plate Center") {
                    PointSelectionView(importedVideo: importedVideo, details: viewModel.details)
                }
                .disabled(!viewModel.canAnalyze)
            }

            if !viewModel.canAnalyze {
                Section {
                    Text("Enter a positive weight and choose a lift type. Reps are detected automatically from the video.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Lift Details")
    }
}
