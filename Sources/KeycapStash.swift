import AppKit
import Carbon

/// A continuous path from the cat's chest to the inside of a brass-framed purse.
/// Wheel events set a position. The paws, eyes and key all follow that same position.
struct KeycapStash {
    private let born: TimeInterval
    private var entrance: TimeInterval
    private var entranceAlpha: CGFloat = 0
    private var lastWheel: TimeInterval
    private var departure: CGFloat
    private(set) var target: CGFloat
    private var direction: CGFloat = 0
    private var demo: Bool

    init(at now: TimeInterval, depth: CGFloat, demo: Bool = false) {
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
        let cap = CGPoint(x: 179 + (pocket.x - 179) * travel,
                          y: 72 + 2.1 * sin(.pi * travel) - 7.4 * travel - (64.6 - pocket.y) * dip)
        let angle = -0.27 + 0.38 * travel - 0.37 * dip
        let pose = Pose(bag: bag, capCenter: cap, capAngle: angle, capWidth: 22 - 3.1 * travel, alpha: visible)
        var frame = DeskScene.Frame(kind: .stash)
        frame.stash = pose
        if visible > 0.26 { frame.hiddenKey = kVK_Escape }
        let left = CGPoint(x: 168 - 28 * travel, y: 69 - 17 * travel)
        let right = CGPoint(x: cap.x + 7 - 4.5 * dip,
                            y: cap.y + 3.8 + 11 * Self.smooth((depth - 0.79) / 0.21) - 2.4 * stroke * dip)
        frame.leftToe = CGPoint(x: 133 + (left.x - 133) * visible, y: 51 + (left.y - 51) * visible)
        frame.rightToe = CGPoint(x: 182 + (right.x - 182) * visible, y: 51 + (right.y - 51) * visible)
        // The curled toes rest against the purse lip when the cap is hidden.
        // Opening the hand before it withdraws would put a second silhouette outside the purse.
        frame.grip = visible
        frame.lean = (-1.6 + 7.2 * travel) * visible
        frame.bodyLift = (1.8 - 3.8 * dip - stroke * 0.85) * visible
        frame.headTilt = (0.045 - 0.115 * travel) * visible
        // At either end she peeks sideways once her paws have settled.
        let peek = Self.smooth((now - (demo ? born + 2.9 : lastWheel) - 0.33) / 0.47) * (1 - travel)
        frame.gaze = CGVector(dx: 0.24 + 0.65 * travel - 1.13 * peek, dy: -0.74 + 0.76 * peek)
        return frame
    }

    struct Pose {
        let bag: CGRect
        let capCenter: CGPoint
        let capAngle: CGFloat
        let capWidth: CGFloat
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

        func drawBack(in c: CGContext, bag image: CGImage?, cap: CGImage?) {
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
            if let cap {
                c.translateBy(x: capCenter.x, y: capCenter.y)
                c.rotate(by: capAngle)
                c.draw(cap, in: CGRect(x: -0.5 * capWidth, y: -0.42 * capWidth, width: capWidth, height: 0.85 * capWidth))
            } else {
                PetKeyboard.drawLooseCap(kVK_Escape, center: capCenter, scale: 1.6, rotation: capAngle, in: c)
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
