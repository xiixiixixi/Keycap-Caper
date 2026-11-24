import AppKit

struct PetAffectionPose {
    var tilt: CGFloat = 0
    var lift: CGFloat = 0
    var blink: CGFloat = 0
    var gaze: CGVector?
    var leftToe: CGPoint?
    var rightToe: CGPoint?
    static let neutral = PetAffectionPose()
}

final class PetAffection {
    private struct Catch {
        let label: String
        let lane: Int
        let pet: PetCharacter
        let born: TimeInterval
        var isPillow: Bool { pet == .cat && label == "空格" }
        var duration: TimeInterval { isPillow ? 2.75 : 2.15 }
    }

    private var catching: Catch?
    private var keysUntilCatch = 7
    private var nextCatch: TimeInterval = 0
    private var previousCursor: CGPoint?
    private var lastTick: TimeInterval?
    private var strokeDistance: CGFloat = 0
    private var lastStroke = -TimeInterval.infinity
    private var touchPreviewUntil = -TimeInterval.infinity
    private var touchAmount: CGFloat = 0
    private var touchDirection: CGFloat = 0
    private var touchLift: CGFloat = 0
    private var pet: PetCharacter = .cat
    private var reducedMotion = false

    var isPetting: Bool { touchAmount > 0.025 }
    var isActive: Bool { isPetting || catching != nil }

    func reset() {
        catching = nil
        lastStroke = -.infinity
        touchPreviewUntil = -.infinity
        strokeDistance = 0
        touchAmount = 0
        touchDirection = 0
        touchLift = 0
        previousCursor = nil
        lastTick = nil
        keysUntilCatch = 7
    }

    func clearBubble() { catching = nil }

    func previewTouch(character: PetCharacter, at now: TimeInterval) {
        pet = character
        catching = nil
        touchPreviewUntil = now + 1.35
        lastStroke = now
    }

    @discardableResult
    func offerBubble(label: String, lane: Int, character: PetCharacter, at now: TimeInterval, force: Bool = false) -> Bool {
        guard (0..<4).contains(lane) else { return false }
        if !force {
            guard catching == nil, !isPetting, now >= nextCatch else { return false }
            keysUntilCatch -= 1
            let catFoundSpace = character == .cat && label == "空格" && keysUntilCatch <= 4
            guard keysUntilCatch <= 0 || catFoundSpace else { return false }
        }
        pet = character
        catching = Catch(label: label, lane: lane, pet: character, born: now)
        keysUntilCatch = Int.random(in: 6...12)
        nextCatch = now + .random(in: 15...24)
        return true
    }

    @discardableResult
    func update(cursor: CGPoint, eyeCenter: CGPoint, character: PetCharacter, at now: TimeInterval, reducedMotion: Bool) -> Bool {
        self.pet = character
        self.reducedMotion = reducedMotion
        let wasActive = isActive
        if let catching, now - catching.born >= catching.duration { self.catching = nil }

        let elapsed = now - (lastTick ?? now)
        let dt = CGFloat(min(0.1, max(0, elapsed)))
        let forehead = foreheadBounds(for: character, eyes: eyeCenter)
        if let previousCursor, (0...0.18).contains(elapsed),
           onForehead(previousCursor, in: forehead), onForehead(cursor, in: forehead) {
            let travel = hypot(cursor.x - previousCursor.x, cursor.y - previousCursor.y)
            strokeDistance = max(0, strokeDistance - dt * 22)
            if travel >= 0.5 && travel <= 62 {
                strokeDistance = min(35, strokeDistance + travel)
                if strokeDistance >= 15 {
                    lastStroke = now
                    // Keep a real stroke going; a parked cursor must never keep it alive.
                    if !isPetting { catching = nil }
                }
            }
        } else { strokeDistance = 0 }
        previousCursor = cursor
        lastTick = now

        let preview = now < touchPreviewUntil
        let age = now - lastStroke
        let linger: TimeInterval = character == .giraffe ? 1.05 : 0.65
        let target = preview ? 1 : Self.clamp(CGFloat((linger - age) / (linger * 0.55)))
        let follow = 1 - exp(-dt * (target > touchAmount ? 11 : 7))
        touchAmount += (target - touchAmount) * follow
        if touchAmount < 0.005 && target == 0 { touchAmount = 0 }
        if target > 0 {
            let aim = preview ? cos(CGFloat(touchPreviewUntil - now) * 3.5) : (cursor.x - eyeCenter.x) / (forehead.width * 0.46)
            let up = preview ? 0.75 : (cursor.y - forehead.midY) / 34
            touchDirection += (max(-1, min(1, aim)) - touchDirection) * (1 - exp(-dt * 8))
            touchLift += (max(-0.5, min(1, up)) - touchLift) * (1 - exp(-dt * 8))
        }
        return wasActive || isActive
    }

