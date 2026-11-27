import AppKit
import ImageIO

/// The near end of the thread stays in Smudge's paw. Downward scrolling pays
/// it out, upward scrolling draws it back. Distance also sets ball rotation.
struct RollingYarn {
    private let born: TimeInterval
    private var changedAt: TimeInterval
    private var revealAt: TimeInterval
    private var revealFrom: CGFloat = 0
    private var from: CGFloat = 0.08
    private var target: CGFloat = 0.08
    private var direction: CGFloat = 1
    private var previousEffort: CGFloat = 0
    private var hasInput = false
    private var demo: Bool

    init(at now: TimeInterval, demo: Bool = false) {
        born = now
        changedAt = now
        revealAt = now
        self.demo = demo
    }

    mutating func scroll(down distance: CGFloat, at now: TimeInterval) {
        guard distance.isFinite, abs(distance) > 0.01 else { return }
        if end - now < Self.fadeOut {
            revealFrom = opacity(at: now)
            revealAt = now
        }
        previousEffort = effort(at: now)
        var current = position(at: now)
        if demo {
            target = current
            demo = false
        } else if !hasInput {
            current = distance > 0 ? 0.08 : 0.78
            target = current
        }
        from = current
        target = min(1, max(0, target + min(120, max(-120, distance)) / 225))
        direction = distance > 0 ? 1 : -1
        changedAt = now
        hasInput = true
    }

    private static let fadeOut: TimeInterval = 0.38
    private var end: TimeInterval { demo ? born + 4.6 : changedAt + 2.4 }

    func isFinished(at now: TimeInterval) -> Bool { now >= end }

    private func opacity(at now: TimeInterval) -> CGFloat {
        let reveal = revealFrom + (1 - revealFrom) * Self.ease((now - revealAt) / 0.14)
        return min(reveal, Self.ease((end - now) / Self.fadeOut))
    }

    private static func ease(_ t: CGFloat) -> CGFloat {
        let v = min(1, max(0, t))
        return v * v * (3 - 2 * v)
    }

    private func position(at now: TimeInterval) -> CGFloat {
        if demo {
            let age = now - born
            return 0.08 + 0.87 * Self.ease((age - 0.35) / 1.12)
                        - 0.84 * Self.ease((age - 2.12) / 1.05)
        }
        return target + (from - target) * exp(-11 * max(0, now - changedAt))
    }

    // Start the next tug at the paw's current position, even when the scroll
    // direction reverses between two display frames.
    private func effort(at now: TimeInterval) -> CGFloat {
        if demo {
            let age = now - born
            let push = Self.ease((age - 0.25) / 0.35) * (1 - Self.ease((age - 0.6) / 0.56))
            let pull = Self.ease((age - 2.02) / 0.35) * (1 - Self.ease((age - 2.45) / 0.62))
            return push - pull
        }
        guard hasInput else { return 0 }
        let elapsed = max(0, now - changedAt)
        let onset = 1 - exp(-elapsed * 16)
        return previousEffort * (1 - onset) + direction * onset * exp(-elapsed * 3)
    }

    func frame(at now: TimeInterval) -> DeskScene.Frame {
        let visible = opacity(at: now)
        let position = position(at: now)
        let stroke = effort(at: now)
        let paw = CGPoint(x: 205 + 7.5 * stroke - 4 * position,
                          y: 64 - 3 * position + max(1.5 * stroke, -6 * stroke))
        let ball = CGPoint(x: 214 + 49 * position, y: 67 - 20 * position)
        let fingertips = CGPoint(x: 182 + (paw.x - 182) * visible, y: 51 + (paw.y - 51) * visible)
        var f = DeskScene.Frame(kind: .yarn)
        f.rightToe = fingertips
        f.lean = (3.1 - 0.7 * position + 1.5 * stroke) * visible
        f.headTilt = (-0.034 - 0.039 * position) * visible
        f.bodyLift = (-1.3 + 0.8 * abs(stroke)) * visible
        f.gaze = CGVector(dx: 0.55 + 0.43 * position, dy: -0.83 + 0.13 * position)
        f.yarn = Pose(ball: ball, paw: fingertips, distance: position * hypot(49, 20),
                      tension: 0.46 - 0.40 * stroke, opacity: visible)
        return f
    }

    struct Pose {
        let ball: CGPoint
        let paw: CGPoint
        let distance: CGFloat
        let tension: CGFloat
        let opacity: CGFloat

        private static let art: CGImage? = {
            guard let url = Bundle.main.url(forResource: "YarnBall", withExtension: "png"),
                  let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }()

        func draw(in c: CGContext) {
            guard opacity > 0, let art = Self.art else { return }
            c.saveGState()
            defer { c.restoreGState() }
            c.setAlpha(opacity)
            c.beginTransparencyLayer(auxiliaryInfo: nil)
            let radius: CGFloat = 12
            let end = CGPoint(x: ball.x - 5, y: ball.y - 9)
            let span = end.x - paw.x
            let slack = min(13, max(1.1, span * (1 - tension) * 0.26))
            let thread = CGMutablePath()
            thread.move(to: paw)
            thread.addCurve(to: end,
                            control1: CGPoint(x: paw.x + 0.23 * span, y: paw.y - slack - 3),
                            control2: CGPoint(x: end.x - 0.28 * span, y: end.y - slack))
            c.setLineCap(.round)
            c.addPath(thread)
            c.setStrokeColor(CGColor(srgbRed: 0.57, green: 0.22, blue: 0.18, alpha: 1))
            c.setLineWidth(1.45)
            c.strokePath()
            c.addPath(thread)
            c.setStrokeColor(CGColor(srgbRed: 0.96, green: 0.55, blue: 0.36, alpha: 1))
            c.setLineWidth(0.65)
            c.strokePath()
            c.setFillColor(CGColor(gray: 0.11, alpha: 0.16))
            c.fillEllipse(in: CGRect(x: ball.x - 9, y: ball.y - radius - 0.9, width: 18, height: 3))
            c.translateBy(x: ball.x, y: ball.y)
            c.rotate(by: -distance / radius)
            c.interpolationQuality = .high
            c.draw(art, in: CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius))
            c.endTransparencyLayer()
        }
    }
}
