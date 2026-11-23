import AppKit
import CoreText

/// Compact, level keyboard in the pet's local, bottom-up coordinate system.
enum PetKeyboard {
    private struct Cap {
        let legend: String
        let frame: CGRect
        let letter: Int?
        let accent: Bool
        let line: CTLine
    }

    private static let shell = CGRect(x: 95, y: 19, width: 130, height: 37)
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

    private static let caps: [Cap] = {
        typealias Spec = (legend: String, units: CGFloat)
        func single(_ labels: String) -> [Spec] { labels.map { (String($0), 1) } }
        let rows: [[Spec]] = [
            [("⎋", 1)] + single("QWERTYUIOP") + [("⌫", 1.25)],
            [("⇥", 1.25)] + single("ASDFGHJKL;") + [("↵", 1)],
            [("⇧", 1.75)] + single("ZXCVBNM,./") + [("⇧", 1)],
            [("⌃", 1), ("⌥", 1), ("⌘", 1.25), ("", 5), ("⌘", 1), ("←", 1), ("↓", 1), ("→", 1)]
        ]
        let font = NSFont.monospacedSystemFont(ofSize: 4.6, weight: .medium)
        var result: [Cap] = []
        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = shell.width - 6
            let gap: CGFloat = 0.85
            let units = row.reduce(CGFloat.zero) { $0 + $1.units }
            let unit = (rowWidth - CGFloat(row.count - 1) * gap) / units
            var x = shell.midX - rowWidth / 2
            for spec in row {
                let w = unit * spec.units
                let frame = CGRect(x: x, y: 46.5 - CGFloat(rowIndex) * 7.65, width: w, height: 6.9)
                let ascii = spec.legend.utf8.first
                let index = spec.legend.count == 1 ? ascii.flatMap { (65...90).contains($0) ? Int($0) - 65 : nil } : nil
                let text = NSAttributedString(string: spec.legend, attributes: [
                    .font: font, .foregroundColor: NSColor(cgColor: legendColor)!
                ])
                result.append(Cap(legend: spec.legend, frame: frame, letter: index,
                                  accent: spec.legend == "⎋" || spec.legend == "↵",
                                  line: CTLineCreateWithAttributedString(text)))
                x += w + gap
            }
        }
        return result
    }()

    static func center(for key: Int) -> CGPoint? {
        guard let cap = caps.first(where: { $0.letter == key }) else { return nil }
        return CGPoint(x: cap.frame.midX, y: cap.frame.midY)
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
        let inset: CGFloat = pressed ? 0.24 : 0.65
        let edge = pressed ? activeEdge : (cap.accent ? ochreEdge : capEdge)
        let base = cap.legend.isEmpty ? sage : ivory
        let face = pressed ? active : (cap.accent ? ochre : base)
        pill(c, rect, radius: 1.0, color: edge)
        let top = CGRect(x: rect.minX, y: rect.minY + inset, width: rect.width, height: rect.height - inset)
        pill(c, top, radius: 0.86, color: face)
        if !cap.legend.isEmpty {
            c.textMatrix = .identity
            let ink = CTLineGetBoundsWithOptions(cap.line, .useGlyphPathBounds)
            c.textPosition = CGPoint(x: top.midX - ink.midX, y: top.midY - ink.midY)
            CTLineDraw(cap.line, c)
        }
    }

    private static func drawResting(in c: CGContext) {
        pill(c, shell, radius: 4.25, color: caseDark)
        pill(c, CGRect(x: shell.minX + 1.4, y: shell.minY + 3, width: shell.width - 2.8, height: shell.height - 4.2),
             radius: 3.1, color: backplate)
        for cap in caps { drawCap(cap, in: c, pressed: false) }
    }

    // The resting keyboard is stationary. Only a pressed key needs repainting.
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

    static func draw(in c: CGContext, activeKey: Int?) {
        c.saveGState()
        defer { c.restoreGState() }
        if let image = restingImage {
            c.interpolationQuality = .high
            c.draw(image, in: bounds)
        } else {
            drawResting(in: c)
        }
        if let key = activeKey, let cap = caps.first(where: { $0.letter == key }) {
            drawCap(cap, in: c, pressed: true)
        }
    }
}
