import AppKit

/// Feet stay on the desk, the chest can bear weight, and the skull moves as a
/// single piece above the neck. Eyes, shoulders and fur use the same map.
struct PortraitMotion {
    let neck: CGFloat
    let head: CGAffineTransform
    private let chestX: CGFloat
    private let chestY: CGFloat
    private let expansion: CGFloat

    init(neck: CGFloat, reach: CGFloat = 0, scene: DeskScene.Frame? = nil,
         affection: PetAffectionPose = .neutral, life: CGFloat = 0, weight: CGFloat = 0) {
        self.neck = neck
        let lean = (scene?.lean ?? 0) - 15 * reach
        let lift = scene?.bodyLift ?? 0
        let tilt = affection.tilt + (scene?.headTilt ?? 0) + 0.043 * reach - 0.013 * weight
        let pivot = CGPoint(x: 160, y: neck - 13)
        head = CGAffineTransform(translationX: pivot.x + lean + 0.9 * weight - affection.tilt * 21,
                                 y: pivot.y + lift + affection.lift * 0.74 + 0.48 * life - abs(weight) * 0.8)
            .rotated(by: tilt)
            .translatedBy(x: -pivot.x, y: -pivot.y)
        chestX = 0.33 * lean + 1.45 * weight
        chestY = 0.26 * lift - 0.72 * abs(weight) + life * 0.38
        expansion = life * 0.008
    }

    static func neck(for character: PetCharacter) -> CGFloat {
        switch character {
        case .cat: return 98
        case .dog: return 97
        case .rabbit: return 99
        case .giraffe: return 159
        case .raccoon: return 112
        case .redPanda: return 109
        case .otter: return 122
        }
    }

    static let base: CGFloat = 55

    func map(_ p: CGPoint) -> CGPoint {
        if p.y >= neck { return p.applying(head) }
        guard p.y > Self.base else { return p }
        let t = (p.y - Self.base) / (neck - Self.base)
        let w = t * t * (3 - 2 * t)
        let middle = 4 * t * (1 - t)
        let q = p.applying(head)
        return CGPoint(x: p.x + (q.x - p.x) * w + (chestX + expansion * (p.x - 160)) * middle,
                       y: p.y + (q.y - p.y) * w + chestY * middle)
    }

    var atRest: Bool { head.isIdentity && chestX == 0 && chestY == 0 && expansion == 0 }
}

/// Only the neck and chest are skinned. Each texture strip has a filter gutter.
/// Hard clipping on shared triangle edges avoids the dashed translucent seam
/// produced by independently antialiasing two sides of a texture mesh.
final class PortraitSkin {
    private struct Strip {
        let lower: CGFloat
        let upper: CGFloat
        let texture: CGImage
        let bounds: CGRect
    }

    private let original: CGImage
    private let frame: CGRect
    private let strips: [Strip]

    init(image: CGImage, frame: CGRect, neck: CGFloat) {
        original = image
        self.frame = frame
        let px = CGFloat(image.height) / frame.height
        let cuts = [frame.minY, PortraitMotion.base] + (1...5).map {
            PortraitMotion.base + (neck - PortraitMotion.base) * CGFloat($0) / 5
        } + [frame.maxY]
        strips = zip(cuts, cuts.dropFirst()).compactMap { lower, upper in
            let start = max(0, floor((frame.maxY - upper) * px) - 2)
            let end = min(CGFloat(image.height), ceil((frame.maxY - lower) * px) + 2)
            guard let crop = image.cropping(to: CGRect(x: 0, y: start, width: CGFloat(image.width), height: end - start)) else { return nil }
            let box = CGRect(x: frame.minX, y: frame.maxY - end / px, width: frame.width, height: (end - start) / px)
            return Strip(lower: lower, upper: upper, texture: crop, bounds: box)
        }
    }

