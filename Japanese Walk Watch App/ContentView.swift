import SwiftUI

/// Root view that switches between the Start screen and the Active Interval screen.
struct ContentView: View {
    @StateObject private var sessionManager = WalkingSessionManager()

    var body: some View {
        Group {
            if sessionManager.phase == .idle {
                StartView(onStart: { sessionManager.start() })
            } else {
                ActiveIntervalView(sessionManager: sessionManager)
            }
        }
    }
}

#Preview {
    ContentView()
}
