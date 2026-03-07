import SwiftUI

/// The initial screen with a large green-ringed "Start" button.
struct StartView: View {
    @ObservedObject var settings: IntervalSettings
    let onStart: () -> Void

    private var durationText: String {
        String(format: "%d:%02d", settings.intervalMinutes, settings.intervalSeconds)
    }

    var body: some View {
        GeometryReader { geo in
            let size = max(min(geo.size.width, geo.size.height) * 0.65, 0)

            VStack(spacing: 6) {
                Spacer()
                Button(action: onStart) {
                    ZStack {
                        Circle()
                            .stroke(Color.green, lineWidth: 8)
                            .frame(width: size, height: size)

                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: max(size - 16, 0), height: max(size - 16, 0))

                        VStack(spacing: 2) {
                            Text("Start")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            Text(durationText)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.green)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                NavigationLink(destination: SettingsView(settings: settings)) {
                    Label("Settings", systemImage: "gear")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.black)
    }
}

#Preview {
    NavigationStack {
        StartView(settings: IntervalSettings(), onStart: {})
    }
}
