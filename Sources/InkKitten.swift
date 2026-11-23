import AppKit

/// A seated, front-facing cat. Screen-left is the cat's own right side.
enum InkKitten {
    private static let outline = pigment(0x17181B)
    private static let bodyLight = pigment(0x39383B)
    private static let bodyDark = pigment(0x222226)
    private static let rim = pigment(0x5F5859)

    static func drawBody(in c: CGContext, gaze: CGVector, blink: CGFloat, reach: CGFloat) {
        c.saveGState()
        defer { c.restoreGState() }
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.translateBy(x: -12 * reach, y: 0)
        let lean = 26 * reach

        let tail = CGMutablePath()
        tail.begin(177, 75)
        tail.bend(195, 69, 209, 70, 219, 80)
        tail.bend(226, 88, 226, 98, 233, 105)
        tail.bend(238, 110, 245, 113, 249, 111)
        tail.bend(253, 109, 251, 104, 247, 103)
        tail.bend(239, 102, 236, 98, 234, 92)
        tail.bend(229, 76, 223, 66, 209, 64)
        tail.bend(195, 61, 184, 64, 176, 65)
        tail.closeSubpath()
        wash(tail, top: bodyLight, bottom: bodyDark, in: c)

        let body = CGMutablePath()
        body.begin(140 - lean, 151)
        body.bend(137 - lean, 140, 130 - lean, 131, 124 - lean, 119)
        body.bend(116 - lean, 104, 110 - lean * 0.36, 86, 115, 73)
        body.bend(118, 62, 124, 60, 128, 60)
        body.bend(131, 55, 144, 54, 151, 59)
        body.bend(163, 55, 172, 55, 177, 60)
        body.bend(188, 57, 199, 61, 199, 69)
        body.bend(204, 76, 202, 91, 198, 101)
        body.bend(194, 114, 182 - lean * 0.4, 121, 179 - lean * 0.7, 132)
        body.bend(177 - lean, 138, 173 - lean, 146, 171 - lean, 152)
        body.closeSubpath()
        wash(body, top: bodyLight, bottom: bodyDark, in: c)
        let haunch = CGMutablePath()
        haunch.begin(192, 93)
        haunch.bend(184, 92, 179, 85, 180, 74)
        haunch.bend(180, 71, 181, 68, 179, 65)
        stroke(haunch, color: pigment(0x16161A, alpha: 0.65), width: 1.15, in: c)
        let haunchLight = CGMutablePath()
        haunchLight.begin(196, 96)
        haunchLight.bend(193, 102, 189, 106, 187 - lean * 0.2, 108)
        stroke(haunchLight, color: pigment(0x665D5E, alpha: 0.48), width: 1.1, in: c)

        c.translateBy(x: -lean, y: -1.5 * reach)
        c.translateBy(x: 152, y: 144)
        c.rotate(by: 0.055 * reach)
        c.translateBy(x: -152, y: -144)
        drawHead(in: c, gaze: gaze, blink: blink)
    }

