import Foundation

enum WalkingPhase {
    case idle
    case fastWalk
    case slowWalk

    /// The next phase in the alternating cycle.
    var next: WalkingPhase {
        switch self {
        case .idle:      return .fastWalk
        case .fastWalk:  return .slowWalk
        case .slowWalk:  return .fastWalk
        }
    }

    /// Duration of each interval in seconds.
    /// static let intervalDuration: Int = 240
    static let intervalDuration: Int = 5

    /// Display label shown on screen and spoken aloud.
    var label: String {
        switch self {
        case .idle:      return ""
        case .fastWalk:  return "Fast walk"
        case .slowWalk:  return "Slow walk"
        }
    }
}
