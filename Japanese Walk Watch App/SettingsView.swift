import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: IntervalSettings

    private static let secondsOptions = Array(stride(from: 0, through: 55, by: 5))

    var body: some View {
        Form {
            Section("Interval Duration") {
                Picker("Minutes", selection: $settings.intervalMinutes) {
                    ForEach(0...30, id: \.self) { m in
                        Text("\(m) min").tag(m)
                    }
                }
                Picker("Seconds", selection: $settings.intervalSeconds) {
                    ForEach(Self.secondsOptions, id: \.self) { s in
                        Text("\(s) sec").tag(s)
                    }
                }
            }

            Section("Start With") {
                Toggle("\(settings.selectedPair.fastLabel) first", isOn: $settings.startWithFastPhase)
            }

            Section("Labels") {
                Picker(settings.selectedPair.displayName, selection: $settings.labelPairIndex) {
                    ForEach(IntervalSettings.allPairs) { pair in
                        Text(pair.displayName).tag(pair.id)
                    }
                }
            }

            Section("Audio") {
                Toggle("Mute Chime", isOn: $settings.muteChime)
                Toggle("Mute Speech", isOn: $settings.muteSpeech)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView(settings: IntervalSettings())
    }
}