    private func foreheadBounds(for character: PetCharacter, eyes: CGPoint) -> CGRect {
        let size: CGSize
        let rise: CGFloat
        switch character {
        case .cat:      (size, rise) = (CGSize(width: 106, height: 52), 33)
        case .rabbit:   (size, rise) = (CGSize(width: 78, height: 33), 22)
        case .giraffe:  (size, rise) = (CGSize(width: 62, height: 41), 17)
        case .dog:      (size, rise) = (CGSize(width: 86, height: 44), 23)
        case .raccoon, .redPanda, .otter: (size, rise) = (CGSize(width: 88, height: 44), 25)
        }
        return CGRect(x: eyes.x - size.width / 2, y: eyes.y + rise - size.height / 2, width: size.width, height: size.height)
    }

    private func onForehead(_ point: CGPoint, in oval: CGRect) -> Bool {
        let dx = (point.x - oval.midX) / (oval.width / 2)
        let dy = (point.y - oval.midY) / (oval.height / 2)
        return dx * dx + dy * dy <= 1
    }

    private static func clamp(_ x: CGFloat) -> CGFloat { min(1, max(0, x)) }
    private static func smooth(_ x: CGFloat) -> CGFloat {
        let t = clamp(x)
        return t * t * (3 - 2 * t)
    }

    func pose(at now: TimeInterval) -> PetAffectionPose {
        var pose = PetAffectionPose()
        let movement: CGFloat = reducedMotion ? 0.22 : 1
        if isPetting {
            let longNeck = pet == .giraffe
            pose.blink = touchAmount * (longNeck ? 0.65 : 0.97)
            pose.tilt = -touchDirection * touchAmount * (longNeck ? 0.14 : 0.085) * movement
            pose.lift = (longNeck ? 8 + 10 * touchLift : 4.2) * touchAmount * movement
            return pose
        }
        guard let c = catching else { return pose }
        let age = CGFloat(now - c.born)
        let t = Self.smooth((age - 0.55) / 0.50) * Self.smooth((CGFloat(c.duration) - age) / 0.43)
        guard t > 0 else { return pose }
        let phase = min(1, max(0, (age - 1.12) / 0.66))
        let flick = sin(phase * .pi)
        pose.gaze = CGVector(dx: 0.85 - 0.7 * t, dy: -0.82)
        switch c.pet {
        case .dog:
            pose.tilt = (-0.08 + 0.1 * flick) * t * movement
            pose.lift = (4 - 6 * flick) * t * movement
        case .rabbit, .giraffe:
            pose.lift = (c.pet == .giraffe ? 8 : 6) * flick * t * movement
            pose.tilt = -0.05 * t * movement
        case .cat where c.isPillow:
            pose.tilt = -0.13 * t * movement
            pose.lift = -7 * t * movement
            pose.blink = 0.95 * t
        case .raccoon, .otter:
            pose.leftToe = CGPoint(x: 133 + 18 * t, y: 51 + 20 * t)
            pose.rightToe = CGPoint(x: 182 - 13 * t, y: 51 + 20 * t)
            pose.tilt = 0.045 * t * movement
        case .cat, .redPanda:
            pose.rightToe = CGPoint(x: 182 + 9 * t, y: 51 + (15 + 6 * flick) * t)
            pose.tilt = -0.06 * t * movement
        }
        return pose
    }

    enum BubbleLayer { case all, beforePaws, afterPaws }