    private static func drawHead(in c: CGContext, gaze: CGVector, blink: CGFloat) {
        let head = CGMutablePath()
        head.begin(116, 175)
        head.bend(113, 186, 111, 200, 114, 206)
        head.bend(118, 209, 129, 199, 137, 189)
        head.bend(145, 192, 160, 193, 170, 190)
        head.bend(178, 197, 185, 207, 190, 206)
        head.bend(193, 201, 191, 186, 189, 178)
        head.bend(194, 171, 196, 160, 193, 153)
        head.lineTo(196, 154)
        head.bend(193, 145, 185, 140, 180, 137)
        head.lineTo(182, 136)
        head.bend(171, 130, 159, 130, 151, 130)
        head.bend(138, 130, 126, 134, 120, 140)
        head.lineTo(123, 140)
        head.bend(116, 143, 110, 149, 108, 155)
        head.lineTo(112, 154)
        head.bend(110, 162, 111, 168, 116, 175)
        head.closeSubpath()
        wash(head, top: pigment(0x424045), bottom: pigment(0x26262A), in: c)

        let leftEar = CGMutablePath()
        leftEar.begin(118, 201)
        leftEar.bend(123, 199, 128, 194, 132, 189)
        leftEar.bend(127, 190, 123, 187, 119, 184)
        leftEar.bend(118, 189, 117, 197, 118, 201)
        leftEar.closeSubpath()
        let rightEar = CGMutablePath()
        rightEar.begin(186, 201)
        rightEar.bend(187, 197, 187, 189, 185, 184)
        rightEar.bend(182, 187, 178, 189, 175, 189)
        rightEar.bend(179, 193, 183, 198, 186, 201)
        rightEar.closeSubpath()
        for ear in [leftEar, rightEar] {
            wash(ear, top: pigment(0xA37B76), bottom: pigment(0x604E55), in: c, edge: false)
        }
        let brow = CGMutablePath()
        brow.begin(126, 177)
        brow.bend(130, 180, 135, 181, 139, 180)
        brow.begin(166, 180)
        brow.bend(171, 181, 176, 180, 179, 178)
        stroke(brow, color: pigment(0x625B5D), width: 0.95, in: c)
        drawEye(in: c, x: 135, y: 164, side: -1, gaze: gaze, blink: blink)
        drawEye(in: c, x: 170, y: 164, side: 1, gaze: gaze, blink: blink)

        let nose = CGMutablePath()
        nose.begin(149.2, 150.6)
        nose.bend(150.3, 152, 155, 152, 156.2, 150.7)
        nose.bend(156.6, 149.6, 153.9, 147.6, 152.7, 147.4)
        nose.bend(151.4, 147.6, 148.8, 149.6, 149.2, 150.6)
        nose.closeSubpath()
        fill(nose, color: pigment(0xB48C89), in: c)
        let mouth = CGMutablePath()
        mouth.begin(152.7, 147.6)
        mouth.lineTo(152.7, 145.6)
        mouth.bend(151.7, 143.7, 149.7, 143.5, 147.9, 144.3)
        mouth.begin(152.7, 145.6)
        mouth.bend(153.7, 144, 155.7, 143.5, 157.4, 144.6)
        stroke(mouth, color: pigment(0xA59693), width: 0.82, in: c)
        for side: CGFloat in [-1, 1] {
            let x: CGFloat = 152.5
            let whiskers = CGMutablePath()
            whiskers.begin(x + side * 23, 151)
            whiskers.bend(x + side * 32, 153, x + side * 40, 155, x + side * 48, 154.6)
            whiskers.begin(x + side * 24, 148.5)
            whiskers.bend(x + side * 33, 148.7, x + side * 41, 148, x + side * 48, 146)
            whiskers.begin(x + side * 24, 146)
            whiskers.bend(x + side * 30, 145.3, x + side * 36, 143.5, x + side * 42, 140)
            stroke(whiskers, color: pigment(0xADAAA5, alpha: 0.84), width: 0.72, in: c)
        }
    }

    private static func drawEye(in c: CGContext, x: CGFloat, y: CGFloat, side: CGFloat, gaze: CGVector, blink: CGFloat) {
        let open = max(0, 1 - blink)
        c.saveGState()
        defer { c.restoreGState() }
        c.translateBy(x: x, y: y)
        c.rotate(by: 0.06 * side)
        if open < 0.065 {
            let lid = CGMutablePath()
            lid.begin(-12, 1)
            lid.bend(-6, -2, 7, -2, 12, 1)
            stroke(lid, color: pigment(0x9AAB83), width: 1.35, in: c)
            return
        }
        c.scaleBy(x: 1, y: open)
        let eye = CGMutablePath()
        eye.begin(-12.7, -0.2)
        eye.bend(-12, 8.5, -6.8, 11.7, 0, 11.5)
        eye.bend(6.6, 11.4, 11.8, 7.5, 12.7, 0.1)
        eye.bend(11.8, -8.4, 6.7, -11.4, 0, -11.3)
        eye.bend(-7.2, -11.4, -12.3, -7.3, -12.7, -0.2)
        eye.closeSubpath()
        wash(eye, top: pigment(0xE4F394), bottom: pigment(0xA8D97D), in: c)
        c.addPath(eye)
        c.clip()
        let px = max(-1, min(gaze.dx, 1)) * 5.4
        let py = max(-1, min(gaze.dy, 1)) * 3.4
        c.setFillColor(pigment(0x1A2720))
        c.fillEllipse(in: CGRect(x: px - 5.1, y: py - 7.6, width: 10.2, height: 15.2))
        c.setFillColor(pigment(0xFFFAD8))
        c.fillEllipse(in: CGRect(x: px - 2.7, y: py + 2.7, width: 3.1, height: 3.2))
    }

