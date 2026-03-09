import Combine
import Foundation

struct LabelPair: Identifiable {
    let id: Int
    let fastLabel: String
    let slowLabel: String
    var displayName: String { "\(fastLabel) / \(slowLabel)" }
}

final class IntervalSettings: ObservableObject {
    private static let defaults = UserDefaults.standard

    @Published var intervalMinutes: Int {
        didSet { Self.defaults.set(intervalMinutes, forKey: "intervalMinutes") }
    }
    @Published var intervalSeconds: Int {
        didSet { Self.defaults.set(intervalSeconds, forKey: "intervalSeconds") }
    }
    @Published var startWithFastPhase: Bool {
        didSet { Self.defaults.set(startWithFastPhase, forKey: "startWithFastPhase") }
    }
    @Published var labelPairIndex: Int {
        didSet { Self.defaults.set(labelPairIndex, forKey: "labelPairIndex") }
    }
    @Published var muteChime: Bool {
        didSet { Self.defaults.set(muteChime, forKey: "muteChime") }
    }
    @Published var muteSpeech: Bool {
        didSet { Self.defaults.set(muteSpeech, forKey: "muteSpeech") }
    }

    /// Total interval duration in seconds (minimum 1).
    var totalSeconds: Int {
        max(intervalMinutes * 60 + intervalSeconds, 1)
    }

    var selectedPair: LabelPair {
        IntervalSettings.allPairs[min(labelPairIndex, IntervalSettings.allPairs.count - 1)]
    }

    static let allPairs: [LabelPair] = [
        LabelPair(id: 0, fastLabel: "Fast Walk", slowLabel: "Slow Walk"),
        LabelPair(id: 1, fastLabel: "Hard",       slowLabel: "Easy"),
        LabelPair(id: 2, fastLabel: "Run",         slowLabel: "Walk"),
        LabelPair(id: 3, fastLabel: "Sprint",      slowLabel: "Jog"),
        LabelPair(id: 4, fastLabel: "Work",        slowLabel: "Rest"),
    ]

    init() {
        let mins    = Self.defaults.object(forKey: "intervalMinutes")   == nil ? 4    : Self.defaults.integer(forKey: "intervalMinutes")
        let secs    = Self.defaults.integer(forKey: "intervalSeconds")
        let fast    = Self.defaults.object(forKey: "startWithFastPhase") == nil ? false : Self.defaults.bool(forKey: "startWithFastPhase")
        let pairIdx = Self.defaults.integer(forKey: "labelPairIndex")

        self.intervalMinutes    = mins
        self.intervalSeconds    = secs
        self.startWithFastPhase = fast
        self.labelPairIndex     = min(pairIdx, Self.allPairs.count - 1)
        self.muteChime          = Self.defaults.bool(forKey: "muteChime")
        self.muteSpeech         = Self.defaults.bool(forKey: "muteSpeech")
    }
}
