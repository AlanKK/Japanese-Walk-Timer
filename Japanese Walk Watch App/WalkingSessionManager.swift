import AVFoundation
import Combine
import HealthKit
import SwiftUI
import WatchKit

/// Manages the walking interval session, including timer, speech, haptics,
/// and an HKWorkoutSession for unlimited background execution.
final class WalkingSessionManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var phase: WalkingPhase = .idle
    @Published var secondsRemaining: Int = WalkingPhase.intervalDuration

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
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    // MARK: - Init

    override init() {
        super.init()
    }

    // MARK: - Public API

    func start() {
        requestHealthKitAuthorization { [weak self] success in
            guard success else { return }
            DispatchQueue.main.async {
                self?.beginWorkoutSession()
                self?.beginWalking()
            }
        }
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        endWorkoutSession()
        phase = .idle
        secondsRemaining = WalkingPhase.intervalDuration
    }

    func skipToNextPhase() {
        guard phase != .idle else { return }
        phase = phase.next
        secondsRemaining = WalkingPhase.intervalDuration
        announcePhase()
    }

    // MARK: - Timer

    private func beginWalking() {
        phase = .fastWalk
        secondsRemaining = WalkingPhase.intervalDuration
        announcePhase()
        startTimer()
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard phase != .idle else { return }

        secondsRemaining -= 1
        if secondsRemaining <= 0 {
            phase = phase.next
            secondsRemaining = WalkingPhase.intervalDuration
            announcePhase()
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
        let utterance = AVSpeechUtterance(string: phase.label)
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        synthesizer.speak(utterance)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // MARK: - HealthKit Workout Session

    private func requestHealthKitAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }

        // We only need workout type — we don't read or write any health samples.
        let workoutType = HKQuantityType.workoutType()
        healthStore.requestAuthorization(toShare: [workoutType], read: []) { success, error in
            if let error = error {
                print("HealthKit auth error: \(error)")
            }
            completion(success)
        }
    }

    private func beginWorkoutSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .walking
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore,
                                                configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                          workoutConfiguration: config)

            session.delegate = self
            builder.delegate = self

            self.workoutSession = session
            self.workoutBuilder = builder

            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, error in
                if let error = error {
                    print("Builder begin error: \(error)")
                }
            }
        } catch {
            print("Workout session error: \(error)")
        }
    }

    private func endWorkoutSession() {
        workoutSession?.end()
        workoutBuilder?.endCollection(withEnd: Date()) { [weak self] _, error in
            if let error = error {
                print("Builder end error: \(error)")
            }
            self?.workoutBuilder?.finishWorkout { _, error in
                if let error = error {
                    print("Finish workout error: \(error)")
                }
            }
        }
        workoutSession = nil
        workoutBuilder = nil
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WalkingSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        // No action needed — we just need the session alive for background.
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("Workout session failed: \(error)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WalkingSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}


