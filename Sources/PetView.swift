import AppKit

enum PetPlay: String, CaseIterable {
    case theft, echo, fishing, petting, bubble, mahjong

    var title: String {
        switch self {
        case .theft: return "小浣熊偷键帽"
        case .echo: return "学我的节奏"
        case .fishing: return "水獭滚轮钓鱼"
        case .petting: return "摸摸搭档的头"
        case .bubble: return "接住按键气泡"
        case .mahjong: return "麻将轴自摸"
        }
    }
}

final class PetView: NSView {
    private struct Bubble {
        let label: String
        let lane: Int
        let born: TimeInterval
    }

    private var bubbles: [Bubble] = []
    private var nextLane = 0
    private let deskScene = DeskScene()
    private let affection = PetAffection()
    private var echo = RhythmEcho()
    private var previewActor: PetCharacter?
    private var actor: PetCharacter { previewActor ?? character }
    var onEchoTap: ((String, Int, Float) -> Void)?
    private var lastTick: TimeInterval?
    private var slipLookUntil: TimeInterval = 0
    private var slipGaze = CGVector.zero
    private var lastLeftPress = -TimeInterval.infinity
    private var lastRightPress = -TimeInterval.infinity
    private var lastKeyPress = -TimeInterval.infinity
    private var keyIndex: Int?
    private var leftKey: Int?
    private var rightKey: Int?
    private var leftStart = CGPoint(x: 133, y: 51)
    private var rightStart = CGPoint(x: 182, y: 51)
    private var lastBreathSample = -TimeInterval.infinity
    private var breath: CGFloat = 0
    private var reducedMotion = false
    private var gaze = CGVector.zero
    private var nextBlink = ProcessInfo.processInfo.systemUptime + 3
    private var blink: CGFloat = 0
    private var activePress = false
    private var combo: (trick: ComboTrick, born: TimeInterval, reducedMotion: Bool)?
    private var cursorSample: (location: NSPoint, time: TimeInterval)?
    private var lastMouseMovement = -TimeInterval.infinity
    private var mouseReach: CGFloat = 0
    private var mouseOffset = CGVector.zero
    private var mouseTarget = CGVector.zero
    private var mousePress: CGFloat = 0

    var character: PetCharacter = .cat {
        didSet {
            resetPlay()
            setAccessibilityLabel("桌宠搭档，\(character.menuTitle)")
            needsDisplay = true
        }
    }

    var moving = false {
        didSet {
            if moving { resetPlay() }
            needsDisplay = true
        }
    }

    var showsBubbles = true {
        didSet {
            if !showsBubbles { clearBubbles() }
        }
    }

    var showsCombos = true {
        didSet {
            if !showsCombos { combo = nil; needsDisplay = true }
        }
    }

