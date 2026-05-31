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

                Stepper("Reps: \(viewModel.details.reps)", value: $viewModel.details.reps, in: 1...20)

                TextField("RPE optional", value: $viewModel.details.rpe, format: .number)
                    .keyboardType(.decimalPad)
            }

            Section("Notes") {
                TextField("Set notes", text: $viewModel.details.notes, axis: .vertical)
                    .lineLimit(3...5)
            }

            Section {
                NavigationLink("Choose Tracking Point") {
                    PointSelectionView(importedVideo: importedVideo, details: viewModel.details)
                }
                .disabled(!viewModel.canAnalyze)
            }

            if !viewModel.canAnalyze {
                Section {
                    Text("Weight must be positive, reps must be at least 1, and lift type is required.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Lift Details")
    }
}
