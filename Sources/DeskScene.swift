import AppKit
import Carbon
import ImageIO

/// The desk props use view coordinates, so hands, loose caps and switches share an anchor.
final class DeskScene {
    enum Kind { case theft, fishing, mahjong }

    struct Frame {
        let kind: Kind
        var rightToe: CGPoint?
        var leftToe: CGPoint?
        var gaze: CGVector?
        var hiddenKey: Int?
        var grip: CGFloat = 0
        var lean: CGFloat = 0
        var bodyLift: CGFloat = 0
        var headTilt: CGFloat = 0
        fileprivate var capCenter: CGPoint?
        fileprivate var lift: CGFloat = 0
        fileprivate var capAngle: CGFloat = 0
        fileprivate var tension: CGFloat = 0
        fileprivate var lineSpeed: CGFloat = 0
        fileprivate var hasSlipper = false
        fileprivate var depth: CGFloat = 0
        fileprivate var catchProgress: CGFloat?
        fileprivate var phase: CGFloat = 0
        fileprivate var fade: CGFloat = 1

        func draw(in context: CGContext) {
            DeskSceneArt.draw(self, in: context)
        }
    }

    private struct Fishing {
        var born: TimeInterval
        var lastScroll: TimeInterval
        var depth: CGFloat = 0.22
        var cast = false
        var caughtAt: TimeInterval?
        var demo = false
        var shownDepth: CGFloat = 0.22
        var velocity: CGFloat = 0
        var hooked = false
        var integratedAt: TimeInterval?

        // The line catches up to the reel rather than jumping each time a wheel notch arrives.
        mutating func integrate(at now: TimeInterval) {
            let dt = min(1, max(0, now - (integratedAt ?? born)))
            integratedAt = now
            let offset = shownDepth - depth
            let omega: CGFloat = 8
            let carry = velocity + omega * offset
            let decay = exp(-omega * dt)
            shownDepth = clamp(depth + (offset + carry * dt) * decay)
            velocity = (velocity - omega * carry * dt) * decay
        }
    }

    private enum Action {
        case theft(start: TimeInterval, caughtAt: TimeInterval?)
        case fishing(Fishing)
        case mahjong(start: TimeInterval)
    }

    private var action: Action?
    private var lastKey: TimeInterval?
    private var theftArmed = false
    private var nextTheft: TimeInterval = 0
    private var nextFishing: TimeInterval = 0
    private var nextMahjong: TimeInterval = 0
    private var typedCount = 0
    private var scrollCharge: CGFloat = 0
    private var lastCastScroll: TimeInterval?
    private var sawDistantCursor = false

    func reset() {
        action = nil
        lastKey = nil
        theftArmed = false
        typedCount = 0
        scrollCharge = 0
        lastCastScroll = nil
        sawDistantCursor = false
    }

    func keyDown(isReturn: Bool, mahjong: Bool, at now: TimeInterval) {
        let continuing = lastKey.map { now - $0 < 2.3 } ?? false
        let eligible = continuing && typedCount >= 24 && isReturn && mahjong && now >= nextMahjong
        typedCount = isReturn ? 0 : (continuing ? min(30, typedCount + 1) : 1)
        lastKey = now
        theftArmed = true
        action = nil
        scrollCharge = 0
        if eligible {
            action = .mahjong(start: now)
            nextMahjong = now + 120
        }
    }

    /// A positive distance scrolls down the page and pays out fishing line.
    func scroll(down distance: CGFloat, character: PetCharacter, at now: TimeInterval) {
        guard character == .otter, distance.isFinite, abs(distance) > 0.01 else { return }
        let delta = min(120, max(-120, distance))
        if case .fishing(var fish) = action {
            guard fish.caughtAt == nil else { return }
            fish.integrate(at: now)
            fish.demo = false
            fish.lastScroll = now
            fish.depth = clamp(fish.depth + delta / 265)
            if fish.depth >= 0.68 { fish.cast = true }
            if fish.cast && delta < 0 { fish.hooked = true }
            if fish.cast && fish.depth <= 0.10 {
                fish.caughtAt = now
                nextFishing = now + 32
            }
            action = .fishing(fish)
        } else if now >= nextFishing && action == nil {
            if lastCastScroll.map({ now - $0 > 1.8 }) ?? true { scrollCharge = 0 }
            lastCastScroll = now
            scrollCharge = max(0, scrollCharge + delta)
            if scrollCharge >= 50 {
                let paidOut = min(0.65, scrollCharge / 265)
                action = .fishing(Fishing(born: now, lastScroll: now, depth: paidOut))
                scrollCharge = 0
                nextFishing = now + 32
            }
        }
    }

