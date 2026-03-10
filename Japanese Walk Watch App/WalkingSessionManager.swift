import AVFoundation
import Combine
import CoreMotion
import SwiftUI
import WatchKit

// MARK: - Session Summary

struct SessionSummary {
    let totalTime: TimeInterval
    let fastIntervalCount: Int
    let slowIntervalCount: Int
    let fastLabel: String
    let slowLabel: String
    let distanceMeters: Double?
    let stepCount: Int?

    var formattedTotalTime: String {
        let t = Int(totalTime)
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    var formattedDistance: String? {
        guard let meters = distanceMeters else { return nil }
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 2
        return formatter.string(from: measurement)
    }

    var formattedStepCount: String? {
        guard let count = stepCount else { return nil }
        return count.formatted()
    }
}

/// Manages the walking interval session using absolute-date phase tracking.
/// A WKExtendedRuntimeSession keeps the app alive in the background so
/// chime + speech audio plays reliably through AirPods without interfering
/// with an Apple Fitness workout running simultaneously.
final class WalkingSessionManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var phase: WalkingPhase = .idle
    @Published var secondsRemaining: Int = 0
    @Published var currentPhaseLabel: String = ""
    @Published var sessionSummary: SessionSummary?

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
    private var sessionStartDate: Date?
    private var completedFastIntervals: Int = 0
    private var completedSlowIntervals: Int = 0
    private let pedometer = CMPedometer()
    private var snapshotDuration: Int = 240
    private var snapshotLabelPair: LabelPair = IntervalSettings.allPairs[0]
    private var snapshotMuteChime: Bool = false
    private var snapshotMuteSpeech: Bool = false

    // MARK: - Extended Runtime Session (background keep-alive)

    private var extendedSession: WKExtendedRuntimeSession?

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

    // MARK: - Extended Runtime Session

    private func startExtendedSession() {
        guard extendedSession?.state != .running else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        extendedSession = session
        session.start()
    }

    private func stopExtendedSession() {
        extendedSession?.invalidate()
        extendedSession = nil
    }

    // MARK: - Public API

    func start(with settings: IntervalSettings) {
        snapshotDuration = settings.totalSeconds
        snapshotLabelPair = settings.selectedPair
        snapshotMuteChime = settings.muteChime
        snapshotMuteSpeech = settings.muteSpeech
        sessionStartDate = Date()
        completedFastIntervals = 0
        completedSlowIntervals = 0
        sessionSummary = nil
        let startPhase: WalkingPhase = settings.startWithFastPhase ? .fastWalk : .slowWalk
        startExtendedSession()
        transitionToPhase(startPhase)
        startUITimer()
    }

    func stop() {
        // Capture timing before clearing state
        let elapsed = sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
        let capturedStartDate = sessionStartDate
        let capturedFast = completedFastIntervals
        let capturedSlow = completedSlowIntervals
        let capturedFastLabel = snapshotLabelPair.fastLabel
        let capturedSlowLabel = snapshotLabelPair.slowLabel

        // Show summary immediately; pedometer data will fill in asynchronously
        sessionSummary = SessionSummary(
            totalTime: elapsed,
            fastIntervalCount: capturedFast,
            slowIntervalCount: capturedSlow,
            fastLabel: capturedFastLabel,
            slowLabel: capturedSlowLabel,
            distanceMeters: nil,
            stepCount: nil
        )

        // Query CoreMotion pedometer for the session window
        if let start = capturedStartDate,
           CMPedometer.isStepCountingAvailable() {
            pedometer.queryPedometerData(from: start, to: Date()) { [weak self] data, error in
                guard let self, let data, error == nil else { return }
                DispatchQueue.main.async {
                    self.sessionSummary = SessionSummary(
                        totalTime: elapsed,
                        fastIntervalCount: capturedFast,
                        slowIntervalCount: capturedSlow,
                        fastLabel: capturedFastLabel,
                        slowLabel: capturedSlowLabel,
                        distanceMeters: data.distance?.doubleValue,
                        stepCount: data.numberOfSteps.intValue
                    )
                }
            }
        }

        timerCancellable?.cancel()
        timerCancellable = nil
        speechTask?.cancel()
        speechTask = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        stopExtendedSession()
        deactivateAudioSession()
        phase = .idle
        secondsRemaining = 0
        currentPhaseLabel = ""
        sessionStartDate = nil
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
        switch newPhase {
        case .fastWalk: completedFastIntervals += 1
        case .slowWalk: completedSlowIntervals += 1
        case .idle: break
        }
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
            if !isSpeechSessionActive { relaxAudioSession() }
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
            try session.setCategory(.playback, options: [.duckOthers, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    /// After an announcement, unduck other audio but keep the session active
    /// so the Bluetooth route to AirPods is not released between intervals.
    private func relaxAudioSession() {
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playback, options: [.mixWithOthers, .allowBluetoothA2DP])
        } catch {
            print("Audio session relax error: \(error)")
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
        startExtendedSession()
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
        relaxAudioSession()
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WalkingSessionManager: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {}

    func extendedRuntimeSessionWillExpire(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        // Restart the session before it expires so background execution continues.
        extendedSession = nil
        startExtendedSession()
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        extendedSession = nil
        if let error { print("Extended session error: \(error)") }
    }
}


