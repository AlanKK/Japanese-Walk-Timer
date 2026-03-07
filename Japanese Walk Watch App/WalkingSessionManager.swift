import AVFoundation
import Combine
import SwiftUI
import WatchKit

/// Manages the walking interval session using absolute-date phase tracking.
/// Background delivery uses WKApplicationRefreshBackgroundTask so the user
/// can run any other workout app simultaneously.
final class WalkingSessionManager: ObservableObject {

    // MARK: - Published State

    @Published var phase: WalkingPhase = .idle
    @Published var secondsRemaining: Int = 0
    @Published var currentPhaseLabel: String = ""

    // MARK: - Formatted Time

    var formattedTime: String {
        let m = secondsRemaining / 60
        let s = secondsRemaining % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Private Properties

    private var timerCancellable: AnyCancellable?
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var speechTask: DispatchWorkItem?
    private var phaseEndDate: Date = .distantPast
    private var snapshotDuration: Int = 240
    private var snapshotLabelPair: LabelPair = IntervalSettings.allPairs[0]

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let isRunning     = "session.isRunning"
        static let phaseEndDate  = "session.phaseEndDate"
        static let currentPhase  = "session.currentPhase"
        static let phaseDuration = "session.phaseDuration"
        static let fastLabel     = "session.fastLabel"
        static let slowLabel     = "session.slowLabel"
    }

    // MARK: - Init

    init() {
        restoreIfNeeded()
    }

    // MARK: - Public API

    func start(with settings: IntervalSettings) {
        snapshotDuration = settings.totalSeconds
        snapshotLabelPair = settings.selectedPair
        let startPhase: WalkingPhase = settings.startWithFastPhase ? .fastWalk : .slowWalk
        transitionToPhase(startPhase)
        startUITimer()
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        speechTask?.cancel()
        speechTask = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        phase = .idle
        secondsRemaining = 0
        currentPhaseLabel = ""
        clearPersistedState()
    }

    func skipToNextPhase() {
        guard phase != .idle else { return }
        transitionToPhase(phase.next)
    }

    /// Called by the app's .backgroundTask handler when a scheduled refresh fires.
    @MainActor
    func handleBackgroundRefresh() async {
        guard phase != .idle else { return }
        var transitioned = false
        while Date() >= phaseEndDate {
            transitionToPhase(phase.next, announce: false)
            transitioned = true
        }
        if transitioned {
            WKInterfaceDevice.current().play(.notification)
        } else {
            // Task fired early — re-schedule for the actual end time.
            scheduleNextBackgroundRefresh()
        }
    }

    // MARK: - Timer

    private func startUITimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard phase != .idle else { return }
        let remaining = Int(phaseEndDate.timeIntervalSinceNow.rounded(.up))
        if remaining <= 0 {
            transitionToPhase(phase.next)
        } else {
            secondsRemaining = remaining
        }
    }

    // MARK: - Phase Transition

    private func transitionToPhase(_ newPhase: WalkingPhase, announce: Bool = true) {
        phase = newPhase
        phaseEndDate = Date().addingTimeInterval(TimeInterval(snapshotDuration))
        secondsRemaining = snapshotDuration
        currentPhaseLabel = labelForPhase(newPhase)
        persistState()
        scheduleNextBackgroundRefresh()
        if announce { announcePhase() }
    }

    // MARK: - Background Task Scheduling

    private func scheduleNextBackgroundRefresh() {
        guard phase != .idle else { return }
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: phaseEndDate,
            userInfo: nil
        ) { error in
            if let error = error {
                print("Background refresh schedule error: \(error)")
            }
        }
    }

    // MARK: - Alerts (Haptic + Chime + Speech)

    private func announcePhase() {
        // 1. Haptic
        WKInterfaceDevice.current().play(.notification)

        // 2. Chime then speech
        configureAudioSession()
        playChimeThenSpeak(for: phase)
    }

    private func playChimeThenSpeak(for phase: WalkingPhase) {
        // Cancel any speech scheduled for a previous phase.
        speechTask?.cancel()
        speechTask = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        let fileName = phase == .fastWalk ? "chime up" : "chime down"
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "wav") else {
            speakPhase(phase)
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            let duration = audioPlayer?.duration ?? 0
            audioPlayer?.play()

            // Schedule speech to fire when the chime ends.
            let task = DispatchWorkItem { [weak self] in self?.speakPhase(phase) }
            speechTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + max(duration - 0.3, 0), execute: task)
        } catch {
            print("Audio player error: \(error)")
            speakPhase(phase)
        }
    }

    private func speakPhase(_ phase: WalkingPhase) {
        let utterance = AVSpeechUtterance(string: labelForPhase(phase))
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        synthesizer.speak(utterance)
    }

    private func labelForPhase(_ phase: WalkingPhase) -> String {
        switch phase {
        case .idle:      return ""
        case .fastWalk:  return snapshotLabelPair.fastLabel
        case .slowWalk:  return snapshotLabelPair.slowLabel
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // MARK: - State Persistence

    private func persistState() {
        let d = UserDefaults.standard
        d.set(true,                                forKey: Keys.isRunning)
        d.set(phaseEndDate.timeIntervalSince1970,  forKey: Keys.phaseEndDate)
        d.set(phase.rawValue,                      forKey: Keys.currentPhase)
        d.set(snapshotDuration,                    forKey: Keys.phaseDuration)
        d.set(snapshotLabelPair.fastLabel,         forKey: Keys.fastLabel)
        d.set(snapshotLabelPair.slowLabel,         forKey: Keys.slowLabel)
    }

    private func clearPersistedState() {
        let d = UserDefaults.standard
        d.removeObject(forKey: Keys.isRunning)
        d.removeObject(forKey: Keys.phaseEndDate)
        d.removeObject(forKey: Keys.currentPhase)
        d.removeObject(forKey: Keys.phaseDuration)
        d.removeObject(forKey: Keys.fastLabel)
        d.removeObject(forKey: Keys.slowLabel)
    }

    private func restoreIfNeeded() {
        let d = UserDefaults.standard
        guard d.bool(forKey: Keys.isRunning),
              let rawPhase = d.string(forKey: Keys.currentPhase),
              let restoredPhase = WalkingPhase(rawValue: rawPhase),
              restoredPhase != .idle else { return }

        let endTimestamp = d.double(forKey: Keys.phaseEndDate)
        guard endTimestamp > 0 else { return }

        let restoredEndDate = Date(timeIntervalSince1970: endTimestamp)
        guard restoredEndDate > Date() else {
            clearPersistedState()
            return
        }

        snapshotDuration = d.integer(forKey: Keys.phaseDuration)
        let fastLabel = d.string(forKey: Keys.fastLabel) ?? "Fast Walk"
        let slowLabel = d.string(forKey: Keys.slowLabel) ?? "Slow Walk"
        snapshotLabelPair = LabelPair(id: 0, fastLabel: fastLabel, slowLabel: slowLabel)
        phase = restoredPhase
        phaseEndDate = restoredEndDate
        secondsRemaining = max(0, Int(restoredEndDate.timeIntervalSinceNow))
        currentPhaseLabel = labelForPhase(restoredPhase)
        startUITimer()
    }
}