    func preview(_ kind: Kind, at now: TimeInterval) {
        reset()
        switch kind {
        case .theft: action = .theft(start: now, caughtAt: nil)
        case .fishing: action = .fishing(Fishing(born: now, lastScroll: now, demo: true))
        case .mahjong: action = .mahjong(start: now)
        }
    }

    func update(character: PetCharacter, cursorNear: Bool, canStartIdle: Bool, at now: TimeInterval) {
        switch action {
        case let .theft(start, caught):
            if !cursorNear { sawDistantCursor = true }
            let age = now - start
            if let caught {
                if now - caught >= 1.48 { action = nil }
            } else if age >= 6.1 {
                action = nil
            } else if (0.7...4.65).contains(age) && cursorNear && sawDistantCursor {
                action = .theft(start: start, caughtAt: now)
            }
        case .fishing(var fish):
            let age = now - fish.born
            fish.integrate(at: now)
            action = .fishing(fish)
            if let caught = fish.caughtAt {
                if now - caught >= 2.5 { action = nil }
            } else if fish.demo {
                if age < 1.5 { fish.depth = 0.2 + 0.72 * ease(age / 1.5) }
                else if age < 2.1 { fish.depth = 0.92 }
                else { fish.depth = 0.92 * (1 - ease((age - 2.1) / 1.4)) }
                fish.cast = fish.depth >= 0.68 || fish.cast
                if age > 2.1 { fish.hooked = true }
                if age >= 3.5 { fish.caughtAt = now }
                action = .fishing(fish)
            } else if now - fish.lastScroll >= 9 {
                action = nil
            }
        case .mahjong(let start):
            if now - start >= 2.3 { action = nil }
        case nil:
            if character == .raccoon && canStartIdle && !cursorNear && theftArmed,
               let lastKey, now - lastKey >= 15 && now >= nextTheft {
                theftArmed = false
                nextTheft = now + 80
                sawDistantCursor = true  // Natural scenes always start outside the catch radius.
                action = .theft(start: now, caughtAt: nil)
            }
        }
    }

