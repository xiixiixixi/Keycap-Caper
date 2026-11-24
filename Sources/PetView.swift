import AppKit

final class PetView: NSView {
    private struct Bubble {
        let label: String
        let lane: Int
        let born: TimeInterval
    }

    private var bubbles: [Bubble] = []
    private var nextLane = 0
    private var lastLeftPress = -TimeInterval.infinity
    private var lastRightPress = -TimeInterval.infinity
    private var lastKeyPress = -TimeInterval.infinity
    private var keyIndex: Int?
    private var leftKey: Int?
    private var rightKey: Int?
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
            setAccessibilityLabel("桌宠搭档，\(character.menuTitle)")
            needsDisplay = true
        }
    }

    var moving = false {
        didSet { needsDisplay = true }
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
        clearBubbles()
        combo = (trick, now, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        needsDisplay = true
    }

    func press(_ label: String, keyCode: Int?, rightHand: Bool, at now: TimeInterval) {
        let keyIndex = keyCode ?? PetKeyboard.code(forDemoLabel: label)
        if PetKeyboard.usesScreenRightPaw(for: keyIndex, rightHand: rightHand) {
            lastRightPress = now
            rightKey = keyIndex
        } else {
            lastLeftPress = now
            leftKey = keyIndex
        }
        lastKeyPress = now
        self.keyIndex = keyIndex
        if showsBubbles {
            bubbles.removeAll { $0.lane == nextLane }
            bubbles.append(Bubble(label: label, lane: nextLane, born: now))
            nextLane = (nextLane + 1) % 4
        }
        needsDisplay = true
    }

    func clearBubbles() {
        guard !bubbles.isEmpty else { return }
        bubbles.removeAll(keepingCapacity: true)
        needsDisplay = true
    }

    func clearKeyFeedback() {
        guard lastKeyPress.isFinite || !bubbles.isEmpty || combo != nil else { return }
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

    func update(at now: TimeInterval) {
        guard let window, window.isVisible else { return }

        let cursor = NSEvent.mouseLocation
        updateMouse(at: now, cursor: cursor)
        if let effect = combo {
            if now - effect.born >= ComboArt.duration { combo = nil }
            needsDisplay = true
        }
        let eyes = CatArt.eyeCenter(mouseReach: mouseReach, character: character)
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
        CatArt.draw(
            in: context,
            gaze: gaze,
            blink: blink,
            leftPress: pawAmount(now - lastLeftPress),
            rightPress: pawAmount(now - lastRightPress),
            keyIndex: now - lastKeyPress < 0.15 ? keyIndex : nil,
            leftKey: leftKey,
            rightKey: rightKey,
            mouseReach: mouseReach,
            mouseOffset: mouseOffset,
            mousePress: mousePress,
            character: character
        )
        for bubble in bubbles {
            draw(bubble, age: now - bubble.born, in: context)
        }
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

    private func pawAmount(_ age: TimeInterval) -> CGFloat {
        guard age < 0.22 else { return 0 }
        return CGFloat(min(age / 0.025, 1, (0.22 - age) / 0.14))
    }

    private func draw(_ bubble: Bubble, age: TimeInterval, in context: CGContext) {
        let progress = CGFloat(min(1, max(0, age / 0.82)))
        let rise = 1 - pow(1 - progress, 2)
        let alpha = min(1, 16 * progress, (1 - progress) * 3.6)
        guard alpha > 0 else { return }

        let font = NSFont.monospacedSystemFont(ofSize: bubble.label.count > 2 ? 10 : 13, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.12, green: 0.20, blue: 0.18, alpha: alpha)
        ]
        let label = NSAttributedString(string: bubble.label, attributes: attributes)
        let labelSize = label.size()
        let width = max(22, labelSize.width + 10)
        let xPositions: [CGFloat] = [203, 229, 252, 218]
        let yPositions: [CGFloat] = [72, 84, 74, 102]
        let x = min(xPositions[bubble.lane] - width / 2, bounds.maxX - width - 4)
        let rect = NSRect(x: x, y: yPositions[bubble.lane] + 16 * rise, width: width, height: 21)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: NSColor.black.withAlphaComponent(alpha * 0.28).cgColor)
        NSColor(srgbRed: 0.95, green: 1, blue: 0.87, alpha: alpha).setFill()
        shape.fill()
        context.restoreGState()

        NSColor(srgbRed: 0.43, green: 0.62, blue: 0.38, alpha: alpha).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        label.draw(at: NSPoint(x: rect.midX - labelSize.width / 2, y: rect.midY - labelSize.height / 2))
    }
}
