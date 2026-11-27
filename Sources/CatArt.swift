import AppKit
import ImageIO

enum CatArt {
    static let size = NSSize(width: 320, height: 250)

    private static let kittenRect = CGRect(x: 68, y: 24, width: 184, height: 184)
    private static let spriteSize: CGFloat = 1_254
    private static let eyes: [CGFloat] = [411, 831]
    private static let ink = color(0x2B2425)
    private static let kitten: CGImage? = {
        guard let url = Bundle.main.url(forResource: "Kitten", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    private static let kittenSkin = kitten.map { PortraitSkin(image: $0, frame: kittenRect, neck: PortraitMotion.neck(for: .cat)) }

    static func eyeCenter(mouseReach: CGFloat, character: PetCharacter = .cat) -> CGPoint {
        let eye = restEyeCenter(character)
        return eye.applying(PortraitMotion(neck: PortraitMotion.neck(for: character), reach: mouseReach).head)
    }

    private static func restEyeCenter(_ character: PetCharacter) -> CGPoint {
        if let portrait = CompanionPortrait.forCharacter(character) { return portrait.eyeCenter }
        let scale = kittenRect.width / spriteSize
        return CGPoint(x: kittenRect.minX + (eyes[0] + eyes[1]) * 0.5 * scale, y: kittenRect.minY + 733 * scale)
    }

    static func faceSpot(offsetFromEyes: CGVector, character: PetCharacter, reach: CGFloat, reaction: PetAffectionPose) -> CGPoint {
        var p = restEyeCenter(character)
        p.x += offsetFromEyes.dx
        p.y += offsetFromEyes.dy
        let rig = PortraitMotion(neck: PortraitMotion.neck(for: character), reach: reach, affection: reaction)
        return rig.map(p)
    }

    static func draw(
        in context: CGContext, gaze: CGVector, blink: CGFloat,
        leftPress: CGFloat, rightPress: CGFloat, keyIndex: Int?,
        leftKey: Int? = nil, rightKey: Int? = nil,
        mouseReach: CGFloat = 0, mouseOffset: CGVector = .zero, mousePress: CGFloat = 0,
        wheel: MouseWheelMotion.Pose = .init(), character: PetCharacter = .cat, scene: DeskScene.Frame? = nil,
        affection: PetAffectionPose = .neutral, life: CGFloat = 0, typingWeight: CGFloat = 0,
        leftOrigin: CGPoint? = nil, rightOrigin: CGPoint? = nil,
        underPaws: ((CGContext) -> Void)? = nil
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.interpolationQuality = .high

        let reach = min(1, max(0, mouseReach))
        let rig = PortraitMotion(neck: PortraitMotion.neck(for: character), reach: reach, scene: scene,
                                 affection: affection, life: life, weight: typingWeight)
        let glance = abs(wheel.travel) * reach * 0.24
        let mouseGaze = CGVector(dx: gaze.dx + (-0.7 - gaze.dx) * glance, dy: gaze.dy + (-0.85 - gaze.dy) * glance)
        let gaze = scene?.gaze ?? affection.gaze ?? mouseGaze
        let blink = max(blink, affection.blink)
        let portrait = CompanionPortrait.forCharacter(character)
        if let portrait {
            portrait.drawBody(in: context, gaze: gaze, blink: blink, motion: rig)
        } else if let kittenSkin {
            kittenSkin.draw(in: context, motion: rig)
            context.saveGState()
            context.concatenate(rig.head)
            drawEyes(in: context, gaze: gaze, blink: blink)
            context.restoreGState()
        }

        let pressure = keyIndex == leftKey ? leftPress : rightPress
        PetKeyboard.draw(in: context, activeKey: keyIndex, hiddenKey: scene?.hiddenKey, pressure: pressure)
        let mouse = CGPoint(x: 83.5 + 0.35 * mouseOffset.dx, y: 55.5 + 0.50 * mouseOffset.dy)
        drawMouse(in: context, at: mouse, press: mousePress, turn: wheel.turn)

        let left = keyContact(rest: affection.leftToe ?? CGPoint(x: 133, y: 51), key: leftKey, press: leftPress, origin: leftOrigin)
        let right = scene?.rightToe ?? keyContact(rest: affection.rightToe ?? CGPoint(x: 182, y: 51), key: rightKey, press: rightPress, origin: rightOrigin)
        let mouseToe = CGPoint(x: mouse.x + 0.5 + 2.7 * wheel.contact + 1.6 * wheel.lift,
                               y: mouse.y - 1 - mousePress * 1.9 + 0.8 * wheel.contact - 6.0 * wheel.travel + 2 * wheel.lift)
        let movingToe = scene?.leftToe ?? CGPoint(x: left.x + (mouseToe.x - left.x) * reach,
                                y: left.y + (mouseToe.y - left.y) * reach + sin(.pi * reach) * 5)
        for tip in [right, movingToe] where tip.y < 63 {
            let contact = max(0, min(1, (64 - tip.y) / 18))
            context.setFillColor(CGColor(gray: 0.08, alpha: 0.045 + contact * 0.06))
            context.fillEllipse(in: CGRect(x: tip.x - 7.2, y: tip.y - 2.5, width: 14.4, height: 3.8))
        }
        let rightShoulder = rig.map(CGPoint(x: 185, y: 84))
        let leftShoulder = rig.map(CGPoint(x: 127, y: 84))
        func paws(_ layer: PortraitLimb.Layer) {
            if let portrait {
                portrait.drawPaw(in: context, toe: right, shoulder: rightShoulder, side: 1,
                                 hold: scene?.grip ?? 0, layer: layer)
                portrait.drawPaw(in: context, toe: movingToe, shoulder: leftShoulder, side: -1,
                                 hold: scene?.leftGrip ?? 0, layer: layer)
            } else {
                kittenLimb?.draw(in: context, shoulder: rightShoulder, toe: right, side: 1, grip: 0, gripImage: nil, hoof: false, layer: layer)
                kittenLimb?.draw(in: context, shoulder: leftShoulder, toe: movingToe, side: -1, grip: 0, gripImage: nil, hoof: false, layer: layer)
            }
        }
        // She wraps her paws around the trophy's sides. The wrists are behind
        // the cap, with just the curved fingertips visible over its face.
        let holdingCap = scene?.rascalCap != nil
        if holdingCap { paws(.arm) }
        scene?.draw(in: context)
        underPaws?(context)
        paws(holdingCap ? .fingers : .complete)
        scene?.drawForeground(in: context)
    }

    static func keyContact(rest: CGPoint, key: Int?, press: CGFloat, origin: CGPoint? = nil) -> CGPoint {
        let target = key.flatMap(PetKeyboard.center(for:)) ?? CGPoint(x: rest.x, y: rest.y - 10)
        let amount = min(1, max(0, press))
        let start = origin ?? rest
        return CGPoint(x: start.x + (target.x - start.x) * amount,
                       y: start.y + (target.y - start.y) * amount)
    }

    // These two small forehead patches follow the fur direction on each side of the face.
    private static let lidCoats = eyes.map { x in
        kitten?.cropping(to: CGRect(x: x - 107, y: 318, width: 214, height: 80))
    }

    private static let relaxedLids = lidCoats.map { coat -> CGImage? in
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let coat, let c = CGContext(data: nil, width: 322, height: 292, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let feather = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1),
                                                                     CGColor(gray: 1, alpha: 0)] as CFArray,
                                       locations: [0, 0.79, 1]) else { return nil }
        c.draw(coat, in: CGRect(x: 0, y: 0, width: 322, height: 292))
        c.translateBy(x: 161, y: 146)
        c.scaleBy(x: 161, y: 146)
        c.setBlendMode(.destinationIn)
        c.drawRadialGradient(feather, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1,
                             options: [.drawsAfterEndLocation])
        return c.makeImage()
    }