    func frame(at now: TimeInterval) -> Frame? {
        switch action {
        case nil: return nil
        case .theft(let start, let caught):
            return theftFrame(age: (caught ?? now) - start, caughtAge: caught.map { now - $0 })
        case .fishing(var fish):
            let age = max(0, now - fish.born)
            fish.integrate(at: now)
            var f = Frame(kind: .fishing)
            f.phase = age
            f.depth = fish.shownDepth
            f.lineSpeed = min(1.4, max(-1.4, fish.velocity))
            f.hasSlipper = fish.hooked
            f.catchProgress = fish.caughtAt.map { max(0, now - $0) }
            f.fade = min(ease(age / 0.35), fish.demo || fish.caughtAt != nil ? 1 : ease((9 - (now - fish.lastScroll)) / 0.55))
            if let done = f.catchProgress { f.fade = min(f.fade, ease((2.5 - done) / 0.5)) }
            let heft = fish.hooked ? ease((0.88 - f.depth) / 0.37) : 0
            let rebound = f.catchProgress.map { sin($0 * 11) * exp(-4 * $0) } ?? 0
            f.tension = max(0, heft * 0.73 - f.lineSpeed * 0.28 + rebound * 0.21)
            f.lean = (2.1 - 5.0 * f.tension) * ease((age - 0.10) / 0.36) * f.fade
            f.bodyLift = (1.0 + 2 * heft - f.tension) * f.fade
            f.headTilt = (-0.065 + 0.12 * heft) * ease((age - 0.06) / 0.30) * f.fade
            let raise = 3 * heft - 1.8 * f.lineSpeed + 1.0 * rebound
            f.grip = ease((age - 0.10) / 0.32) * f.fade
            f.rightToe = mix(Self.rest, CGPoint(x: 189 - 2.2 * heft, y: 58 + raise),
                             ease((age - 0.10) / 0.32) * f.fade)
            f.leftToe = mix(CGPoint(x: 133, y: 51), CGPoint(x: 139, y: 52.8),
                            (0.30 + 0.7 * heft) * f.fade)
            f.gaze = CGVector(dx: 0.87, dy: -0.85 + 0.56 * (1 - f.depth))
            return f
        case .mahjong(let start):
            let age = max(0, now - start)
            var f = Frame(kind: .mahjong)
            f.phase = age
            f.fade = min(ease(age / 0.20), ease((2.3 - age) / 0.28))
            let reach = ease((age - 0.21) / 0.42) * (1 - ease((age - 0.92) / 0.54))
            let nudge = ease((age - 0.64) / 0.15) * (1 - ease((age - 0.84) / 0.25))
            f.rightToe = mix(Self.rest, CGPoint(x: 202.5 + 3.6 * nudge, y: 57.4 + 2.8 * nudge), reach)
            f.leftToe = mix(CGPoint(x: 133, y: 51), CGPoint(x: 139, y: 50),
                            ease((age - 0.14) / 0.52) * (1 - ease((age - 0.94) / 0.59)))
            f.lean = 3.8 * reach - 1.8 * window(age, 0.82, 1.15, 0.2)
            f.bodyLift = -1.5 * reach + 1.7 * nudge
            f.headTilt = -0.052 * window(age, 0.12, 1.2, 0.28) + 0.038 * window(age, 1.1, 1.75, 0.2)
            f.gaze = CGVector(dx: 0.67 + 0.26 * ease((age - 0.7) / 0.4), dy: -0.76)
            return f
        }
    }

    private static let rest = CGPoint(x: 182, y: 51)
    private static var socket: CGPoint { PetKeyboard.center(for: kVK_Escape)! }

