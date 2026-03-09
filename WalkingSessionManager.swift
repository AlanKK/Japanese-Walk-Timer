import AVFoundation
import Combine
import HealthKit
import SwiftUI
import WatchKit

/// Manages the walking interval session using absolute-date phase tracking.
/// A lightweight HKWorkoutSession keeps the app alive in the background so
/// chime + speech audio plays reliably through AirPods, even when another
/// workout (e.g. Apple Fitness) is running simultaneously on watchOS 11+.
final class WalkingSessionManager: NSObject, ObservableObject {

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
    private var isSpeechSessionActive = false
    private var audioPlayer: AVAudioPlayer?
    private var speechTask: DispatchWorkItem?
    private var phaseEndDate: Date = .distantPast
    private var snapshotDuration: Int = 240
    private var snapshotLabelPair: LabelPair = IntervalSettings.allPairs[0]
    private var snapshotMuteChime: Bool = false
    private var snapshotMuteSpeech: Bool = false

    // MARK: - HealthKit (background execution)

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?

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

    override init() {
        super.init()
        synthesizer.delegate = self
        restoreIfNeeded()
    }

    // MARK: - HealthKit Authorization

    /// Request HealthKit permission. Call once (e.g. on first app launch).
    func requestHealthKitAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let typesToShare: Set<HKSampleType> = [HKWorkoutType.workoutType()]
        healthStore.requestAuthorization(toShare: typesToShare, read: nil) { _, error in
            if let error { print("HealthKit auth error: \(error)") }
        }
    }

    // MARK: - Workout Session (background keep-alive)

    private func startWorkoutSession() {
        guard workoutSession == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .walking
        config.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            session.delegate = self
            workoutSession = session
            session.startActivity(with: Date())
        } catch {
            print("Workout session start error: \(error)")
        }
    }

    private func stopWorkoutSession() {
        workoutSession?.end()
        workoutSession = nil
    }

    // MARK: - Public API

    func start(with settings: IntervalSettings) {
        snapshotDuration = settings.totalSeconds
        snapshotLabelPair = settings.selectedPair
        snapshotMuteChime = settings.muteChime
        snapshotMuteSpeech = settings.muteSpeech
        let startPhase: WalkingPhase = settings.startWithFastPhase ? .fastWalk : .slowWalk
        startWorkoutSession()
        transitionToPhase(startPhase)
        startUITimer()
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        speechTask?.cancel()
        speechTask = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        stopWorkoutSession()
        deactivateAudioSession()
        phase = .idle
        secondsRemaining = 0
        currentPhaseLabel = ""
        clearPersistedState()
    }

    func skipToNextPhase() {
        guard phase != .idle else { return }
        transitionToPhase(phase.next)
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
        if announce { announcePhase() }
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

        if snapshotMuteChime {
            speakPhase(phase)
            return
        }

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
        guard !snapshotMuteSpeech else {
            deactivateAudioSession()
            return
        }
        let utterance = AVSpeechUtterance(string: labelForPhase(phase))
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeechSessionActive = true
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
            try session.setCategory(.playback, options: [.mixWithOthers, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
        } catch {
            print("Audio session deactivation error: \(error)")
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
        startWorkoutSession()
        startUITimer()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension WalkingSessionManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        guard isSpeechSessionActive else { return }
        isSpeechSessionActive = false
        deactivateAudioSession()
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WalkingSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // No action needed — the session exists solely for background execution.
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("Workout session error: \(error)")
    }
}


