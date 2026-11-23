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

    // The head, chest, ears and tail move together. A small lean keeps the mouse within reach.
    private static func pose(_ reach: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: 160 - 14 * reach, y: 42 - 1.2 * reach)
            .rotated(by: 0.047 * reach)
            .translatedBy(x: -160, y: -42)
    }

    static func eyeCenter(mouseReach: CGFloat, character: PetCharacter = .cat) -> CGPoint {
        if let portrait = CompanionPortrait.forCharacter(character) {
            return portrait.eyeCenter.applying(pose(mouseReach))
        }
        let scale = kittenRect.width / spriteSize
        return CGPoint(x: kittenRect.minX + (eyes[0] + eyes[1]) * 0.5 * scale,
                       y: kittenRect.minY + 733 * scale).applying(pose(mouseReach))
    }

    static func draw(
        in context: CGContext, gaze: CGVector, blink: CGFloat,
        leftPress: CGFloat, rightPress: CGFloat, keyIndex: Int?,
        leftKey: Int? = nil, rightKey: Int? = nil,
        mouseReach: CGFloat = 0, mouseOffset: CGVector = .zero, mousePress: CGFloat = 0,
        character: PetCharacter = .cat
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.interpolationQuality = .high

        let reach = min(1, max(0, mouseReach))
        let body = pose(reach)
        let portrait = CompanionPortrait.forCharacter(character)
        context.saveGState()
        context.concatenate(body)
        if let portrait {
            portrait.drawBody(in: context, gaze: gaze, blink: blink)
        } else if let kitten {
            context.draw(kitten, in: kittenRect)
            drawEyes(in: context, gaze: gaze, blink: blink)
        }
        context.restoreGState()

        PetKeyboard.draw(in: context, activeKey: keyIndex)
        let mouse = CGPoint(x: 83.5 + 0.35 * mouseOffset.dx, y: 55.5 + 0.50 * mouseOffset.dy)
        drawMouse(in: context, at: mouse, press: mousePress)

        let left = keyContact(rest: CGPoint(x: 133, y: 51), key: leftKey, press: leftPress)
        let right = keyContact(rest: CGPoint(x: 182, y: 51), key: rightKey, press: rightPress)
        let mouseToe = CGPoint(x: mouse.x + 0.5, y: mouse.y - 1 - mousePress * 1.9)
        let movingToe = CGPoint(x: left.x + (mouseToe.x - left.x) * reach,
                                y: left.y + (mouseToe.y - left.y) * reach + sin(.pi * reach) * 5)
        let rightShoulder = CGPoint(x: 185, y: 80).applying(body)
        let leftShoulder = CGPoint(x: 127, y: 80).applying(body)
        if let portrait {
            portrait.drawPaw(in: context, toe: right, shoulder: rightShoulder)
            portrait.drawPaw(in: context, toe: movingToe, shoulder: leftShoulder)
        } else {
            drawPaw(in: context, toe: right, shoulder: rightShoulder, mirror: false)
            drawPaw(in: context, toe: movingToe, shoulder: leftShoulder, mirror: true)
        }
    }

    private static func keyContact(rest: CGPoint, key: Int?, press: CGFloat) -> CGPoint {
        let target = key.flatMap(PetKeyboard.center(for:)) ?? CGPoint(x: rest.x, y: rest.y - 10)
        let amount = min(1, max(0, press))
        return CGPoint(x: rest.x + (target.x - rest.x) * amount,
                       y: rest.y + (target.y - rest.y) * amount)
    }

    private static func drawEyes(in context: CGContext, gaze: CGVector, blink: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: kittenRect.minX, y: kittenRect.minY)
        context.scaleBy(x: kittenRect.width / spriteSize, y: kittenRect.height / spriteSize)
        let xOffset = min(max(gaze.dx, -1), 1) * 37
        let yOffset = min(max(gaze.dy, -1), 1) * 27
        let blinkAmount = min(max(blink, 0), 1)

        for x in eyes {
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
                let lidY = y + 108 - 179 * blinkAmount
                let lid = shape(x - 122, y + 113, closed: true) {
                    $0.line(x + 122, y + 113)
                    $0.line(x + 122, lidY + 18)
                    $0.curve(x + 61, lidY - 12, x - 61, lidY - 12, x - 122, lidY + 18)
                }
                gradient(lid, top: color(0x4B403C), bottom: color(0x2D2424),
                         minY: lidY, maxY: y + 109, in: context)
                let lowerLid = shape(x - 122, y - 109, closed: true) {
                    $0.line(x + 122, y - 109)
                    $0.line(x + 122, y - 111 + 42 * blinkAmount)
                    $0.curve(x + 55, y - 118 + 45 * blinkAmount,
                             x - 55, y - 118 + 45 * blinkAmount,
                             x - 122, y - 111 + 42 * blinkAmount)
                }
                fill(lowerLid, with: color(0x332827), in: context)
            }
            context.restoreGState()
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

    // A single, fixed-size furry forepaw pivots from the chest. Only its angle and
    // contact point change, keeping the toes the same size on the mouse and keys.
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

    private static func drawPaw(in context: CGContext, toe: CGPoint, shoulder: CGPoint, mirror: Bool) {
        guard let pawImage else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: toe.x, y: toe.y)
        context.rotate(by: atan2(toe.x - shoulder.x, shoulder.y - toe.y))
        if mirror { context.scaleBy(x: -1, y: 1) }
        context.draw(pawImage, in: pawFrame)
    }

    private static func drawMouse(in context: CGContext, at center: CGPoint, press: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: 0.82, y: 0.87)
        context.setFillColor(CGColor(gray: 0.08, alpha: 0.13))
        context.fillEllipse(in: CGRect(x: -10.5, y: -12.5, width: 21, height: 6))

        let shell = CGRect(x: -10, y: -11, width: 20, height: 23 - 1.5 * press)
        context.setFillColor(CGColor(gray: 0.24, alpha: 1))
        context.fillEllipse(in: shell.offsetBy(dx: 0, dy: -1.0))
        context.setFillColor(CGColor(srgbRed: 0.96 - 0.20 * press, green: 0.95 + 0.02 * press,
                                     blue: 0.90 - 0.31 * press, alpha: 1))
        context.fillEllipse(in: shell)
        let wheel = CGPath(roundedRect: CGRect(x: -1.15, y: 2 - press, width: 2.3, height: 5.5),
                           cornerWidth: 1.1, cornerHeight: 1.1, transform: nil)
        context.setFillColor(CGColor(srgbRed: 0.55, green: 0.57, blue: 0.51, alpha: 1))
        context.addPath(wheel)
        context.fillPath()
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