    func draw(in c: CGContext, motion: PortraitMotion) {
        guard !motion.atRest else { c.draw(original, in: frame); return }
        for strip in strips {
            if strip.lower >= motion.neck || strip.upper <= PortraitMotion.base {
                c.saveGState()
                if strip.lower >= motion.neck { c.concatenate(motion.head) }
                c.setShouldAntialias(false)
                c.clip(to: CGRect(x: frame.minX, y: strip.lower, width: frame.width, height: strip.upper - strip.lower))
                c.draw(strip.texture, in: strip.bounds)
                c.restoreGState()
                continue
            }
            let bl = CGPoint(x: frame.minX, y: strip.lower)
            let br = CGPoint(x: frame.maxX, y: strip.lower)
            let tl = CGPoint(x: frame.minX, y: strip.upper)
            let tr = CGPoint(x: frame.maxX, y: strip.upper)
            let a = motion.map(bl), b = motion.map(br), d = motion.map(tl), e = motion.map(tr)
            let h = strip.upper - strip.lower
            drawTriangle(origin: bl, out: a, across: b, beside: d, width: frame.width, height: h, strip: strip, in: c)
            drawTriangle(origin: tr, out: e, across: d, beside: b, width: -frame.width, height: -h, strip: strip, in: c)
        }
    }

    private func drawTriangle(origin p: CGPoint, out q: CGPoint, across u: CGPoint, beside v: CGPoint,
                              width: CGFloat, height: CGFloat, strip: Strip, in c: CGContext) {
        let a = (u.x - q.x) / width, b = (u.y - q.y) / width
        let d = (v.x - q.x) / height, e = (v.y - q.y) / height
        let t = CGAffineTransform(a: a, b: b, c: d, d: e, tx: q.x - a * p.x - d * p.y, ty: q.y - b * p.x - e * p.y)
        c.saveGState()
        c.setShouldAntialias(false)
        c.beginPath(); c.move(to: q); c.addLine(to: u); c.addLine(to: v); c.closePath(); c.clip()
        c.concatenate(t)
        c.draw(strip.texture, in: strip.bounds)
        c.restoreGState()
    }
}