    func showCombo(_ trick: ComboTrick, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard showsCombos else { return }
        resetPlay()
        clearBubbles()
        combo = (trick, now, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        needsDisplay = true
    }

    func press(_ label: String, keyCode: Int?, rightHand: Bool, at now: TimeInterval,
               physical: Bool = false, mahjong: Bool = false) {
        let code = keyCode ?? PetKeyboard.code(forDemoLabel: label)
        if physical {
            slipLookUntil = 0
            previewActor = nil
            let canDeal = mahjong && !moving && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            deskScene.keyDown(isReturn: code == 36 || code == 76, mahjong: canDeal, at: now)
        }
        tapPaw(keyIndex: code, rightHand: rightHand, at: now)
        if showsBubbles {
            bubbles.removeAll { $0.lane == nextLane }
            let taken = physical && !moving && combo == nil && deskScene.frame(at: now) == nil &&
                affection.offerBubble(label: label, lane: nextLane, character: actor, at: now)
            if !taken { bubbles.append(Bubble(label: label, lane: nextLane, born: now)) }
            nextLane = (nextLane + 1) % 4
        }
    }

    private func tapPaw(keyIndex: Int?, rightHand: Bool, at now: TimeInterval) {
        if PetKeyboard.usesScreenRightPaw(for: keyIndex, rightHand: rightHand) {
            rightStart = strokePoint(right: true, at: now)
            lastRightPress = now
            rightKey = keyIndex
        } else {
            leftStart = strokePoint(right: false, at: now)
            lastLeftPress = now
            leftKey = keyIndex
        }
        lastKeyPress = now
        self.keyIndex = keyIndex
        needsDisplay = true
    }

    func clearBubbles() {
        affection.clearBubble()
        bubbles.removeAll(keepingCapacity: true)
        needsDisplay = true
    }

    func clearKeyFeedback() {
        resetPlay()
        combo = nil
        clearBubbles()
        keyIndex = nil
        leftKey = nil
        rightKey = nil
        lastKeyPress = -.infinity
        lastLeftPress = -.infinity
        lastRightPress = -.infinity
        needsDisplay = true
    }

    private func resetPlay() {
        deskScene.reset()
        affection.reset()
        echo.cancel()
        previewActor = nil
        lastTick = nil
        slipLookUntil = 0
        needsDisplay = true
    }

    func recordBeat(eligible: Bool, at now: TimeInterval) {
        guard !moving else { return }
        echo.record(eligible: eligible, at: now)
    }

    func scroll(down: CGFloat, at now: TimeInterval) {
        guard !moving, combo == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        deskScene.scroll(down: down, character: actor, at: now)
        if deskScene.frame(at: now) != nil {
            echo.cancel()
            needsDisplay = true
        }
    }

    func preview(_ play: PetPlay, at now: TimeInterval) {
        clearKeyFeedback()
        switch play {
        case .theft:
            previewActor = .raccoon
            deskScene.preview(.theft, at: now)
        case .fishing:
            previewActor = .otter
            deskScene.preview(.fishing, at: now)
        case .mahjong: deskScene.preview(.mahjong, at: now)
        case .echo: echo.startDemo(at: now)
        case .petting: affection.previewTouch(character: actor, at: now)
        case .bubble:
            // A preview is explicitly requested, even when ordinary key labels are hidden.
            _ = affection.offerBubble(label: actor == .cat ? "空格" : "B", lane: nextLane,
                                      character: actor, at: now, force: true)
        }
        needsDisplay = true
    }

    private func updatePlay(cursor: CGPoint, eyes: CGPoint, at now: TimeInterval) {
        guard !moving, combo == nil else { return }
        if let lastTick, now - lastTick > 2 { resetPlay() }
        lastTick = now
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let wasPerforming = deskScene.frame(at: now) != nil || previewActor != nil
        let inReach = hypot(cursor.x - eyes.x, cursor.y - eyes.y) < 95
        deskScene.update(character: actor, cursorNear: inReach,
                         canStartIdle: !reduced && !affection.isActive && !echo.isPlaying, at: now)
        if deskScene.frame(at: now) != nil {
            echo.cancel()
            if affection.isActive { affection.reset() }
            needsDisplay = true
            return
        }
        if wasPerforming {
            previewActor = nil
            needsDisplay = true
        }
        if affection.update(cursor: cursor, eyeCenter: eyes, character: actor, at: now, reducedMotion: reduced) {
            needsDisplay = true
        }
        if affection.isPetting { echo.cancel() }
        if let beat = echo.nextTap(at: now) {
            if beat.isSlip {
                slipGaze = CGVector(dx: PetKeyboard.usesScreenRightPaw(for: beat.keyCode, rightHand: beat.rightHand) ? 0.55 : -0.55, dy: -1)
                slipLookUntil = now + 0.38
            }
            tapPaw(keyIndex: beat.keyCode, rightHand: beat.rightHand, at: now)
            onEchoTap?(beat.label, beat.keyCode, beat.gain)
        }
    }

    func update(at now: TimeInterval, allowPlay: Bool = true) {
        guard let window, window.isVisible else { return }

        let cursor = NSEvent.mouseLocation
        updateMouse(at: now, cursor: cursor)
        if let effect = combo {
            if now - effect.born >= ComboArt.duration { combo = nil }
            needsDisplay = true
        }
        let eyes = CatArt.eyeCenter(mouseReach: mouseReach, character: actor)
        if allowPlay {
            let local = convert(window.convertPoint(fromScreen: cursor), from: nil)
            updatePlay(cursor: local, eyes: eyes, at: now)
        }
        let eyeCenter = window.convertPoint(toScreen: convert(eyes, to: nil))
        let dx = cursor.x - eyeCenter.x
        let dy = cursor.y - eyeCenter.y
        let distance = max(36, hypot(dx, dy))
        let change = CGVector(dx: dx / distance - gaze.dx, dy: dy / distance - gaze.dy)
        if abs(change.dx) + abs(change.dy) > 0.01 {
            gaze.dx += change.dx * 0.28
            gaze.dy += change.dy * 0.28
            needsDisplay = true
        }

        let blinkAge = now - nextBlink
        let newBlink: CGFloat = (0...0.18).contains(blinkAge) ? sin(.pi * blinkAge / 0.18) : 0
        if blinkAge > 0.18 { nextBlink = now + Double.random(in: 3.2...6.0) }
        if newBlink != blink {
            blink = newBlink
            needsDisplay = true
        }

        // A sub-point breath only needs a few fresh idle frames per second.
        if now - lastBreathSample >= 0.20 {
            lastBreathSample = now
            reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let phase = now * (2 * .pi / 4.7)
            let sample = reducedMotion ? 0 : (sin(phase) * 0.91 + sin(2 * phase - 0.4) * 0.09)
            let newBreath = CGFloat((sample * 8).rounded() / 8)
            if newBreath != breath {
                breath = newBreath
                needsDisplay = true
            }
        }

        let hadBubbles = !bubbles.isEmpty
        bubbles.removeAll { now - $0.born >= 0.82 }
        if now - lastKeyPress >= 0.15 { keyIndex = nil }
        if now - lastLeftPress >= 0.22 { leftKey = nil }
        if now - lastRightPress >= 0.22 { rightKey = nil }
        let pressing = now - lastKeyPress < 0.22
        if hadBubbles || pressing || activePress { needsDisplay = true }
        activePress = pressing
    }

    private func updateMouse(at now: TimeInterval, cursor: NSPoint) {
        let previous = cursorSample
        cursorSample = (cursor, now)
        if !moving, let previous, now - previous.time < 0.15 {
            let dx = cursor.x - previous.location.x
            let dy = cursor.y - previous.location.y
            if hypot(dx, dy) >= 0.5 {
                lastMouseMovement = now
                mouseTarget.dx = min(6, max(-6, mouseTarget.dx * 0.72 + dx * 0.45))
                mouseTarget.dy = min(4, max(-4, mouseTarget.dy * 0.72 + dy * 0.45))
            }
        }

        let clickAge = min(
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
        )
        let clicking = (0...0.16).contains(clickAge)
        let recentlyClicked = (0...0.42).contains(clickAge)
        let holding = NSEvent.pressedMouseButtons & 0b11 != 0
        let lastMouseAction = recentlyClicked ? max(lastMouseMovement, now - clickAge) : lastMouseMovement
        // A front-facing pet's right paw is on the left side of the drawing.
        let mousePawKeyAge = now - lastLeftPress
        let typingWithMousePaw = mousePawKeyAge < 0.11 || (mousePawKeyAge < 0.22 && lastLeftPress > lastMouseAction)
        let usingMouse = !moving && !typingWithMousePaw && (now - lastMouseAction < 0.48 || holding)
        if !usingMouse { mouseTarget = .zero }

        let reach = approach(mouseReach, toward: usingMouse ? 1 : 0, fraction: usingMouse ? 0.42 : 0.28)
        let click = approach(mousePress, toward: usingMouse && (clicking || holding) ? 1 : 0, fraction: 0.6)
        let offset = CGVector(
            dx: approach(mouseOffset.dx, toward: mouseTarget.dx, fraction: 0.44),
            dy: approach(mouseOffset.dy, toward: mouseTarget.dy, fraction: 0.44)
        )
        if mouseReach != reach || mouseOffset != offset || mousePress != click {
            mouseReach = reach
            mouseOffset = offset
            mousePress = click
            needsDisplay = true
        }
    }

    private func approach(_ value: CGFloat, toward target: CGFloat, fraction: CGFloat) -> CGFloat {
        let difference = target - value
        return abs(difference) < 0.025 ? target : value + difference * fraction
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        let now = ProcessInfo.processInfo.systemUptime
        let leftAge = now - lastLeftPress
        let rightAge = now - lastRightPress
        let pose = affection.pose(at: now)
        let weight = reducedMotion ? 0 : pawAmount(rightAge - 0.012) - pawAmount(leftAge - 0.012)
        CatArt.draw(
            in: context,
            gaze: now < slipLookUntil ? slipGaze : gaze,
            blink: blink,
            leftPress: pawAmount(leftAge),
            rightPress: pawAmount(rightAge),
            keyIndex: now - lastKeyPress < 0.15 ? keyIndex : nil,
            leftKey: leftKey,
            rightKey: rightKey,
            mouseReach: mouseReach,
            mouseOffset: mouseOffset,
            mousePress: mousePress,
            character: actor, scene: deskScene.frame(at: now), affection: pose, life: breath, typingWeight: weight,
            leftOrigin: leftAge < Self.downstroke ? leftStart : nil,
            rightOrigin: rightAge < Self.downstroke ? rightStart : nil,
            underPaws: { self.affection.drawBubble(in: $0, at: now, mouseReach: self.mouseReach, layer: .beforePaws) }
        )
        for bubble in bubbles {
            PetBubbleArt.draw(label: bubble.label, lane: bubble.lane, age: now - bubble.born, in: context)
        }
        affection.drawBubble(in: context, at: now, mouseReach: mouseReach, layer: .afterPaws)
        if let effect = combo {
            ComboArt.draw(effect.trick, age: now - effect.born, reducedMotion: effect.reducedMotion, in: context)
        }

        if moving {
            NSColor(srgbRed: 0.53, green: 0.86, blue: 0.60, alpha: 0.85).setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 5), xRadius: 21, yRadius: 21)
            outline.lineWidth = 1.5
            outline.setLineDash([4, 4], count: 2, phase: 0)
            outline.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard moving else { return }
        window?.performDrag(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { moving }

    private static let downstroke: TimeInterval = 0.035

    private func pawAmount(_ age: TimeInterval) -> CGFloat {
        guard age >= 0, age < 0.22 else { return 0 }
        let phase = age < Self.downstroke ? age / Self.downstroke : min(1, (0.22 - age) / 0.154)
        return CGFloat(phase * phase * (3 - 2 * phase))
    }

    // A second key can arrive before the first paw has lifted. Begin the new
    // stroke where the toes actually are, then let them return to their perch.
    private func strokePoint(right: Bool, at now: TimeInterval) -> CGPoint {
        let rest = CGPoint(x: right ? 182 : 133, y: 51)
        let age = now - (right ? lastRightPress : lastLeftPress)
        guard age < 0.22 else { return rest }
        let start = age < Self.downstroke ? (right ? rightStart : leftStart) : nil
        return CatArt.keyContact(rest: rest, key: right ? rightKey : leftKey, press: pawAmount(age), origin: start)
    }

}
