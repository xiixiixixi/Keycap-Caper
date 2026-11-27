import AppKit
import Carbon

/// A continuous path from the cat's chest to the inside of a brass-framed purse.
/// Wheel events set a position. The paws, eyes and key all follow that same position.
struct KeycapStash {
    // The orange key fills the space under the grin, leaving both eyes and the fang visible.
    static let held = RascalKeycap(center: CGPoint(x: 157.5, y: 97), width: 68, angle: -0.22)

    private let born: TimeInterval
    private let continuing: DeskScene.Frame?
    private var entrance: TimeInterval
    private var entranceAlpha: CGFloat = 0
    private var lastWheel: TimeInterval
    private var departure: CGFloat
    private(set) var target: CGFloat
    private var direction: CGFloat = 0
    private var demo: Bool

    init(at now: TimeInterval, depth: CGFloat, demo: Bool = false, continuing: DeskScene.Frame? = nil) {
        self.continuing = continuing
        born = now
        entrance = now - 0.035
        lastWheel = now
        departure = depth
        target = depth
        self.demo = demo
    }

    mutating func scroll(down distance: CGFloat, at now: TimeInterval) {
        let current = position(at: now)
        if end - now < Self.fadeOut {
            entranceAlpha = visibility(at: now)
            entrance = now
        }
        if demo { target = current }
        demo = false
        departure = current
        lastWheel = now
        target = min(1, max(0, target + min(160, max(-160, distance)) / 150))
        direction = distance > 0 ? 1 : -1
    }

    func isFinished(at now: TimeInterval) -> Bool {
        now >= end
    }

    private static let fadeOut: TimeInterval = 0.29

    private func visibility(at now: TimeInterval) -> CGFloat {
        let appear = entranceAlpha + (1 - entranceAlpha) * Self.smooth((now - entrance) / 0.17)
        return min(appear, Self.smooth((end - now) / Self.fadeOut))
    }

    private var end: TimeInterval { demo ? born + 4.35 : lastWheel + 2.65 }

    private func position(at now: TimeInterval) -> CGFloat {
        if demo {
            let age = now - born
            return Self.smooth((age - 0.40) / 1.05) * (1 - Self.smooth((age - 2.05) / 1.15))
        }
        return target + (departure - target) * exp(-max(0, now - lastWheel) * 19)
    }

