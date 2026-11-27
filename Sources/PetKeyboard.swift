import AppKit
import Carbon
import CoreText

/// The pet faces the viewer. A keyboard's bottom row therefore sits closest to
/// the pet, and the pet's leftmost keys appear on the viewer's right.
enum PetKeyboard {
    private struct Key {
        let code: Int?
        let legend: String
        let units: CGFloat

        init(_ code: Int?, _ legend: String, _ units: CGFloat = 1) {
            self.code = code
            self.legend = legend
            self.units = units
        }
    }

    private struct Cap {
        let key: Key
        let frame: CGRect
        let line: CTLine
        let ink: CGRect
        let finish: Finish
    }

    private struct Finish {
        let skirt: CGColor
        let crown: CGGradient
        let ink: CGColor

        init(_ skirt: UInt32, _ low: UInt32, _ high: UInt32, _ ink: UInt32) {
            self.skirt = color(skirt)
            crown = gradient(low, high)
            self.ink = color(ink)
        }
    }

    // Contact geometry belongs to the switch plate. The rounded case has a
    // separate front lip so it can have depth without moving any switches.
    private static let shell = CGRect(x: 95, y: 23.5, width: 130, height: 35.5)
    private static let bounds = CGRect(x: 92, y: 16.5, width: 136, height: 45.5)
    private static let well = color(0x62766B)
    private static let caseSide = gradient(0x254943, 0x588879)
    private static let caseTop = gradient(0x599887, 0xA9CDB7)
    private static let rim = color(0xC9D9BE)
    private static let cream = Finish(0xBAA88D, 0xEFDFC4, 0xFFFAE8, 0x645A4A)
    private static let parchment = Finish(0xB5A488, 0xE1CFAB, 0xF2E4C7, 0x655E4E)
    private static let sage = Finish(0x829B88, 0xB2C9B0, 0xD6E5C9, 0x476357)
    private static let orange = Finish(0xAE5325, 0xE78232, 0xFFAC5E, 0x60351D)
    private static let illuminated = Finish(0x6D964F, 0xBFD984, 0xE1F3A9, 0x354F3D)