    func drawBubble(in context: CGContext, at now: TimeInterval, mouseReach: CGFloat = 0, layer: BubbleLayer = .all) {
        guard let c = catching else { return }
        let age = CGFloat(now - c.born)
        guard age >= 0, age < CGFloat(c.duration) else { return }
        let heldInPaws = age >= 1.03 && (c.pet == .raccoon || c.pet == .otter || c.pet == .redPanda || (c.pet == .cat && !c.isPillow))
        if (layer == .beforePaws && !heldInPaws) || (layer == .afterPaws && heldInPaws) { return }
        if age <= 0.50 {
            PetBubbleArt.draw(label: c.label, lane: c.lane, age: TimeInterval(age), in: context)
            return
        }
        let start = PetBubbleArt.center(lane: c.lane, age: 0.50)
        let spot = contact(for: c, pose: pose(at: now), mouseReach: mouseReach)
        let fall = Self.smooth((age - 0.50) / 0.66)
        let release = Self.smooth((age - 1.2) / 0.68)
        let motion: CGFloat = reducedMotion ? 0 : 1
        var center = CGPoint(x: start.x + (spot.x - start.x) * fall,
                             y: start.y + (spot.y - start.y) * fall + 17 * sin(.pi * fall) * motion)
        var tilt = -0.22 * sin(.pi * fall) * motion
        var stretch: CGFloat = 1
        switch c.pet {
        case .rabbit, .giraffe:
            center.x += release * 40 * motion
            center.y += (sin(.pi * release) * 27 + 7 * release) * motion
            tilt += release * 0.55 * motion
        case .dog:
            tilt += (0.15 - 0.30 * sin(release * .pi)) * fall * motion
        case .cat where c.isPillow:
            stretch += 0.30 * fall
            tilt += 0.17 * fall * motion
        case .otter, .raccoon:
            center.y += sin(release * .pi * 2) * 3 * motion
            tilt += sin(release * .pi * 2) * 0.22 * motion
        case .cat, .redPanda:
            center.x += release * 28 * motion
            center.y += sin(release * .pi) * 22 * motion
            tilt += release * 0.5 * motion
        }
        let alpha = Self.clamp((CGFloat(c.duration) - age) / 0.38)
        PetBubbleArt.draw(label: c.label, center: center, alpha: alpha, tilt: tilt, stretch: stretch, in: context)
    }

    private func contact(for c: Catch, pose: PetAffectionPose, mouseReach: CGFloat) -> CGPoint {
        let offset: CGVector
        switch c.pet {
        case .dog: offset = CGVector(dx: 5, dy: -38)
        case .rabbit: offset = CGVector(dx: 17, dy: -14)
        case .giraffe: offset = CGVector(dx: 18, dy: -19)
        case .cat where c.isPillow: offset = CGVector(dx: 17, dy: -43)
        case .otter, .raccoon: return CGPoint(x: 160, y: 72)
        case .cat, .redPanda: return CGPoint(x: 196, y: 72)
        }
        return CatArt.faceSpot(offsetFromEyes: offset, character: c.pet, reach: mouseReach, reaction: pose)
    }
}

enum PetBubbleArt {
    static func center(lane: Int, age: TimeInterval) -> CGPoint {
        let progress = CGFloat(min(1, max(0, age / 0.82)))
        let rise = 1 - pow(1 - progress, 2)
        let xs: [CGFloat] = [203, 229, 252, 218]
        let ys: [CGFloat] = [72, 84, 74, 102]
        return CGPoint(x: xs[lane], y: ys[lane] + 10.5 + 16 * rise)
    }

    static func draw(label: String, lane: Int, age: TimeInterval, in context: CGContext) {
        let progress = CGFloat(min(1, max(0, age / 0.82)))
        let alpha = min(1, 16 * progress, (1 - progress) * 3.6)
        draw(label: label, center: center(lane: lane, age: age), alpha: alpha, tilt: 0, stretch: 1, in: context)
    }

    static func draw(label: String, center: CGPoint, alpha: CGFloat, tilt: CGFloat, stretch: CGFloat, in context: CGContext) {
        guard alpha > 0 else { return }
        let font = NSFont.monospacedSystemFont(ofSize: label.count > 2 ? 10 : 13, weight: .semibold)
        let text = NSAttributedString(string: label, attributes: [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.12, green: 0.20, blue: 0.18, alpha: alpha)
        ])
        let size = text.size()
        let width = max(22, size.width + 10)
        let rect = CGRect(x: -width / 2, y: -10.5, width: width, height: 21)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: min(center.x, CatArt.size.width - width / 2 - 4), y: center.y)
        context.rotate(by: tilt)
        context.scaleBy(x: stretch, y: 1 / stretch)
        let cap = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: NSColor.black.withAlphaComponent(alpha * 0.28).cgColor)
        NSColor(srgbRed: 0.95, green: 1, blue: 0.87, alpha: alpha).setFill()
        cap.fill()
        context.restoreGState()
        NSColor(srgbRed: 0.43, green: 0.62, blue: 0.38, alpha: alpha).setStroke()
        cap.lineWidth = 1
        cap.stroke()
        text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
    }
}