    private static func smooth(_ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    func frame(at now: TimeInterval) -> DeskScene.Frame {
        let depth = position(at: now)
        let visible = visibility(at: now)
        let travel = Self.smooth(depth / 0.72)
        let dip = Self.smooth((depth - 0.48) / 0.52)
        let since = max(0, now - lastWheel)
        let stroke = demo ? 0 : direction * sin(min(1, since / 0.33) * .pi) * exp(-since * 4)
        let squash = 0.9 * dip + 1.65 * max(0, stroke) * dip
        let bagWidth: CGFloat = 38 + squash * 0.65
        let bag = CGRect(x: 225 - bagWidth * 0.5, y: 24.5,
                         width: bagWidth, height: 30.75 - squash)
        let pocket = CGPoint(x: bag.midX, y: bag.minY + bag.height * 0.42)
        let held = Self.held
        // As the purse appears or clears, lift/lower the cap with the paws so
        // it never fades in at the muzzle while the hands are on the keyboard.
        let fromKeyboard = (1 - visible) * (1 - travel)
        let center = CGPoint(x: held.center.x + (pocket.x - held.center.x) * travel,
                             y: held.center.y + (64.6 - held.center.y) * travel - 35 * fromKeyboard
                                + 4.2 * sin(.pi * travel) - (64.6 - pocket.y) * dip)
        let width = held.width + (18 - held.width) * travel
        let cap = RascalKeycap(center: center, width: width - (width - 15) * fromKeyboard,
                               angle: held.angle + 0.29 * travel - 0.32 * dip)
        var frame = DeskScene.Frame(kind: .stash)
        frame.stash = Pose(bag: bag, alpha: visible)
        frame.rascalCap = cap
        frame.capOpacity = visible
        if visible > 0.26 { frame.hiddenKey = kVK_Escape }
        // Her second paw lets go before the key reaches the far side of the desk.
        let support = 1 - Self.smooth(depth / 0.55)
        let left = Self.mix(CGPoint(x: 139, y: 52), cap.leftContact, support)
        let lip = CGPoint(x: pocket.x + 2, y: pocket.y + 15 - 2.4 * stroke)
        let right = Self.mix(cap.rightContact, lip, Self.smooth((depth - 0.73) / 0.27))
        frame.leftToe = Self.mix(CGPoint(x: 133, y: 51), left, visible)
        frame.rightToe = Self.mix(CGPoint(x: 182, y: 51), right, visible)
        frame.leftGrip = support * visible
        frame.grip = visible
        frame.lean = (-1.6 + 7.2 * travel) * visible
        frame.bodyLift = (1.8 - 3.8 * dip - stroke * 0.85) * visible
        frame.headTilt = (0.045 - 0.115 * travel) * visible
        // At either end she peeks sideways once her paws have settled.
        let peek = Self.smooth((now - (demo ? born + 2.9 : lastWheel) - 0.33) / 0.47) * (1 - travel)
        frame.gaze = CGVector(dx: 0.24 + 0.65 * travel - 1.13 * peek, dy: -0.74 + 0.76 * peek)
        // Scrolling can interrupt a theft during the pry, lift, or return. Carry
        // those exact contacts into the purse gesture before taking up its path.
        if let previous = continuing, now - born < 0.28 {
            let amount = Self.smooth((now - born) / 0.28)
            frame.leftToe = Self.mix(previous.leftToe ?? CGPoint(x: 133, y: 51), left, amount)
            frame.rightToe = Self.mix(previous.rightToe ?? CGPoint(x: 182, y: 51), right, amount)
            frame.leftGrip += (previous.leftGrip - frame.leftGrip) * (1 - amount)
            frame.grip += (previous.grip - frame.grip) * (1 - amount)
            frame.lean += (previous.lean - frame.lean) * (1 - amount)
            frame.bodyLift += (previous.bodyLift - frame.bodyLift) * (1 - amount)
            frame.headTilt += (previous.headTilt - frame.headTilt) * (1 - amount)
            if let old = previous.rascalCap {
                frame.rascalCap = RascalKeycap(center: Self.mix(old.center, center, amount),
                    width: old.width + (cap.width - old.width) * amount,
                    angle: old.angle + (cap.angle - old.angle) * amount)
                frame.capOpacity = 1
                frame.hiddenKey = kVK_Escape
            }
        }
        return frame
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    struct Pose {
        let bag: CGRect
        let alpha: CGFloat

        // Trace the inner edge of the front brass rim in the purse's original proportions.
        // The cap and the fingertips can pass between this lip and the back of the purse.
        private var front: CGPath {
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: bag.minX + bag.width * x, y: bag.minY + bag.height * y)
            }
            let path = CGMutablePath()
            path.move(to: at(0, 0))
            path.addLine(to: at(0, 0.81))
            path.addLine(to: at(0.157, 0.81))
            path.addCurve(to: at(0.50, 0.626), control1: at(0.161, 0.705), control2: at(0.313, 0.626))
            path.addCurve(to: at(0.847, 0.809), control1: at(0.689, 0.626), control2: at(0.842, 0.707))
            path.addLine(to: at(1, 0.809))
            path.addLine(to: at(1, 0))
            path.closeSubpath()
            return path
        }

        func drawBack(in c: CGContext, bag image: CGImage?) {
            guard alpha > 0 else { return }
            c.saveGState()
            defer { c.restoreGState() }
            c.setAlpha(alpha)
            c.setFillColor(CGColor(gray: 0.12, alpha: 0.19))
            c.fillEllipse(in: CGRect(x: bag.minX + 2, y: bag.minY - 0.65, width: bag.width - 4, height: 3.1))
            if let image {
                c.saveGState()
                c.addRect(bag)
                c.addPath(front)
                c.clip(using: .evenOdd)
                c.draw(image, in: bag)
                c.restoreGState()
            }
        }

        func drawFront(in c: CGContext, bag image: CGImage?) {
            guard let image, alpha > 0 else { return }
            c.saveGState()
            c.setAlpha(alpha)
            c.addPath(front)
            c.clip()
            c.draw(image, in: bag)
            c.restoreGState()
        }
    }
}