    // In the pet's reading order. The power key is visible, but macOS does
    // not send it through the application's ordinary keyboard event stream.
    private static let rows: [[Key]] = [
        [Key(kVK_Escape, "esc", 1.3), Key(kVK_F1, "F1"), Key(kVK_F2, "F2"), Key(kVK_F3, "F3"),
         Key(kVK_F4, "F4"), Key(kVK_F5, "F5"), Key(kVK_F6, "F6"), Key(kVK_F7, "F7"),
         Key(kVK_F8, "F8"), Key(kVK_F9, "F9"), Key(kVK_F10, "F10"), Key(kVK_F11, "F11"),
         Key(kVK_F12, "F12"), Key(nil, "⏻")],
        [Key(kVK_ANSI_Grave, "`"), Key(kVK_ANSI_1, "1"), Key(kVK_ANSI_2, "2"), Key(kVK_ANSI_3, "3"),
         Key(kVK_ANSI_4, "4"), Key(kVK_ANSI_5, "5"), Key(kVK_ANSI_6, "6"), Key(kVK_ANSI_7, "7"),
         Key(kVK_ANSI_8, "8"), Key(kVK_ANSI_9, "9"), Key(kVK_ANSI_0, "0"), Key(kVK_ANSI_Minus, "-"),
         Key(kVK_ANSI_Equal, "="), Key(kVK_Delete, "⌫", 1.5)],
        [Key(kVK_Tab, "⇥", 1.5), Key(kVK_ANSI_Q, "Q"), Key(kVK_ANSI_W, "W"), Key(kVK_ANSI_E, "E"),
         Key(kVK_ANSI_R, "R"), Key(kVK_ANSI_T, "T"), Key(kVK_ANSI_Y, "Y"), Key(kVK_ANSI_U, "U"),
         Key(kVK_ANSI_I, "I"), Key(kVK_ANSI_O, "O"), Key(kVK_ANSI_P, "P"), Key(kVK_ANSI_LeftBracket, "["),
         Key(kVK_ANSI_RightBracket, "]"), Key(kVK_ANSI_Backslash, "\\")],
        [Key(kVK_CapsLock, "⇪", 1.75), Key(kVK_ANSI_A, "A"), Key(kVK_ANSI_S, "S"), Key(kVK_ANSI_D, "D"),
         Key(kVK_ANSI_F, "F"), Key(kVK_ANSI_G, "G"), Key(kVK_ANSI_H, "H"), Key(kVK_ANSI_J, "J"),
         Key(kVK_ANSI_K, "K"), Key(kVK_ANSI_L, "L"), Key(kVK_ANSI_Semicolon, ";"),
         Key(kVK_ANSI_Quote, "'"), Key(kVK_Return, "↩", 1.75)],
        [Key(kVK_Shift, "⇧", 2.15), Key(kVK_ANSI_Z, "Z"), Key(kVK_ANSI_X, "X"), Key(kVK_ANSI_C, "C"),
         Key(kVK_ANSI_V, "V"), Key(kVK_ANSI_B, "B"), Key(kVK_ANSI_N, "N"), Key(kVK_ANSI_M, "M"),
         Key(kVK_ANSI_Comma, ","), Key(kVK_ANSI_Period, "."), Key(kVK_ANSI_Slash, "/"),
         Key(kVK_RightShift, "⇧", 2.35)],
        [Key(kVK_Function, "fn"), Key(kVK_Control, "⌃"), Key(kVK_Option, "⌥"), Key(kVK_Command, "⌘", 1.25),
         Key(kVK_Space, "", 5), Key(kVK_RightCommand, "⌘", 1.25), Key(kVK_RightOption, "⌥"),
         Key(kVK_LeftArrow, "←"), Key(kVK_DownArrow, "↓"), Key(kVK_RightArrow, "→")]
    ]

    private static let caps: [Cap] = {
        var result: [Cap] = []
        let gap: CGFloat = 0.66
        let rowGap: CGFloat = 0.56
        let rowWidth = shell.width - 6
        var y = shell.minY + 2.6
        for (rowNumber, row) in rows.enumerated() {
            let height: CGFloat = rowNumber == 0 ? 3.95 : 4.85
            let totalUnits = row.reduce(CGFloat.zero) { $0 + $1.units }
            let unit = (rowWidth - CGFloat(row.count - 1) * gap) / totalUnits
            var x = shell.maxX - 3
            for key in row {
                let width = key.units * unit
                x -= width
                var rect = CGRect(x: x, y: y, width: width, height: height)
                var fontSize: CGFloat = rowNumber == 0 ? 2.70 : 3.55
                if [kVK_LeftArrow, kVK_DownArrow, kVK_RightArrow].contains(key.code ?? -1) {
                    rect.size.height = (height - 0.42) / 2
                    fontSize = 2.65
                    if key.code == kVK_DownArrow {
                        result.append(makeCap(Key(kVK_UpArrow, "↑"), in: rect, fontSize: fontSize))
                    }
                    rect.origin.y = y + height - rect.height
                }
                result.append(makeCap(key, in: rect, fontSize: fontSize))
                x -= gap
            }
            y += height + rowGap
        }
        return result
    }()