/// The palm keeps its original length while two short segments change angle at
/// the elbow. Both joints use fur sampled from the actual animal portrait.
final class PortraitLimb {
    private let fur: CGImage
    private let palm: CGImage
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    init?(fur: CGImage, straightPaw: CGImage) {
        self.fur = fur
        let w = straightPaw.width, h = Int(Double(straightPaw.height) * 0.55)
        guard let tip = straightPaw.cropping(to: CGRect(x: 0, y: straightPaw.height - h, width: w, height: h)),
              let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: Self.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let area = CGRect(x: 0, y: 0, width: w, height: h)
        c.draw(tip, in: area)
        if let fade = CGGradient(colorsSpace: Self.space, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1]) {
            c.setBlendMode(.destinationIn)
            c.drawLinearGradient(fade, start: CGPoint(x: 0, y: CGFloat(h) * 0.70), end: CGPoint(x: 0, y: h),
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        guard let palm = c.makeImage() else { return nil }
        self.palm = palm
    }

    func draw(in c: CGContext, shoulder: CGPoint, toe: CGPoint, side: CGFloat, grip: CGFloat, gripImage: CGImage?, hoof: Bool) {
        let dx = toe.x - shoulder.x, dy = toe.y - shoulder.y
        let distance = max(1, hypot(dx, dy))
        let bend = min(17, max(5, 24 - 0.31 * distance))
        let elbow = CGPoint(x: shoulder.x + dx * 0.45 + side * bend,
                            y: shoulder.y + dy * 0.40 + max(0, -dy - 34) * 0.10)
        let distalDistance = max(1, hypot(elbow.x - toe.x, elbow.y - toe.y))
        let ux = (elbow.x - toe.x) / distalDistance, uy = (elbow.y - toe.y) / distalDistance
        // A curled hand holds its prop from above, even when the elbow is out to the side.
        let palmAngle = min(1.16, max(-1.16, atan2(-ux, uy))) * (1 - grip * 0.72)
        let wrist = CGPoint(x: toe.x - sin(palmAngle) * 12.5, y: toe.y + cos(palmAngle) * 12.5)
        paintArm(in: c, from: shoulder, elbow: elbow, to: wrist)
        c.saveGState()
        c.translateBy(x: toe.x, y: toe.y); c.rotate(by: palmAngle)
        let w: CGFloat = hoof ? 16.0 : 20.0
        let custom = gripImage != nil ? grip : 0
        let blending = custom > 0 && custom < 1
        // Weight both opaque coats inside their own layer so key legends cannot
        // show through the palm while the fingers close around an object.
        if blending { c.beginTransparencyLayer(auxiliaryInfo: nil) }
        if custom < 1 {
            c.setAlpha(1 - custom)
            c.draw(palm, in: CGRect(x: -w / 2, y: -1.5, width: w, height: hoof ? 19 : 21))
        }
        if let gripImage, custom > 0 {
            if blending { c.setBlendMode(.plusLighter) }
            c.setAlpha(custom)
            let gripW: CGFloat = 22.5
            let gripH = min(29, gripW * CGFloat(gripImage.height) / CGFloat(gripImage.width))
            c.draw(gripImage, in: CGRect(x: -gripW * 0.29, y: -gripH * 0.32, width: gripW, height: gripH))
        }
        if blending { c.endTransparencyLayer() }
        c.restoreGState()
    }

    private func paintArm(in c: CGContext, from shoulder: CGPoint, elbow: CGPoint, to wrist: CGPoint) {
        let dx = shoulder.x - wrist.x, dy = shoulder.y - wrist.y
        let len = max(1, hypot(dx, dy))
        let angle = atan2(-dx, dy)
        c.saveGState()
        c.translateBy(x: wrist.x, y: wrist.y)
        c.rotate(by: angle)
        // Convert the elbow to this wrist-to-shoulder coordinate system.
        let ex = (elbow.x - wrist.x) * cos(angle) + (elbow.y - wrist.y) * sin(angle)
        let ey = -(elbow.x - wrist.x) * sin(angle) + (elbow.y - wrist.y) * cos(angle)
        let bend = max(-13, min(13, ex)), middle = max(4, min(len - 1, ey))
        let contour = CGMutablePath()
        contour.move(to: CGPoint(x: -6.5, y: -5))
        contour.addQuadCurve(to: CGPoint(x: -9.8, y: len + 3), control: CGPoint(x: bend * 1.65 - 9.3, y: middle))
        contour.addQuadCurve(to: CGPoint(x: 9.8, y: len + 3), control: CGPoint(x: 0, y: len + 10))
        contour.addQuadCurve(to: CGPoint(x: 6.5, y: -5), control: CGPoint(x: bend * 1.65 + 9.3, y: middle))
        contour.closeSubpath()
        c.addPath(contour)
        c.clip()
        let ext = max(12, abs(bend) + 12)
        let box = CGRect(x: -ext, y: -5, width: ext * 2, height: len + 15)
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        c.draw(fur, in: box)
        let shade = CGColor(srgbRed: 0.13, green: 0.09, blue: 0.08, alpha: 0.26)
        let clear = CGColor(gray: 0, alpha: 0)
        if let g = CGGradient(colorsSpace: Self.space, colors: [shade, clear, clear, shade] as CFArray, locations: [0, 0.27, 0.7, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: -ext, y: 0), end: CGPoint(x: ext, y: 0), options: [])
        }
        if let fade = CGGradient(colorsSpace: Self.space, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1]) {
            c.setBlendMode(.destinationIn)
            c.drawLinearGradient(fade, start: CGPoint(x: 0, y: max(4, len - 8)), end: CGPoint(x: 0, y: len + 7),
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        c.endTransparencyLayer()
        c.restoreGState()
    }
}
