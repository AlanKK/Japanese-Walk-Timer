import SwiftUI

/// Shows the current walking phase label, countdown timer, and a stop button.
struct ActiveIntervalView: View {
    @ObservedObject var sessionManager: WalkingSessionManager

    private var phaseColor: Color {
        sessionManager.phase == .fastWalk ? .green : Color(red: 1.0, green: 0.75, blue: 0.1)
    }

    private var progress: Double {
        guard sessionManager.currentPhaseTotalSeconds > 0 else { return 1 }
        return Double(sessionManager.secondsRemaining) / Double(sessionManager.currentPhaseTotalSeconds)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                Text(sessionManager.currentPhaseLabel)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(phaseColor)

                // Improvement 1: circular progress ring around the timer
                ZStack {
                    Circle()
                        .stroke(phaseColor.opacity(0.2), lineWidth: 5)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(phaseColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)

                    // Improvement 6: larger timer + rounded font design
                    Text(sessionManager.formattedTime)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(phaseColor)
                        .monospacedDigit()
                }
                .frame(width: 120, height: 120)

                Button(action: { sessionManager.stop() }) {
                    Text("Stop")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
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
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onTapGesture {
            sessionManager.skipToNextPhase()
        }
    }
}

#Preview {
    let manager = WalkingSessionManager()
    ActiveIntervalView(sessionManager: manager)
}
