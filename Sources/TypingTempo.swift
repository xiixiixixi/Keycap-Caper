import Foundation

/// Only the timing of physical strokes is needed for the short burst and its recovery.
struct TypingTempo {
    struct Pose: Equatable {
        var urgency: CGFloat = 0
        var impact: CGFloat = 0
        var lean: CGFloat = 0
        var leftLift: CGFloat = 0
        var rightLift: CGFloat = 0
        var rest: CGFloat = 0
        var exhale: CGFloat = 0
    }

    private var lastStroke: TimeInterval?
    private var gap: TimeInterval = 0.27
    private var energy: CGFloat = 0
    private var leftStroke = -TimeInterval.infinity
    private var rightStroke = -TimeInterval.infinity

    mutating func strike(right: Bool, at now: TimeInterval) {
        if let lastStroke, now > lastStroke, now - lastStroke <= 0.46 {
            let elapsed = now - lastStroke
            // Smooth neighboring intervals: one accidental double tap should look ordinary.
            gap += (max(0.045, elapsed) - gap) * 0.34
            let demand = Self.ease((0.265 - gap) / 0.166)
            let response = demand > energy ? 0.50 : 0.30
            energy += (demand - energy) * (1 - exp(-elapsed / response))
        } else {
            self = Self()
        }
        lastStroke = now
        if right { rightStroke = now } else { leftStroke = now }
    }

    // A modifier, demo, or other ordinary tap can take over a paw mid-rebound.
    mutating func releasePaw(right: Bool, at now: TimeInterval) {
        if let lastStroke, now - lastStroke > 0.46 {
            self = Self()
        } else if right {
            rightStroke = -.infinity
        } else {
            leftStroke = -.infinity
        }
    }

    func takesPriority(at now: TimeInterval) -> Bool {
        guard let lastStroke else { return false }
        return energy >= 0.26 && now - lastStroke < 3.25
    }

    func pose(at now: TimeInterval) -> Pose {
        guard let lastStroke, energy > 0.001 else { return Pose() }
        let age = now - lastStroke
        guard age >= 0, age < 3.25 else { return Pose() }
        let hurry = energy * (1 - Self.ease((age - 0.13) / 0.33))
        // Both elbows rise after contact. Each rebound belongs to its own physical stroke.
        func lift(since key: TimeInterval) -> CGFloat {
            let t = now - key
            return hurry * Self.ease((t - 0.049) / 0.057) * (1 - Self.ease((t - 0.106) / 0.121))
        }
        let hit = hurry * Self.ease(age / 0.025) * (1 - Self.ease((age - 0.033) / 0.12))
        let tired = Self.ease((energy - 0.20) / 0.56) * Self.ease((age - 0.25) / 0.46)
            * (1 - Self.ease((age - 2.00) / 1.25))
        let exhale = tired * sin(.pi * Self.ease((age - 0.38) / 1.80))
        return Pose(urgency: hurry, impact: hit, lean: rightStroke > leftStroke ? hit : -hit,
                    leftLift: lift(since: leftStroke), rightLift: lift(since: rightStroke),
                    rest: tired, exhale: exhale)
    }

    private static func ease(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}