    private static func drawEyes(in context: CGContext, gaze: CGVector, blink: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: kittenRect.minX, y: kittenRect.minY)
        context.scaleBy(x: kittenRect.width / spriteSize, y: kittenRect.height / spriteSize)
        let xOffset = min(max(gaze.dx, -1), 1) * 37
        let yOffset = min(max(gaze.dy, -1), 1) * 27
        let blinkAmount = min(max(blink, 0), 1)

        for (i, x) in eyes.enumerated() {
            let y: CGFloat = 733
            let eye = shape(x, y + 105, closed: true) {
                $0.curve(x + 61, y + 105, x + 114, y + 57, x + 115, y - 2)
                $0.curve(x + 120, y - 64, x + 78, y - 102, x, y - 105)
                $0.curve(x - 78, y - 107, x - 119, y - 68, x - 115, y - 7)
                $0.curve(x - 111, y + 54, x - 62, y + 106, x, y + 105)
            }
            context.saveGState()
            context.addPath(eye)
            context.clip()
            drawPupil(in: context, x: x + xOffset, y: y + yOffset)

            if blinkAmount > 0.03 {
                let closed = min(1, blinkAmount / 0.94)
                let upperY = y + 128 - 154 * closed
                let lowerY = y - 114 + 92 * closed
                let lid = CGMutablePath()
                lid.move(to: CGPoint(x: x - 125, y: upperY))
                lid.addQuadCurve(to: CGPoint(x: x + 125, y: upperY), control: CGPoint(x: x, y: upperY - 22))
                lid.addLine(to: CGPoint(x: x + 125, y: y + 125))
                lid.addLine(to: CGPoint(x: x - 125, y: y + 125)); lid.closeSubpath()
                lid.move(to: CGPoint(x: x - 125, y: lowerY))
                lid.addQuadCurve(to: CGPoint(x: x + 125, y: lowerY), control: CGPoint(x: x, y: lowerY - 22))
                lid.addLine(to: CGPoint(x: x + 125, y: y - 125))
                lid.addLine(to: CGPoint(x: x - 125, y: y - 125)); lid.closeSubpath()
                context.saveGState()
                context.addPath(lid); context.clip()
                context.setFillColor(color(0x342D2C))
                context.fill(CGRect(x: x - 125, y: y - 125, width: 250, height: 250))
                if let coat = lidCoats[i] {
                    context.draw(coat, in: CGRect(x: x - 125, y: y - 115, width: 250, height: 230))
                }
                context.restoreGState()
                let crease = CGMutablePath()
                crease.move(to: CGPoint(x: x - 123, y: upperY + 1))
                crease.addQuadCurve(to: CGPoint(x: x + 123, y: upperY + 1), control: CGPoint(x: x, y: upperY - 21))
                stroke(crease, with: color(0x241C1C).copy(alpha: 0.86 * closed)!, width: 7, in: context)
            }
            context.restoreGState()
            // At full closure the fur crosses the rim as well as the iris.
            // The tapered crease ends before the edge of the relaxed lid.
            if blinkAmount > 0.67, let coat = relaxedLids[i] {
                let t = min(1, (blinkAmount - 0.67) / 0.27)
                context.saveGState()
                context.setAlpha(t * t * (3 - 2 * t))
                context.draw(coat, in: CGRect(x: x - 161, y: y - 146, width: 322, height: 292))
                let seam = CGMutablePath()
                seam.move(to: CGPoint(x: x - 89, y: y - 15))
                seam.addQuadCurve(to: CGPoint(x: x + 91, y: y - 13), control: CGPoint(x: x, y: y - 45))
                seam.addQuadCurve(to: CGPoint(x: x - 89, y: y - 15), control: CGPoint(x: x, y: y - 57))
                seam.closeSubpath()
                fill(seam, with: color(0x201A19), in: context)
                context.restoreGState()
            }
        }
    }

    private static func drawPupil(in context: CGContext, x: CGFloat, y: CGFloat) {
        let rim = CGPath(ellipseIn: CGRect(x: x - 64, y: y - 76, width: 128, height: 154), transform: nil)
        gradient(rim, top: color(0x487247), bottom: color(0x648648), minY: y - 76, maxY: y + 78, in: context)
        let pupil = CGPath(ellipseIn: CGRect(x: x - 57, y: y - 72, width: 114, height: 144), transform: nil)
        gradient(pupil, top: color(0x131D18), bottom: color(0x252C19), minY: y - 72, maxY: y + 72, in: context)
        ellipse(x: x - 33, y: y + 21, width: 32, height: 31, with: color(0xFFFCEC), in: context)
        ellipse(x: x + 20, y: y - 35, width: 13, height: 13, with: color(0xB9D69D), in: context)
    }

    // The toes keep their shape. The patch above the wrist covers the small
    // gap to the chest when the paw reaches the far edge of the keyboard.
    private static let pawFrame = CGRect(x: -12, y: -2, width: 24, height: 37)
    private static let pawImage: CGImage? = {
        guard let coat = kitten?.cropping(to: CGRect(x: 438, y: 927, width: 283, height: 250)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: 96, height: 148, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        c.scaleBy(x: 4, y: 4)
        c.translateBy(x: -pawFrame.minX, y: -pawFrame.minY)
        c.setLineCap(.round)
        let paw = shape(-5.8, 33, closed: true) {
            $0.curve(-8.2, 28, -7.2, 22, -8.6, 17)
            $0.curve(-9.2, 14, -10.1, 12, -10.4, 9)
            $0.curve(-11, 5.1, -9.4, 2.1, -6.2, 1.7)
            $0.curve(-4.4, 0.3, -1.4, 0.1, 0.1, 1)
            $0.curve(3, 0.0, 6.3, 1.4, 7.1, 3)
            $0.curve(9.8, 4.2, 10.8, 7.5, 10, 11)
            $0.curve(9.5, 14.4, 8.1, 17.5, 8.7, 22)
            $0.curve(9.9, 30.5, 7.2, 34, 2, 34)
            $0.curve(-0.9, 34.1, -3.5, 34.3, -5.8, 33)
        }
        c.addPath(paw)
        c.clip()
        c.draw(coat, in: pawFrame)
        let toeEdge = shape(-10.4, 8.5) {
            $0.curve(-10.6, 5, -9.3, 2.2, -6.2, 1.7)
            $0.curve(-4.4, 0.4, -1.4, 0.1, 0.1, 1)
            $0.curve(2.9, 0.3, 5.8, 1.4, 7.1, 3)
        }
        stroke(toeEdge, with: color(0x856C60).copy(alpha: 0.56)!, width: 0.8, in: c)
        let toes = shape(-5.1, 1.7) {
            $0.curve(-6.1, 3.7, -5.7, 5.4, -5.2, 6.4)
            $0.move(to: CGPoint(x: 0.7, y: 1.2))
            $0.curve(-0.2, 2.8, 0.1, 4.7, 0.7, 5.4)
        }
        stroke(toes, with: color(0x79665A).copy(alpha: 0.72)!, width: 0.70, in: c)
        // Feather the shoulder into the original coat instead of outlining the joint.
        let mask = CGGradient(colorsSpace: space, colors: [
            CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)
        ] as CFArray, locations: [0, 1])!
        c.setBlendMode(.destinationIn)
        c.drawLinearGradient(mask, start: CGPoint(x: 0, y: 28), end: CGPoint(x: 0, y: 34),
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return c.makeImage()
    }()

    private static let kittenLimb: PortraitLimb? = {
        guard let coat = kitten?.cropping(to: CGRect(x: 438, y: 927, width: 283, height: 250)), let pawImage else { return nil }
        return PortraitLimb(fur: coat, straightPaw: pawImage)
    }()

    private static func drawMouse(in context: CGContext, at center: CGPoint, press: CGFloat, turn: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: 0.82, y: 0.87)
        context.setFillColor(CGColor(gray: 0.08, alpha: 0.13))
        context.fillEllipse(in: CGRect(x: -10.5, y: -12.5, width: 21, height: 6))

        let shell = CGRect(x: -10, y: -11, width: 20, height: 23 - 1.5 * press)
        context.setFillColor(CGColor(gray: 0.24, alpha: 1))
        context.fillEllipse(in: shell.offsetBy(dx: 0, dy: -1.0))
        let shellPath = CGPath(ellipseIn: shell, transform: nil)
        let rubberRim = CGColor(srgbRed: 0.76 - 0.035 * press, green: 0.75 - 0.03 * press,
                                 blue: 0.69 - 0.035 * press, alpha: 1)
        gradient(shellPath, top: color(0xFFFAEA), bottom: rubberRim,
                 minY: shell.minY - 1, maxY: shell.midY + 3.0, in: context)
        let buttonSeam = shape(0, shell.maxY - 0.8) { $0.line(0, 0.8 - press) }
        stroke(buttonSeam, with: CGColor(gray: 0.43, alpha: 0.40), width: 0.50, in: context)
        let tread = CGRect(x: -1.6, y: 1.4 - press, width: 3.2, height: 6.7)
        let wheel = CGPath(roundedRect: tread, cornerWidth: 1.4, cornerHeight: 1.4, transform: nil)
        gradient(wheel, top: color(0x74766B), bottom: color(0x999B8C), minY: tread.minY, maxY: tread.maxY, in: context)
        context.addPath(wheel)
        context.clip()
        let pitch: CGFloat = 2.4
        let shift = (turn - floor(turn)) * pitch
        context.setFillColor(color(0xC6C8B7))
        for index in 0...4 {
            context.fill(CGRect(x: tread.minX + 0.3, y: tread.minY + CGFloat(index) * pitch - shift,
                                width: tread.width - 0.6, height: 0.68))
        }
    }

    private static func color(_ hex: UInt32) -> CGColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        ).cgColor
    }

    private static func shape(
        _ x: CGFloat, _ y: CGFloat, closed: Bool = false,
        _ draw: (CGMutablePath) -> Void
    ) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: y))
        draw(path)
        if closed { path.closeSubpath() }
        return path
    }

    private static func fill(_ path: CGPath, with color: CGColor, in context: CGContext) {
        context.setFillColor(color)
        context.addPath(path)
        context.fillPath()
    }

    private static func stroke(
        _ path: CGPath, with color: CGColor, width: CGFloat, in context: CGContext
    ) {
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.addPath(path)
        context.strokePath()
    }

    private static func ellipse(
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, with color: CGColor,
        in context: CGContext
    ) {
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: x, y: y, width: width, height: height))
    }

    private static func gradient(
        _ path: CGPath, top: CGColor, bottom: CGColor, minY: CGFloat, maxY: CGFloat,
        in context: CGContext
    ) {
        guard let gradient = CGGradient(colorsSpace: nil, colors: [bottom, top] as CFArray, locations: nil)
        else {
            fill(path, with: bottom, in: context)
            return
        }

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: minY), end: CGPoint(x: 0, y: maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }
}

private extension CGMutablePath {
    func line(_ x: CGFloat, _ y: CGFloat) {
        addLine(to: CGPoint(x: x, y: y))
    }

    func curve(
        _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat
    ) {
        addCurve(to: CGPoint(x: x, y: y),
                 control1: CGPoint(x: x1, y: y1),
                 control2: CGPoint(x: x2, y: y2))
    }
}