    private func theftFrame(age: TimeInterval, caughtAge: TimeInterval?) -> Frame {
        let socket = Self.socket
        let rest = Self.rest
        var f = Frame(kind: .theft)
        let reach = ease((age - 0.67) / 0.78) * (1 - ease((age - 5.35) / 0.58))
        let brace = window(age, 0.39, 4.94, 0.40)
        let pry = window(age, 1.28, 1.76, 0.20)
        let popped = max(0, age - 1.76)
        let spring = sin(popped * 19) * exp(-7.5 * popped)
        let lift = ease(popped / 0.69) * (1 - ease((age - 4.42) / 0.91))
        let handArc = sin(.pi * lift)
        f.lift = lift
        f.grip = window(age, 1.16, 5.25, 0.29)
        f.capAngle = -0.36 * lift + 0.15 * spring
        let pocket = CGPoint(x: 190, y: 68)
        var loose = mix(socket, pocket, lift)
        loose.x += handArc * 2
        loose.y += (popped > 0 && age < 4.2 ? 4.2 : 2) * handArc + 2.1 * spring
        // The illustrated thumb opens towards screen-left. Leave the face of the cap outside the palm.
        let toeOffset = CGPoint(x: 6.2 * lift, y: 2.5 + 1.2 * lift)
        let contact = CGPoint(x: loose.x + toeOffset.x + 0.85 * pry, y: loose.y + toeOffset.y - 1.1 * pry)
        var toe = mix(rest, contact, reach)
        toe.y += 3.5 * sin(.pi * reach)
        let leftRest = CGPoint(x: 133, y: 51)
        let bracedToe = mix(leftRest, CGPoint(x: 140, y: 50.5 - 0.8 * pry), brace)
        f.rightToe = toe
        f.leftToe = bracedToe
        f.lean = 4.1 * brace + 2.4 * pry - 3.5 * lift - 2.2 * spring
        f.bodyLift = -1.8 * brace - 1.5 * pry + 2.7 * lift + 1.85 * spring
        f.headTilt = 0.035 * window(age, 0.12, 0.49, 0.18)
            - 0.086 * window(age, 0.48, 4.56, 0.44) + 0.031 * lift
        let glance = ease((age - 0.32) / 0.34)
        f.gaze = CGVector(dx: -0.87 + 1.72 * glance - 0.32 * lift, dy: 0.06 - 0.81 * glance)
        if lift > 0.002 {
            f.hiddenKey = kVK_Escape
            f.capCenter = loose
        }
        if let t = caughtAge {
            f.gaze = nil
            // Hold the caught pose for a beat before looking up and covering the evidence.
            let flinch = window(t, 0.07, 0.44, 0.19)
            let tuck = window(t, 0.31, 0.67, 0.17) * lift
            let replaced = ease((t - 0.67) / 0.43)
            let release = ease((t - 1.10) / 0.38)
            let relax = 1 - ease((t - 0.72) / 0.71)
            f.grip *= 1 - release
            f.headTilt = f.headTilt * relax + 0.052 * flinch
            f.lean = f.lean * relax - 1.9 * flinch
            f.bodyLift = f.bodyLift * relax + 1.8 * flinch
            let dip = abs(sin(2 * .pi * clamp((t - 0.46) / 0.61)))
            f.leftToe = mix(bracedToe, CGPoint(x: 133, y: 51 - 3.2 * dip), ease((t - 0.32) / 0.24))
            if f.capCenter != nil {
                var tucked = loose
                tucked.x += 7.2 * tuck
                tucked.y += 5.8 * tuck
                f.capCenter = mix(tucked, socket, replaced)
                f.lift *= 1 - replaced
                f.capAngle = (f.capAngle - 0.65 * tuck) * (1 - replaced)
                if replaced >= 1 { f.hiddenKey = nil; f.capCenter = nil }
            }
            var tuckedToe = toe
            tuckedToe.x -= 3.1 * tuck
            tuckedToe.y += 5.6 * tuck
            let target = lift > 0.002 ? CGPoint(x: socket.x, y: socket.y + 2.5) : rest
            f.rightToe = mix(mix(tuckedToe, target, replaced), rest, release)
        }
        return f
    }
}

fileprivate func clamp(_ t: CGFloat) -> CGFloat { min(1, max(0, t)) }

fileprivate func ease(_ t: CGFloat) -> CGFloat {
    let n = clamp(t)
    return n * n * (3 - 2 * n)
}

fileprivate func window(_ t: CGFloat, _ start: CGFloat, _ end: CGFloat, _ ramp: CGFloat) -> CGFloat {
    ease((t - start) / ramp) * (1 - ease((t - end) / ramp))
}

fileprivate func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

private enum DeskSceneArt {
    private static let ink = NSColor(srgbRed: 0.21, green: 0.17, blue: 0.16, alpha: 1).cgColor
    private static let ivory = NSColor(srgbRed: 1, green: 0.95, blue: 0.81, alpha: 1).cgColor
    private static let amber = NSColor(srgbRed: 0.90, green: 0.62, blue: 0.32, alpha: 1).cgColor
    private static let red = NSColor(srgbRed: 0.83, green: 0.29, blue: 0.26, alpha: 1).cgColor
    private static let teal = NSColor(srgbRed: 0.28, green: 0.59, blue: 0.56, alpha: 1).cgColor

    private static let esc = image("DeskEsc")
    private static let bobber = image("DeskBobber")
    private static let slipper = image("DeskSlipper")
    private static let tile = image("DeskTile")

