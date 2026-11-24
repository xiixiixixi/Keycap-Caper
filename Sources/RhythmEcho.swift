import Foundation

/// Holds only the spacing of a short phrase. The pet chooses its own keys.
struct RhythmEcho {
    struct Tap {
        let keyCode: Int
        let label: String
        let rightHand: Bool
        let gain: Float
        let isSlip: Bool
        let isCorrection: Bool
    }

    private var lastInput: TimeInterval?
    private var gaps: [TimeInterval] = []
    private var nextEligible: TimeInterval = 0
    private var nextBeat: TimeInterval?
    private var beatIndex = 0
    private var correctEnding = false
    private var performances = 0
    var isPlaying: Bool { nextBeat != nil }

    mutating func cancel() {
        lastInput = nil
        nextBeat = nil
        gaps.removeAll(keepingCapacity: true)
    }

    mutating func record(eligible: Bool, at now: TimeInterval) {
        if !eligible || isPlaying || now < nextEligible {
            cancel()
            return
        }
        if let previous = lastInput {
            let gap = now - previous
            if gap <= 0 || gap > 0.78 {
                gaps.removeAll(keepingCapacity: true)
            } else {
                // Keep the beat recognizable even when several keys arrive in one frame.
                gaps.append(max(0.085, gap))
                if gaps.count > 5 { gaps.removeFirst() }
            }
        }
        lastInput = now
    }

    mutating func startDemo(at now: TimeInterval) {
        cancel()
        gaps = [0.19, 0.14, 0.46]
        begin(at: now + 0.18, withCorrection: true)
    }

    mutating func nextTap(at now: TimeInterval) -> Tap? {
        if let lastInput, now - lastInput >= 1.05 {
            if gaps.count >= 3 && now - lastInput <= 1.55 {
                begin(at: now, withCorrection: performances % 4 == 2)
            } else {
                cancel()
            }
        }
        guard let due = nextBeat, now >= due else { return nil }
        guard now - due < 0.5 else { cancel(); return nil }

        let correction = beatIndex > gaps.count
        let slipped = correctEnding && beatIndex == gaps.count
        let handIndex = correction ? gaps.count : beatIndex
        let right = !handIndex.isMultiple(of: 2)
        let accented = beatIndex == 0 || correction || gaps[beatIndex - 1] >= 0.32
        let gain: Float = slipped ? 0.29 : (accented ? 0.66 : 0.48)
        let key: (code: Int, label: String)
        if right { key = slipped ? (40, "K") : (38, "J") }
        else { key = slipped ? (2, "D") : (3, "F") }
        let tap = Tap(keyCode: key.code, label: key.label, rightHand: right,
                      gain: gain, isSlip: slipped, isCorrection: correction)

        if beatIndex < gaps.count {
            nextBeat = now + gaps[beatIndex]
        } else if slipped {
            nextBeat = now + 0.38
        } else {
            cancel()
        }
        beatIndex += 1
        return tap
    }

    private mutating func begin(at now: TimeInterval, withCorrection: Bool) {
        lastInput = nil
        nextBeat = now
        beatIndex = 0
        correctEnding = withCorrection
        performances += 1
        nextEligible = now + 65
    }
}
