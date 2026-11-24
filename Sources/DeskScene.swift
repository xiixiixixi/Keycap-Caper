import AppKit
import Carbon

/// The desk props use view coordinates, so hands, loose caps and switches share an anchor.
final class DeskScene {
    enum Kind { case theft, fishing, mahjong }

    struct Frame {
        let kind: Kind
        var rightToe: CGPoint?
        var leftToe: CGPoint?
        var gaze: CGVector?
        var hiddenKey: Int?
        fileprivate var capCenter: CGPoint?
        fileprivate var lift: CGFloat = 0
        fileprivate var startled = false
        fileprivate var tuck: CGFloat = 0
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
            fish.demo = false
            fish.lastScroll = now
            fish.depth = clamp(fish.depth + delta / 265)
            if fish.depth >= 0.68 { fish.cast = true }
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
            if let caught = fish.caughtAt {
                if now - caught >= 2.5 { action = nil }
            } else if fish.demo {
                if age < 1.5 { fish.depth = 0.2 + 0.72 * ease(age / 1.5) }
                else if age < 2.1 { fish.depth = 0.92 }
                else { fish.depth = 0.92 * (1 - ease((age - 2.1) / 1.4)) }
                fish.cast = fish.depth >= 0.68 || fish.cast
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
        case .fishing(let fish):
            let age = max(0, now - fish.born)
            var f = Frame(kind: .fishing)
            f.phase = age
            f.depth = fish.depth
            f.catchProgress = fish.caughtAt.map { max(0, now - $0) }
            f.fade = min(ease(age / 0.3), fish.demo || fish.caughtAt != nil ? 1 : ease((9 - (now - fish.lastScroll)) / 0.5))
            if let done = f.catchProgress { f.fade = min(f.fade, ease((2.5 - done) / 0.4)) }
            f.rightToe = mix(Self.rest, CGPoint(x: 190, y: 59 - fish.depth * 3), f.fade)
            f.gaze = CGVector(dx: 0.93, dy: -0.43)
            return f
        case .mahjong(let start):
            let age = max(0, now - start)
            var f = Frame(kind: .mahjong)
            f.phase = age
            f.fade = min(ease(age / 0.22), ease((2.3 - age) / 0.35))
            let push = ease((age - 0.30) / 0.32) * (1 - ease((age - 0.78) / 0.32))
            f.rightToe = mix(Self.rest, CGPoint(x: 203, y: 64), push)
            f.gaze = CGVector(dx: 0.91, dy: -0.68)
            return f
        }
    }

    private static let rest = CGPoint(x: 182, y: 51)
    private static var socket: CGPoint { PetKeyboard.center(for: kVK_Escape)! }

    private func theftFrame(age: TimeInterval, caughtAge: TimeInterval?) -> Frame {
        let socket = Self.socket
        let rest = Self.rest
        var f = Frame(kind: .theft)
        let reach = ease((age - 0.65) / 0.85) * (1 - ease((age - 5.35) / 0.58))
        let lift = ease((age - 1.5) / 0.88) * (1 - ease((age - 4.5) / 0.85))
        f.lift = lift
        let pocket = CGPoint(x: 193, y: 71)
        let loose = mix(socket, pocket, lift)
        let pawOnCap = CGPoint(x: loose.x - 3 * lift, y: loose.y + 2.2)
        f.rightToe = mix(rest, pawOnCap, reach)
        f.gaze = age < 0.65 ? CGVector(dx: -0.9, dy: 0.15) : CGVector(dx: 0.86, dy: -0.70)
        if lift > 0.002 {
            f.hiddenKey = kVK_Escape
            f.capCenter = loose
        }
        if let t = caughtAge {
            f.startled = t < 0.65
            f.gaze = nil
            // She tucks the cap in her paw and taps two innocent notes with her free hand.
            f.tuck = ease((t - 0.25) / 0.16) * (1 - ease((t - 0.62) / 0.20))
            let tapping = clamp((t - 0.40) / 0.63)
            let dip = abs(sin(2 * .pi * tapping))
            f.leftToe = CGPoint(x: 133, y: 51 - 3.2 * dip)
            if let toe = f.rightToe {
                let replaced = ease((t - 0.62) / 0.46)
                if f.capCenter != nil {
                    f.capCenter = mix(loose, socket, replaced)
                    f.lift *= 1 - replaced
                    if replaced >= 1 { f.hiddenKey = nil; f.capCenter = nil }
                }
                let target = lift > 0.002 ? CGPoint(x: socket.x, y: socket.y + 2.2) : rest
                let settingDown = mix(toe, target, replaced)
                f.rightToe = mix(settingDown, rest, ease((t - 1.08) / 0.4))
            }
        }
        return f
    }
}

fileprivate func clamp(_ t: CGFloat) -> CGFloat { min(1, max(0, t)) }

