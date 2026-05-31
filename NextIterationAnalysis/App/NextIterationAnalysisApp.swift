import SwiftUI

@main
struct NextIterationAnalysisApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appState)
                .task {
                    await appState.loadHistory()
                }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var sessions: [LiftSession] = []

    private let storage = LocalStorageService()

    func loadHistory() async {
        sessions = (try? storage.loadSessions()) ?? SampleData.sessions
    }

    func save(_ session: LiftSession) {
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0)
        try? storage.saveSessions(sessions)
    }
}
