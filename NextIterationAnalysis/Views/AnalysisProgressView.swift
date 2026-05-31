import SwiftUI

struct AnalysisProgressView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject var viewModel: AnalysisViewModel

    init(viewModel: AnalysisViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 18) {
            ProgressView(value: progress)
                .padding(.horizontal)

            List {
                ForEach(AnalysisStep.allCases) { step in
                    HStack {
                        Image(systemName: viewModel.completedSteps.contains(step) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(viewModel.completedSteps.contains(step) ? .green : .secondary)
                        Text(step.rawValue)
                        Spacer()
                        if step == viewModel.currentStep, !viewModel.completedSteps.contains(step) {
                            ProgressView()
                        }
                    }
                }
            }

            if let session = viewModel.session {
                NavigationLink("View Results") {
                    AnalysisResultsView(session: session, analysisViewModel: viewModel)
                        .onAppear {
                            appState.save(session)
                        }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Analyzing")
        .task {
            if viewModel.session == nil {
                await viewModel.runAnalysis()
            }
        }
    }

    private var progress: Double {
        Double(viewModel.completedSteps.count) / Double(AnalysisStep.allCases.count)
    }
}
