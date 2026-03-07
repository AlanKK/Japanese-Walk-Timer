import Foundation

enum WalkingPhase: String {
    case idle = "idle"
    case fastWalk = "fastWalk"
    case slowWalk = "slowWalk"

    /// The next phase in the alternating cycle.
    var next: WalkingPhase {
        switch self {
        case .idle:      return .fastWalk
        case .fastWalk:  return .slowWalk
        case .slowWalk:  return .fastWalk
        }
    }
}