    static func drawPaws(in c: CGContext, leftPress: CGFloat, rightPress: CGFloat, reach: CGFloat, mouse: CGPoint, mousePress: CGFloat, leftTarget: CGPoint?, rightTarget: CGPoint?) {
        let leftRest = CGPoint(x: 128, y: 56.5)
        let rightRest = CGPoint(x: 175, y: 56.5)
        let keyLeft = blend(leftRest, leftTarget ?? CGPoint(x: 123, y: 44), leftPress)
        let keyRight = blend(rightRest, rightTarget ?? CGPoint(x: 179, y: 45), rightPress)
        let mouseTip = CGPoint(x: mouse.x + 1.2, y: mouse.y + 7 - mousePress * 2.6)
        var left = blend(keyLeft, mouseTip, reach)
        left.y += sin(reach * .pi) * 5
        c.saveGState()
        defer { c.restoreGState() }
        c.setLineCap(.round)
        drawLeg(in: c, shoulder: CGPoint(x: 133 - 37 * reach, y: 108 - reach * 10), tip: left)
        drawLeg(in: c, shoulder: CGPoint(x: 175 - 20 * reach, y: 109), tip: keyRight)
    }

    private static func drawLeg(in c: CGContext, shoulder: CGPoint, tip: CGPoint) {
        let deltaX = tip.x - shoulder.x
        let deltaY = tip.y - shoulder.y
        let distance = max(1, hypot(deltaX, deltaY))
        let nx = -deltaY / distance
        let ny = deltaX / distance
        let bend = min(8, abs(deltaX) * 0.13)
        func point(_ progress: CGFloat, _ width: CGFloat) -> CGPoint {
            let offset = width + sin(.pi * progress) * bend
            return CGPoint(x: shoulder.x + progress * deltaX + nx * offset,
                           y: shoulder.y + progress * deltaY + ny * offset)
        }
        let leg = CGMutablePath()
        leg.move(to: point(0, 8))
        leg.addCurve(to: point(0.88, 5.8), control1: point(0.33, 9.5), control2: point(0.66, 5.4))
        leg.addCurve(to: point(0.93, -6.1), control1: point(1.07, 8.0), control2: point(1.09, -6.8))
        leg.addCurve(to: point(0, -9), control1: point(0.72, -6.1), control2: point(0.34, -10))
        leg.addQuadCurve(to: point(0, 8), control: point(-0.15, -1))
        leg.closeSubpath()
        wash(leg, top: pigment(0x343337), bottom: pigment(0x202125), in: c, edge: false)
        c.saveGState()
        defer { c.restoreGState() }
        c.addPath(leg)
        c.clip()
        let edge = CGMutablePath()
        edge.move(to: point(0.40, 7.7))
        edge.addQuadCurve(to: point(0.88, 5.6), control: point(0.70, 5.7))
        stroke(edge, color: pigment(0x626064, alpha: 0.65), width: 0.72, in: c)
        for toe in [-1.8, 2.0] {
            let crease = CGMutablePath()
            crease.move(to: point(0.98, toe))
            crease.addQuadCurve(to: point(0.95, toe + 0.4), control: point(0.96, toe))
            stroke(crease, color: rim, width: 0.85, in: c)
        }
    }

    private static func blend(_ a: CGPoint, _ b: CGPoint, _ amount: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount)
    }

    private static func pigment(_ rgb: Int, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }

    private static func fill(_ path: CGPath, color: CGColor, in c: CGContext) {
        c.setFillColor(color)
        c.addPath(path)
        c.fillPath()
    }

    private static func stroke(_ path: CGPath, color: CGColor, width: CGFloat, in c: CGContext) {
        c.setStrokeColor(color)
        c.setLineWidth(width)
        c.addPath(path)
        c.strokePath()
    }

    private static func wash(_ path: CGPath, top: CGColor, bottom: CGColor, in c: CGContext, edge: Bool = true) {
        let bounds = path.boundingBoxOfPath
        c.saveGState()
        c.addPath(path)
        c.clip()
        if let paint = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottom, top] as CFArray, locations: [0, 1]) {
            c.drawLinearGradient(paint, start: CGPoint(x: bounds.midX, y: bounds.minY), end: CGPoint(x: bounds.midX, y: bounds.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        } else {
            c.setFillColor(top)
            c.fill(bounds)
        }
        c.restoreGState()
        if edge { stroke(path, color: outline, width: 1.15, in: c) }
    }
}

private extension CGMutablePath {
    func begin(_ x: CGFloat, _ y: CGFloat) { move(to: CGPoint(x: x, y: y)) }
    func lineTo(_ x: CGFloat, _ y: CGFloat) { addLine(to: CGPoint(x: x, y: y)) }
    func bend(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
    }
}