    private static func image(_ name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    static func draw(_ f: DeskScene.Frame, in c: CGContext) {
        c.saveGState()
        defer { c.restoreGState() }
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.interpolationQuality = .high
        c.setAlpha(f.fade)
        switch f.kind {
        case .theft:
            guard let cap = f.capCenter else { return }
            if let esc {
                c.translateBy(x: cap.x, y: cap.y)
                c.rotate(by: f.capAngle)
                let width = 10 + 4 * f.lift
                let height = 4.2 + 7.8 * ease(f.lift * 1.6)
                c.draw(esc, in: CGRect(x: -width * 0.5, y: -height * 0.46, width: width, height: height))
            } else {
                PetKeyboard.drawLooseCap(kVK_Escape, center: cap, scale: 1 + 0.5 * f.lift,
                                         rotation: f.capAngle, in: c)
            }
        case .fishing: fishing(f, in: c)
        case .mahjong: tiles(f.phase, in: c)
        }
    }

    private static let cane = NSColor(srgbRed: 0.62, green: 0.38, blue: 0.20, alpha: 1).cgColor
    private static let guide = NSColor(srgbRed: 0.46, green: 0.49, blue: 0.45, alpha: 1).cgColor

    private static func fishing(_ f: DeskScene.Frame, in c: CGContext) {
        guard let paw = f.rightToe else { return }
        let grip = CGPoint(x: paw.x + 1, y: paw.y + 2)
        let length: CGFloat = 85
        let angle = 0.68 - 0.105 * f.lineSpeed + 0.085 * f.tension
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let bend = 9 + 17 * f.tension
        func shaft(_ s: CGFloat) -> CGPoint {
            CGPoint(x: grip.x + length * s * direction.x + 2.8 * f.tension * s * s,
                    y: grip.y + length * s * direction.y - bend * s * s * s)
        }
        // A tapered cane with ferrules and a cork grip. Flex is concentrated near the tip.
        let rod = CGMutablePath()
        for i in 0...14 {
            let u = CGFloat(i) / 14
            let p = shaft(u)
            let r = 1.72 - 1.20 * u
            let q = CGPoint(x: p.x + normal.x * r, y: p.y + normal.y * r)
            if i == 0 { rod.move(to: q) } else { rod.addLine(to: q) }
        }
        for i in (0...14).reversed() {
            let u = CGFloat(i) / 14
            let p = shaft(u)
            let r = 1.72 - 1.20 * u
            rod.addLine(to: CGPoint(x: p.x - normal.x * r, y: p.y - normal.y * r))
        }
        rod.closeSubpath()
        c.setFillColor(cane); c.setStrokeColor(ink); c.setLineWidth(0.55)
        c.addPath(rod); c.drawPath(using: .fillStroke)
        let varnish = CGMutablePath()
        for i in 2...14 {
            let u = CGFloat(i) / 15
            let p = shaft(u)
            let q = CGPoint(x: p.x + normal.x * (0.72 - u * 0.5),
                            y: p.y + normal.y * (0.72 - u * 0.5))
            if i == 2 { varnish.move(to: q) } else { varnish.addLine(to: q) }
        }
        c.addPath(varnish)
        c.setStrokeColor(amber)
        c.setLineWidth(0.52)
        c.strokePath()
        for joint: CGFloat in [0.25, 0.58, 0.84] {
            let p = shaft(joint)
            let r = 1.73 - joint
            let a = CGPoint(x: p.x - normal.x * r, y: p.y - normal.y * r)
            let b = CGPoint(x: p.x + normal.x * r, y: p.y + normal.y * r)
            stroke(c, from: a, to: b, color: ink, width: 1.25)
            stroke(c, from: mix(a, b, 0.35), to: b, color: guide, width: 0.6)
        }
        let butt = CGPoint(x: grip.x - direction.x * 6, y: grip.y - direction.y * 6)
        stroke(c, from: butt, to: shaft(0.14), color: ink, width: 4.9)
        stroke(c, from: butt, to: shaft(0.14), color: cane, width: 3.7)
        for u: CGFloat in [-0.045, 0.004, 0.046, 0.1] {
            stroke(c, from: shaft(u), to: shaft(u + 0.006), color: amber, width: 3.3)
        }
        let seat = shaft(0.17)
        let reel = CGPoint(x: seat.x + 1, y: seat.y - 4.5)
        stroke(c, from: seat, to: reel, color: ink, width: 1.6)
        ellipse(c, CGRect(x: reel.x - 3.8, y: reel.y - 3.5, width: 7.6, height: 7), fill: guide)
        let rotation = f.depth * 24
        for i in 0..<4 {
            let angle = rotation + CGFloat(i) * .pi / 2
            let hole = CGPoint(x: reel.x + 1.9 * cos(angle), y: reel.y + 1.7 * sin(angle))
            c.setFillColor(ink)
            c.fillEllipse(in: CGRect(x: hole.x - 0.6, y: hole.y - 0.65, width: 1.2, height: 1.3))
        }
        c.setStrokeColor(ivory.copy(alpha: 0.78)!)
        c.setLineWidth(0.5)
        c.beginPath()
        c.addArc(center: reel, radius: 2.8, startAngle: 0.20 * .pi, endAngle: 0.86 * .pi, clockwise: false)
        c.strokePath()
        let crank = CGPoint(x: reel.x + 3.1 * cos(f.depth * 24), y: reel.y + 3.1 * sin(f.depth * 24))
        stroke(c, from: reel, to: crank, color: ink, width: 1.15)
        c.setFillColor(amber)
        c.fillEllipse(in: CGRect(x: crank.x - 0.75, y: crank.y - 0.75, width: 1.5, height: 1.5))

        let tip = shaft(1)
        let caught = f.catchProgress ?? 0
        let swing = (f.catchProgress != nil ? sin(caught * 7.3) * exp(-2.3 * caught) * 0.11 : 0)
        let lineAngle = 0.023 + 0.046 * f.lineSpeed + swing
        let lineLength = 24 + 56 * f.depth
        let hanging = CGPoint(x: tip.x + sin(lineAngle) * lineLength,
                              y: tip.y - cos(lineAngle) * lineLength)
        let waterY: CGFloat = 24
        let slack = max(0, waterY - hanging.y)
        let float = CGPoint(x: hanging.x + slack * 0.16, y: max(waterY, hanging.y))
        let line = CGMutablePath()
        line.move(to: tip)
        line.addQuadCurve(to: CGPoint(x: float.x, y: float.y + 4.4),
                          control: CGPoint(x: (float.x + tip.x) * 0.5 + slack * 0.36 + f.lineSpeed * 1.75,
                                           y: (tip.y + float.y) * 0.5 - slack * 0.55))
        c.addPath(line); c.setStrokeColor(ink.copy(alpha: 0.67)!); c.setLineWidth(1.25); c.strokePath()
        c.addPath(line); c.setStrokeColor(ivory.copy(alpha: 0.88)!); c.setLineWidth(0.48); c.strokePath()
        let floatAngle = -lineAngle + min(0.3, slack * 0.025) * sin(f.phase * 5.2)
        c.saveGState()
        c.translateBy(x: float.x, y: float.y)
        c.rotate(by: floatAngle)
        if let bobber {
            c.draw(bobber, in: CGRect(x: -2.9, y: -6.7, width: 5.8, height: 13.4))
        } else {
            ellipse(c, CGRect(x: -2.6, y: -5.9, width: 5.2, height: 11.8), fill: ivory)
            c.setFillColor(red); c.fillEllipse(in: CGRect(x: -2.2, y: 0.4, width: 4.4, height: 5.2))
        }
        c.restoreGState()
        let tail = CGPoint(x: float.x + 6.4 * sin(floatAngle), y: float.y - 6.4 * cos(floatAngle))
        let hook = CGPoint(x: tail.x - 0.8, y: tail.y - 5.1)
        stroke(c, from: tail, to: CGPoint(x: hook.x + 1.0, y: hook.y + 0.3), color: guide, width: 0.9)
        if f.hasSlipper {
            c.saveGState()
            // The hook and shoe pass through the same surface on the way out.
            c.clip(to: CGRect(x: 0, y: waterY - 2, width: 320, height: 250))
            c.translateBy(x: hook.x, y: hook.y)
            let wobble = f.catchProgress.map { sin($0 * 8.4 - 0.4) * exp(-1.85 * $0) } ?? 0
            c.rotate(by: 0.92 + 0.17 * f.lineSpeed + 0.24 * wobble)
            let w: CGFloat = 29
            let h: CGFloat = 15.55
            let shoeBounds = CGRect(x: -0.68 * w, y: -0.43 * h, width: w, height: h)
            if let slipper {
                c.draw(slipper, in: shoeBounds)
            } else {
                paint(c, CGPath(roundedRect: shoeBounds.insetBy(dx: 0, dy: 2), cornerWidth: 4.0, cornerHeight: 4.0, transform: nil), fill: amber)
            }
            c.restoreGState()
        }
        let hookPath = CGMutablePath()
        hookPath.move(to: CGPoint(x: hook.x + 1.1, y: hook.y + 1.1))
        hookPath.addQuadCurve(to: CGPoint(x: hook.x - 1.4, y: hook.y + 1.2),
                              control: CGPoint(x: hook.x, y: hook.y - 1.7))
        c.addPath(hookPath); c.setStrokeColor(guide); c.setLineWidth(0.85); c.strokePath()
        let surface = ease((waterY + 12 - float.y) / 12)
        if surface > 0 {
            c.setStrokeColor(teal.copy(alpha: 0.67 * surface)!); c.setLineWidth(0.8)
            let radius = 8 + 3 * sin(f.phase * 3)
            c.strokeEllipse(in: CGRect(x: float.x - radius, y: waterY - 2.1,
                                       width: radius * 2, height: 3.6))
        }
    }

    private static let ranks: [[CGPoint]] = [
        [.zero],
        [CGPoint(x: -1.65, y: 2.5), CGPoint(x: 1.65, y: -2.5)],
        [CGPoint(x: -1.9, y: 3), .zero, CGPoint(x: 1.9, y: -3)],
        [CGPoint(x: -2.05, y: 2.6), CGPoint(x: 2.05, y: 2.6), CGPoint(x: -2.05, y: -2.6), CGPoint(x: 2.05, y: -2.6)]
    ]

    private static func tiles(_ age: CGFloat, in c: CGContext) {
        for i in (0..<4).reversed() {
            let t = age - (0.70 + Double(i) * 0.115)
            let falling = clamp(t / 0.25)
            let hitAngle = i == 3 ? 1.50 : 0.81
            let rebound = max(0, t - 0.25)
            let angle = hitAngle * falling * falling -
                0.14 * sin(rebound * 20) * exp(-rebound * 8)
            let push = ease(t / 0.21)
            c.saveGState()
            // Balance on the bottom-right corner until this tile touches its neighbour.
            c.translateBy(x: 213 + CGFloat(i) * 13.3 + push * 0.95, y: 52.5)
            c.setFillColor(ink.copy(alpha: 0.16)!)
            c.fillEllipse(in: CGRect(x: -11 + sin(angle) * 5, y: -1.15,
                                     width: 12 + sin(angle) * 4, height: 2.3))
            c.rotate(by: -angle)
            let body = CGRect(x: -12, y: 0, width: 12, height: 16)
            if let tile {
                c.draw(tile, in: body)
            } else {
                paint(c, CGPath(roundedRect: body, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil), fill: ivory)
            }
            let center = CGPoint(x: body.minX + body.width * 0.46, y: body.midY - 0.4)
            for offset in ranks[i] {
                let r: CGFloat = i == 0 ? 2.2 : 1.35
                let x = center.x + offset.x, y = center.y + offset.y
                c.setFillColor(i < 2 ? red : teal)
                c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                c.setFillColor(ivory)
                c.fillEllipse(in: CGRect(x: x - 0.4, y: y - 0.4, width: 0.8, height: 0.8))
            }
            c.restoreGState()
        }
    }

    private static func ellipse(_ c: CGContext, _ rect: CGRect, fill: CGColor) {
        paint(c, CGPath(ellipseIn: rect, transform: nil), fill: fill)
    }

    private static func paint(_ c: CGContext, _ path: CGPath, fill: CGColor) {
        c.setLineWidth(1.15); c.setFillColor(fill); c.setStrokeColor(ink)
        c.addPath(path); c.drawPath(using: .fillStroke)
    }

    private static func stroke(_ c: CGContext, from: CGPoint, to: CGPoint, color: CGColor, width: CGFloat) {
        c.setStrokeColor(color)
        c.setLineWidth(width)
        c.beginPath(); c.move(to: from); c.addLine(to: to); c.strokePath()
    }
}
