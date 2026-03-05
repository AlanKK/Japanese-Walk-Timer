import SwiftUI

/// Shows the current walking phase label, countdown timer, and a stop button.
struct ActiveIntervalView: View {
    @ObservedObject var sessionManager: WalkingSessionManager

    private var phaseColor: Color {
        sessionManager.phase == .fastWalk ? .green : .orange
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(sessionManager.phase.label)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(phaseColor)

            Text(sessionManager.formattedTime)
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(phaseColor)
                .monospacedDigit()

            Button(action: { sessionManager.stop() }) {
                Text("Stop")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .simultaneousGesture(TapGesture())
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onTapGesture {
            sessionManager.skipToNextPhase()
        }
    }
}

#Preview {
    let manager = WalkingSessionManager()
    ActiveIntervalView(sessionManager: manager)
}
