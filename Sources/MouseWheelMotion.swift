import CoreGraphics
import Foundation

/// Each stroke pushes the tread, then lifts the toes to reset. Input controls
/// cadence and direction; the wheel itself stays still during the return.
struct MouseWheelMotion {
    struct Pose {
        var travel: CGFloat = 0
        var lift: CGFloat = 0
        var turn: CGFloat = 0
        var contact: CGFloat = 0
    }

    private(set) var lastInput = -TimeInterval.infinity
    private var direction: CGFloat = 1
    private var pace: CGFloat = 4
    private var phaseAtInput: CGFloat = 0
    private var stopPhase: CGFloat = 0
    private var startTravel: CGFloat = 0
    private var startTurn: CGFloat = 0
    private var startLift: CGFloat = 0

    mutating func scroll(down distance: CGFloat, at now: TimeInterval) {
        guard distance.isFinite, abs(distance) > 0.01, now >= lastInput else { return }
        let nextDirection: CGFloat = distance > 0 ? 1 : -1
        let phase = phase(at: now)
        let gap = now - lastInput
        if nextDirection != direction || phase >= stopPhase {
            let previous = pose(at: now)
            startTravel = previous.travel
            startLift = previous.lift
            startTurn = previous.turn.truncatingRemainder(dividingBy: 1)
            phaseAtInput = 0
        } else {
            phaseAtInput = phase
        }
        let interval = min(0.12, max(0.026, gap))
        let strength = min(1, abs(distance) / (interval * 430))
        pace = 3.7 + 2.2 * strength
        direction = nextDirection
        lastInput = now
        stopPhase = ceil(phaseAtInput + 0.25)
    }

    private func phase(at now: TimeInterval) -> CGFloat {
        guard lastInput.isFinite else { return 0 }
        return min(stopPhase, phaseAtInput + max(0, now - lastInput) * pace)
    }

    func pose(at now: TimeInterval) -> Pose {
        guard lastInput.isFinite else { return Pose() }
        let elapsed = max(0, now - lastInput)
        let phase = phase(at: now)
        let cycle = floor(phase)
        let t = phase - cycle
        let push = min(1, t / 0.54)
        let pull = max(0, (t - 0.54) / 0.46)
        let drive = push * push * (3 - 2 * push)
        let release = 1 - pull * pull * (3 - 2 * pull)
        let origin = cycle == 0 ? startTravel : 0
        let tip = (origin + (direction - origin) * drive) * release
        return Pose(travel: tip, lift: (cycle == 0 ? startLift * (1 - drive) : 0) + sin(.pi * pull),
                    turn: startTurn + direction * (cycle + drive),
                    contact: min(1, max(0, (0.43 - elapsed) / 0.13)))
    }
}