    private static func makeCap(_ key: Key, in frame: CGRect, fontSize: CGFloat) -> Cap {
        let finish: Finish
        switch key.code {
        case kVK_Escape: finish = orange
        case kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_Return, kVK_Space, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            finish = sage
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
             kVK_Shift, kVK_RightShift, kVK_CapsLock, kVK_Tab, kVK_Delete, kVK_Function,
             kVK_Option, kVK_RightOption, kVK_Control, kVK_Command, kVK_RightCommand:
            finish = parchment
        default: finish = cream
        }
        let text = NSAttributedString(string: key.legend, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ])
        let line = CTLineCreateWithAttributedString(text)
        return Cap(key: key, frame: frame, line: line, ink: CTLineGetBoundsWithOptions(line, .useGlyphPathBounds),
                   finish: finish)
    }

    private static let byCode = Dictionary(uniqueKeysWithValues: caps.compactMap { cap in
        cap.key.code.map { ($0, cap) }
    })

    static func center(for code: Int) -> CGPoint? {
        guard let rect = byCode[code]?.frame else { return nil }
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    static func usesScreenRightPaw(for code: Int?, rightHand: Bool) -> Bool {
        guard let x = code.flatMap(center(for:))?.x else { return !rightHand }
        return x >= shell.midX
    }

    // Demo notes have no hardware event. Real presses always use their Mac key code.
    static func code(forDemoLabel label: String) -> Int? {
        if label == "↵" { return kVK_Return }
        if label == "空格" { return kVK_Space }
        return caps.first { $0.key.legend == label }?.key.code
    }

    private static func color(_ value: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    private static func pill(_ c: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor) {
        c.setFillColor(color)
        c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        c.fillPath()
    }

    private static func gradient(_ low: UInt32, _ high: UInt32) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                   colors: [color(low), color(high)] as CFArray, locations: [0, 1])!
    }

    private static func shaded(_ c: CGContext, _ path: CGPath, tint: CGGradient) {
        let rect = path.boundingBoxOfPath
        c.saveGState()
        c.addPath(path)
        c.clip()
        c.drawLinearGradient(tint, start: CGPoint(x: rect.midX, y: rect.minY),
                             end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        c.restoreGState()
    }

    private static func drawCap(_ cap: Cap, in c: CGContext, pressed: Bool, pressure: CGFloat = 0) {
        let rect = cap.frame
        let finish = pressed ? illuminated : cap.finish
        let relief = min(1.26, rect.height * 0.26)
        let travel = relief * min(1, max(0, pressure)) * 0.88
        let face = CGRect(x: rect.minX + 0.44, y: rect.minY + relief - travel,
                          width: rect.width - 0.88, height: rect.height - relief - 0.12)
        let isSpace = cap.key.code == kVK_Space
        let radius: CGFloat = isSpace ? 1.72 : 1.04
        pill(c, rect, radius: radius + 0.22, color: finish.skirt)
        let crown = CGPath(roundedRect: face, cornerWidth: radius, cornerHeight: radius, transform: nil)
        shaded(c, crown, tint: finish.crown)
        if isSpace {
            // The thumb bar has a broader convex shoulder than the dished alphas.
            let shine = CGRect(x: face.minX + 1.6, y: face.maxY - 0.64,
                               width: face.width - 3.2, height: 0.33)
            pill(c, shine, radius: 0.16, color: CGColor(gray: 1, alpha: 0.72))
        }

        guard !cap.key.legend.isEmpty else { return }
        c.saveGState()
        c.translateBy(x: face.midX, y: face.midY)
        c.scaleBy(x: -1, y: -1)
        c.textMatrix = .identity
        c.setFillColor(finish.ink)
        c.textPosition = CGPoint(x: -cap.ink.midX, y: -cap.ink.midY)
        CTLineDraw(cap.line, c)
        c.restoreGState()
    }

    // Narrow shoulders at the back open out into two rounded front cheeks.
    // Their shallow central scallop is the join between the enamel case halves.
    private static func caseOutline(front: CGFloat, back: CGFloat, halfWidth w: CGFloat,
                                    recess: CGFloat) -> CGPath {
        let x = shell.midX
        func p(_ dx: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y) }
        let path = CGMutablePath()
        path.move(to: p(-w + 8, back))
        path.addLine(to: p(w - 8, back))
        path.addQuadCurve(to: p(w - 2.5, back - 4.4), control: p(w - 3, back))
        path.addLine(to: p(w - 0.15, front + 8.2))
        path.addQuadCurve(to: p(w - 2.2, front + 2.4), control: p(w + 0.5, front + 4.4))
        path.addQuadCurve(to: p(w - 7, front), control: p(w - 4.0, front))
        path.addLine(to: p(w - 15, front))
        path.addCurve(to: p(w - 23, front + recess), control1: p(w - 19, front), control2: p(w - 18, front + recess))
        path.addLine(to: p(-w + 23, front + recess))
        path.addCurve(to: p(-w + 15, front), control1: p(-w + 18, front + recess), control2: p(-w + 19, front))
        path.addLine(to: p(-w + 7, front))
        path.addQuadCurve(to: p(-w + 2.2, front + 2.4), control: p(-w + 4, front))
        path.addQuadCurve(to: p(-w + 0.15, front + 8.2), control: p(-w - 0.5, front + 4.4))
        path.addLine(to: p(-w + 2.5, back - 4.4))
        path.addQuadCurve(to: p(-w + 8, back), control: p(-w + 3, back))
        path.closeSubpath()
        return path
    }

    private static func drawResting(in c: CGContext) {
        let base = caseOutline(front: 18.7, back: 58.7, halfWidth: 65.4, recess: 1.15)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -0.65), blur: 0.8, color: CGColor(gray: 0.10, alpha: 0.32))
        c.setFillColor(well)
        c.addPath(base)
        c.fillPath()
        c.restoreGState()
        shaded(c, base, tint: caseSide)
        let seam = caseOutline(front: 20.6, back: 59.1, halfWidth: 65.8, recess: 1.65)
        c.setFillColor(color(0x30685E))
        c.addPath(seam)
        c.fillPath()
        let deck = caseOutline(front: 21.8, back: 60.5, halfWidth: 65.8, recess: 1.85)
        shaded(c, deck, tint: caseTop)
        let glint = CGRect(x: shell.midX - 39, y: 23.72, width: 78, height: 0.40)
        pill(c, glint, radius: 0.20, color: rim)

        // The small function caps sit in their own lower channel. This exposed
        // strip of case separates the banks without shifting sockets or paws.
        let mainPlate = CGRect(x: 97.35, y: 30.30, width: 125.30, height: 27.55)
        pill(c, mainPlate, radius: 2.1, color: well)
        for cap in caps { drawCap(cap, in: c, pressed: false) }
    }

    private static let restingImage: CGImage? = {
        let scale: CGFloat = 3
        guard let c = CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: -bounds.minX, y: -bounds.minY)
        drawResting(in: c)
        return c.makeImage()
    }()

    static func draw(in c: CGContext, activeKey: Int?, hiddenKey: Int? = nil, pressure: CGFloat = 1) {
        c.saveGState()
        defer { c.restoreGState() }
        if let image = restingImage {
            c.interpolationQuality = .high
            c.draw(image, in: bounds)
        } else {
            drawResting(in: c)
        }
        if let hiddenKey, let cap = byCode[hiddenKey] {
            let r = cap.frame
            pill(c, r.insetBy(dx: -0.15, dy: -0.15), radius: 0.84, color: well)
            let housing = CGRect(x: r.midX - 1.85, y: r.midY - 1.18, width: 3.7, height: 2.36)
            pill(c, housing, radius: 0.55, color: cream.skirt)
            c.setFillColor(orange.skirt)
            c.fill(CGRect(x: r.midX - 1.0, y: r.midY - 0.26, width: 2, height: 0.52))
            c.fill(CGRect(x: r.midX - 0.27, y: r.midY - 0.78, width: 0.54, height: 1.56))
        }
        if let key = activeKey, key != hiddenKey, let cap = byCode[key] {
            drawCap(cap, in: c, pressed: true, pressure: pressure)
        }
    }

    static func drawLooseCap(_ code: Int, center: CGPoint, scale: CGFloat, rotation: CGFloat, in c: CGContext) {
        guard let cap = byCode[code] else { return }
        c.saveGState()
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: rotation)
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: -cap.frame.midX, y: -cap.frame.midY)
        drawCap(cap, in: c, pressed: false)
        c.restoreGState()
    }
}
