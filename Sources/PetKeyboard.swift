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
    }

    private static let shell = CGRect(x: 95, y: 23.5, width: 130, height: 35.5)
    private static let bounds = shell.insetBy(dx: -1, dy: -1)
    private static let caseDark = color(0x37363A)
    private static let backplate = color(0x5D5A5B)
    private static let ivory = color(0xFFF5E6)
    private static let capEdge = color(0xCDBDAA)
    private static let ochre = color(0xF2CD93)
    private static let ochreEdge = color(0xC89F73)
    private static let sage = color(0xD2DFCE)
    private static let active = color(0xC4EC7B)
    private static let activeEdge = color(0x7F9D55)
    private static let legendColor = color(0x514D4B)

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
                var fontSize: CGFloat = rowNumber == 0 ? 3.0 : 3.9
                if [kVK_LeftArrow, kVK_DownArrow, kVK_RightArrow].contains(key.code ?? -1) {
                    rect.size.height = (height - 0.42) / 2
                    fontSize = 3.0
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
        let text = NSAttributedString(string: key.legend, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor(cgColor: legendColor)!
        ])
        return Cap(key: key, frame: frame, line: CTLineCreateWithAttributedString(text))
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

    private static func drawCap(_ cap: Cap, in c: CGContext, pressed: Bool) {
        let rect = cap.frame
        let accent = cap.key.code == kVK_Escape || cap.key.code == kVK_Return
        let edge = pressed ? activeEdge : (accent ? ochreEdge : capEdge)
        let face = pressed ? active : (accent ? ochre : cap.key.code == kVK_Space ? sage : ivory)
        pill(c, rect, radius: 0.8, color: edge)
        let inset: CGFloat = pressed ? 0.15 : 0.55
        let top = CGRect(x: rect.minX, y: rect.minY + inset, width: rect.width, height: rect.height - inset)
        pill(c, top, radius: 0.66, color: face)
        guard !cap.key.legend.isEmpty else { return }
        c.saveGState()
        c.translateBy(x: top.midX, y: top.midY)
        c.scaleBy(x: -1, y: -1)
        c.textMatrix = .identity
        let ink = CTLineGetBoundsWithOptions(cap.line, .useGlyphPathBounds)
        c.textPosition = CGPoint(x: -ink.midX, y: -ink.midY)
        CTLineDraw(cap.line, c)
        c.restoreGState()
    }

    private static func drawResting(in c: CGContext) {
        pill(c, shell, radius: 4.0, color: caseDark)
        pill(c, CGRect(x: shell.minX + 1.4, y: shell.minY + 2.0, width: shell.width - 2.8, height: shell.height - 3.3),
             radius: 3.0, color: backplate)
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

    static func draw(in c: CGContext, activeKey: Int?, hiddenKey: Int? = nil) {
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
            pill(c, r.insetBy(dx: -0.15, dy: -0.15), radius: 0.7, color: caseDark)
            let stem = CGRect(x: r.midX - 1.3, y: r.midY - 0.8, width: 2.6, height: 1.6)
            pill(c, stem, radius: 0.4, color: capEdge)
        }
        if let key = activeKey, key != hiddenKey, let cap = byCode[key] { drawCap(cap, in: c, pressed: true) }
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