fileprivate func ease(_ t: CGFloat) -> CGFloat {
    let n = clamp(t)
    return n * n * (3 - 2 * n)
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

    static func draw(_ f: DeskScene.Frame, in c: CGContext) {
        c.saveGState()
        defer { c.restoreGState() }
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.setAlpha(f.fade)
        switch f.kind {
        case .theft:
            if let cap = f.capCenter {
                let shown = CGPoint(x: cap.x + 3.6 * f.lift - 6.5 * f.tuck,
                                    y: cap.y - 1.9 * f.lift + 7.0 * f.tuck)
                PetKeyboard.drawLooseCap(kVK_Escape, center: shown, scale: 1 + 0.67 * f.lift,
                                         rotation: -0.33 * f.lift - 0.35 * f.tuck, in: c)
            }
            if f.startled {
                stroke(c, from: CGPoint(x: 200, y: 175), to: CGPoint(x: 202, y: 182), color: amber, width: 2.1)
                stroke(c, from: CGPoint(x: 205, y: 173), to: CGPoint(x: 210, y: 177), color: amber, width: 1.8)
            }
        case .fishing: fishing(f, in: c)
        case .mahjong: tiles(f.phase, in: c)
        }
    }

    private static func fishing(_ f: DeskScene.Frame, in c: CGContext) {
        guard let paw = f.rightToe else { return }
        let catchAge = f.catchProgress ?? 0
        let lift = ease(catchAge / 0.63)
        let tip = CGPoint(x: 252 - 6 * lift, y: 114 - 4 * f.depth + 6 * lift)
        let handle = CGPoint(x: paw.x - 3, y: paw.y + 1)
        let mid = CGPoint(x: 230, y: 116 + 4 * lift)
        let pole = CGMutablePath()
        pole.move(to: handle)
        pole.addQuadCurve(to: tip, control: mid)
        c.addPath(pole); c.setStrokeColor(ink); c.setLineWidth(3.3); c.strokePath()
        c.addPath(pole); c.setStrokeColor(amber); c.setLineWidth(1.7); c.strokePath()
        let reel = CGPoint(x: handle.x + 13, y: handle.y + 9)
        ellipse(c, CGRect(x: reel.x - 4.1, y: reel.y - 4.1, width: 8.2, height: 8.2), fill: teal)
        stroke(c, from: reel, to: CGPoint(x: reel.x + 3 * cos(f.depth * 17), y: reel.y + 3 * sin(f.depth * 17)), color: ivory, width: 1.5)

        let sway = sin(f.phase * 2.6) * 1.1
        let float = CGPoint(x: tip.x + 3 + sway - lift * 1.5, y: tip.y - 26 - 58 * f.depth + 3 * lift)
        let line = CGMutablePath()
        line.move(to: tip)
        line.addQuadCurve(to: float, control: CGPoint(x: float.x + 1.7, y: (tip.y + float.y) * 0.5))
        c.addPath(line); c.setStrokeColor(ink.copy(alpha: 0.78)!); c.setLineWidth(1.8); c.strokePath()
        c.addPath(line); c.setStrokeColor(ivory); c.setLineWidth(0.65); c.strokePath()
        let bobber = CGRect(x: float.x - 3.4, y: float.y - 5.4, width: 6.8, height: 10.8)
        ellipse(c, bobber, fill: ivory)
        c.saveGState()
        c.clip(to: CGRect(x: bobber.minX, y: float.y, width: bobber.width, height: 7))
        ellipse(c, bobber, fill: red)
        c.restoreGState()
        stroke(c, from: CGPoint(x: float.x, y: float.y - 5), to: CGPoint(x: float.x, y: float.y - 9), color: ink, width: 1.1)
        if f.catchProgress != nil {
            c.saveGState()
            c.translateBy(x: float.x, y: float.y - 11)
            c.rotate(by: -0.25 + sin(catchAge * 8) * 0.18 * exp(-catchAge * 2))
            let shoe = CGMutablePath()
            shoe.move(to: CGPoint(x: -3, y: 2))
            shoe.addQuadCurve(to: CGPoint(x: -13, y: -4), control: CGPoint(x: -13, y: 2))
            shoe.addQuadCurve(to: CGPoint(x: -10, y: -8), control: CGPoint(x: -14, y: -8))
            shoe.addLine(to: CGPoint(x: 9, y: -8))
            shoe.addQuadCurve(to: CGPoint(x: 13, y: -3), control: CGPoint(x: 14, y: -7))
            shoe.addQuadCurve(to: CGPoint(x: 7, y: 1), control: CGPoint(x: 12, y: 1))
            shoe.addLine(to: CGPoint(x: 5, y: -2))
            shoe.addLine(to: CGPoint(x: 0, y: -2))
            shoe.closeSubpath()
            paint(c, shoe, fill: amber)
            stroke(c, from: CGPoint(x: -10, y: -5.7), to: CGPoint(x: 9, y: -5.7), color: ivory, width: 1.6)
            stroke(c, from: CGPoint(x: -5, y: 0.4), to: CGPoint(x: -2, y: -2.9), color: red, width: 1.7)
            c.restoreGState()
        } else if f.depth > 0.50 {
            c.setStrokeColor(teal.copy(alpha: (f.depth - 0.5) * 1.4)!)
            c.setLineWidth(1.1)
            c.strokeEllipse(in: CGRect(x: float.x - 13, y: float.y - 4, width: 26, height: 4))
        }
    }

    private static func tiles(_ age: CGFloat, in c: CGContext) {
        let push = ease((age - 0.25) / 0.42)
        for i in 0..<4 {
            let fall = ease((age - 0.42 - Double(i) * 0.09) / 0.26)
            c.saveGState()
            c.translateBy(x: 207 + CGFloat(i) * 14.4 + 3 * push, y: 52)
            c.rotate(by: -fall * 0.61)
            let body = CGRect(x: -5.7, y: 0, width: 11.4, height: 15.2)
            paint(c, CGPath(roundedRect: body, cornerWidth: 2, cornerHeight: 2, transform: nil), fill: teal)
            let face = CGRect(x: -5.7, y: 2.1, width: 10.3, height: 13.2)
            paint(c, CGPath(roundedRect: face, cornerWidth: 1.8, cornerHeight: 1.8, transform: nil), fill: ivory)
            for n in 0...i {
                let x = (i % 2 == 0 && n == i) ? -0.6 : (n % 2 == 0 ? -2.7 : 1.8)
                let y = i == 0 ? 8.6 : ((n / 2) == 0 ? 10.4 : 6.3)
                c.setFillColor(i == 0 || i == 3 ? red : teal)
                c.fillEllipse(in: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2))
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
