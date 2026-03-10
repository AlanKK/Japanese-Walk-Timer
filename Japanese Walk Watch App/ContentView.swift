import SwiftUI

/// Root view that switches between the Start screen and the Active Interval screen.
struct ContentView: View {
    @EnvironmentObject private var sessionManager: WalkingSessionManager
    @StateObject private var settings = IntervalSettings()

    var body: some View {
        NavigationStack {
            if let summary = sessionManager.sessionSummary {
                SummaryView(summary: summary, onDismiss: { sessionManager.sessionSummary = nil })
            } else if sessionManager.phase == .idle {
                StartView(settings: settings, onStart: { sessionManager.start(with: settings) })
            } else {
                ActiveIntervalView(sessionManager: sessionManager)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WalkingSessionManager())
}

