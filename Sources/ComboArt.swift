import AppKit

/// Draws a single short prop animation in bottom-up view coordinates.
enum ComboArt {
    static let duration: TimeInterval = 1.35
    private static let ink = NSColor(srgbRed: 0.18, green: 0.14, blue: 0.16, alpha: 1)
    private static let paper = NSColor(srgbRed: 1, green: 0.97, blue: 0.86, alpha: 1)
    private static let honey = NSColor(srgbRed: 1, green: 0.73, blue: 0.32, alpha: 1)
    private static let apricot = NSColor(srgbRed: 0.99, green: 0.59, blue: 0.42, alpha: 1)
    private static let mint = NSColor(srgbRed: 0.68, green: 0.88, blue: 0.69, alpha: 1)
    private static let lilac = NSColor(srgbRed: 0.79, green: 0.76, blue: 0.99, alpha: 1)
    private static let sky = NSColor(srgbRed: 0.65, green: 0.85, blue: 0.93, alpha: 1)

    static func draw(_ trick: ComboTrick, age: TimeInterval, reducedMotion: Bool,
                     in c: CGContext, center: CGPoint = CGPoint(x: 45, y: 127)) {
        guard age >= 0, age < duration else { return }
        let t = CGFloat(age)
        let entry = reducedMotion ? 1 : min(1, t / 0.16)
        let exit = max(0, min(1, (CGFloat(duration) - t) / 0.19))
        let progress = reducedMotion ? 1 : min(1, max(0, (t - 0.07) / 0.58))
        let ease = 1 - pow(1 - progress, 3)
        let accent: NSColor
        switch trick {
        case .copy, .selectAll: accent = mint
        case .paste, .save: accent = honey
        case .cut: accent = apricot
        case .undo, .redo: accent = lilac
        case .find: accent = sky
        }
        c.saveGState()
        defer { c.restoreGState() }
        c.setAlpha(min(1, 0.36 + 0.64 * entry) * exit)
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { c.endTransparencyLayer() }
        c.translateBy(x: center.x, y: center.y - 9 * pow(1 - entry, 2))
        c.setLineCap(.round)
        c.setLineJoin(.round)

        caption(trick, accent: accent, in: c)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -1.4), blur: 2.2, color: ink.withAlphaComponent(0.3).cgColor)
        dot(c, 0, 1, 24, accent, border: paper, line: 2)
        c.restoreGState()

        switch trick {
        case .copy: copies(ease, in: c)
        case .paste: paste(ease, in: c)
        case .cut: cut(progress, in: c)
        case .undo, .redo: timeDial(progress, forward: trick == .redo, in: c)
        case .save: chest(ease, in: c)
        case .find: search(ease, in: c)
        case .selectAll: selection(ease, in: c)
        }
        let gleam = reducedMotion ? 1 : sin(.pi * min(1, max(0, (t - 0.30) / 0.66)))
        if gleam > 0 {
            star(c, x: 23, y: 17, radius: 4 * gleam, color: paper)
            star(c, x: -24, y: -7, radius: 2.7 * gleam, color: honey)
        }
    }

    private static func caption(_ trick: ComboTrick, accent: NSColor, in c: CGContext) {
        rounded(c, CGRect(x: -33, y: -63, width: 66, height: 34), 9,
                fill: ink, stroke: paper.withAlphaComponent(0.92), line: 1.25)
        centeredText(trick.title, baseline: -46, font: .systemFont(ofSize: 12.4, weight: .bold), color: paper, in: c)
        centeredText(trick.shortcut, baseline: -59, font: .monospacedSystemFont(ofSize: 10, weight: .bold), color: accent, in: c)
    }

    private static func centeredText(_ text: String, baseline: CGFloat, font: NSFont, color: NSColor, in c: CGContext) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        c.textMatrix = .identity
        c.textPosition = CGPoint(x: -CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) / 2, y: baseline)
        CTLineDraw(line, c)
    }

    private static func copies(_ p: CGFloat, in c: CGContext) {
        sheet(c, x: -5 * p, y: -4 * p, angle: p * 0.19, tint: sky)
        sheet(c, x: 7 * p, y: 5 * p, angle: -p * 0.14, tint: paper)
    }

    private static func paste(_ p: CGFloat, in c: CGContext) {
        rounded(c, CGRect(x: -13, y: -16, width: 26, height: 32), 3, fill: apricot)
        sheet(c, x: -15 * (1 - p), y: 16 * (1 - p) - 2, angle: (1 - p) * 0.45, tint: paper)
        rounded(c, CGRect(x: -6, y: 12, width: 12, height: 5), 2, fill: honey)
    }

    private static func sheet(_ c: CGContext, x: CGFloat, y: CGFloat, angle: CGFloat, tint: NSColor) {
        c.saveGState()
        defer { c.restoreGState() }
        c.translateBy(x: x, y: y)
        c.rotate(by: angle)
        let route: [CGPoint] = [pt(-10,-13),pt(10,-13),pt(10,7),pt(4,13),pt(-10,13)]
        polygon(c, route, fill: tint)
        line(c, [pt(4,12),pt(4,7),pt(9,7)], width: 1)
        pawPrint(c, x: 0, y: -2, scale: 0.7, color: ink)
    }

    private static func cut(_ p: CGFloat, in c: CGContext) {
        let split = max(0, (p - 0.48) / 0.52)
        for direction: CGFloat in [-1, 1] {
            c.saveGState()
            c.translateBy(x: direction * (8 + 5 * split), y: 7 - split * 3)
            c.rotate(by: direction * split * 0.18)
            rounded(c, CGRect(x: -7.7, y: -4.5, width: 15.4, height: 9), 1.1, fill: paper)
            c.restoreGState()
        }
        let opening = 0.13 + 0.54 * abs(cos(.pi * min(p, 0.78)))
        for direction: CGFloat in [-1, 1] {
            c.saveGState()
            c.rotate(by: direction * opening)
            line(c, [pt(0,-10),pt(0,12)], width: 4)
            line(c, [pt(0,0),pt(0,11)], width: 1.7, color: paper)
            dot(c, 0, -12.5, 3.8, honey, border: ink)
            dot(c, 0, -12.5, 1.35, apricot)
            c.restoreGState()
        }
        dot(c, 0, -1, 1.75, apricot, border: ink, line: 1)
    }

    private static func timeDial(_ p: CGFloat, forward: Bool, in c: CGContext) {
        let sign: CGFloat = forward ? -1 : 1
        dot(c, 0, 0, 11.3, paper, border: ink)
        let hand = .pi / 2 + sign * .pi * 1.43 * p
        line(c, [pt(0,5),pt(0,0),pt(cos(hand)*8,sin(hand)*8)], width: 1.8)
        dot(c, 0, 0, 1.6, ink)
        c.saveGState()
        defer { c.restoreGState() }
        if forward { c.scaleBy(x: -1, y: 1) }
        let endAngle: CGFloat = .pi * (0.64 + 0.38 * p)
        c.setStrokeColor(ink.cgColor)
        c.setLineWidth(2.5)
        c.beginPath()
        c.addArc(center: .zero, radius: 16.5, startAngle: -.pi * 0.53, endAngle: endAngle, clockwise: false)
        c.strokePath()
        c.translateBy(x: cos(endAngle)*16.5, y: sin(endAngle)*16.5)
        c.rotate(by: endAngle + .pi / 2)
        polygon(c, [pt(3,0),pt(-3,3.2),pt(-3,-3.2)], fill: ink, border: nil)
    }

    private static func chest(_ p: CGFloat, in c: CGContext) {
        rounded(c, CGRect(x: -16, y: -12, width: 32, height: 18), 4, fill: apricot)
        c.saveGState()
        c.translateBy(x: -15, y: 4)
        c.rotate(by: (1-p) * 0.62)
        rounded(c, CGRect(x: -1, y: -1, width: 32, height: 12), 4, fill: honey)
        c.restoreGState()
        rounded(c, CGRect(x: -4, y: -4, width: 8, height: 8), 2, fill: paper)
        dot(c, 0, 1, 1.3, ink)
        line(c, [pt(0,0),pt(0,-1.3)], width: 1)
    }

    private static func search(_ p: CGFloat, in c: CGContext) {
        for i in 0..<3 {
            pawPrint(c, x: CGFloat(i*9-11), y: CGFloat(i*5-7), scale: 0.39, color: ink.withAlphaComponent(0.58))
        }
        let x = -12 + 16 * p
        let y = 1 + 3 * p + 4 * sin(.pi * p)
        line(c, [pt(x-6,y-6),pt(x-17,y-17)], width: 4.5)
        dot(c, x, y, 9.7, paper, border: ink, line: 2.6)
        pawPrint(c, x: x, y: y-1, scale: 0.68 * p, color: ink)
    }

    private static func selection(_ p: CGFloat, in c: CGContext) {
        for coord in [pt(-8,-6),pt(7,-5),pt(0,7)] {
            rounded(c, CGRect(x: coord.x-4, y: coord.y-3.5, width: 8, height: 7), 1.6, fill: paper, line: 1)
        }
        let w = 11 + 24*p
        let h = 9 + 17*p
        let rect = CGRect(x: -w/2, y: 1-h/2, width: w, height: h)
        c.saveGState()
        c.setLineDash(phase: 2 * p, lengths: [3,2])
        c.setStrokeColor(ink.cgColor)
        c.setLineWidth(1.15)
        c.stroke(rect)
        c.restoreGState()
        for x in [rect.minX, rect.maxX] {
            for y in [rect.minY, rect.maxY] {
                rounded(c, CGRect(x:x-1.45,y:y-1.45,width:2.9,height:2.9), 0.4, fill: honey, line: 0.7)
            }
        }
    }

    private static func pawPrint(_ c: CGContext, x: CGFloat, y: CGFloat, scale: CGFloat, color: NSColor) {
        guard scale > 0 else { return }
        c.saveGState()
        defer { c.restoreGState() }
        c.translateBy(x: x, y: y)
        c.scaleBy(x: scale, y: scale)
        c.setFillColor(color.cgColor)
        c.fillEllipse(in: CGRect(x:-4.1,y:-4.5,width:8.2,height:6.4))
        for (x,y) in [(-4.4,2.0),(-1.1,4.7),(2.9,4.0),(5.1,0.8)] {
            c.fillEllipse(in: CGRect(x:x-1.45,y:y-1.85,width:2.9,height:3.7))
        }
    }

    private static func star(_ c: CGContext, x: CGFloat, y: CGFloat, radius r: CGFloat, color: NSColor) {
        let points = [pt(x,y+r),pt(x+r*0.28,y+r*0.28),pt(x+r,y),pt(x+r*0.28,y-r*0.28),
                      pt(x,y-r),pt(x-r*0.28,y-r*0.28),pt(x-r,y),pt(x-r*0.28,y+r*0.28)]
        polygon(c, points, fill: color, border: ink, width: 0.7)
    }

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static func line(_ c: CGContext, _ points: [CGPoint], width: CGFloat, color: NSColor = ink) {
        guard let start = points.first else { return }
        c.beginPath()
        c.move(to: start)
        for point in points.dropFirst() { c.addLine(to: point) }
        c.setStrokeColor(color.cgColor)
        c.setLineWidth(width)
        c.strokePath()
    }

    private static func polygon(_ c: CGContext, _ points: [CGPoint], fill: NSColor,
                                border: NSColor? = ink, width: CGFloat = 1.55) {
        guard let start = points.first else { return }
        c.beginPath()
        c.move(to: start)
        for point in points.dropFirst() { c.addLine(to: point) }
        c.closePath()
        paint(c, fill: fill, border: border, width: width)
    }

    private static func dot(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ radius: CGFloat,
                            _ fill: NSColor, border: NSColor? = nil, line: CGFloat = 1.55) {
        c.beginPath()
        c.addEllipse(in: CGRect(x:x-radius,y:y-radius,width:2*radius,height:2*radius))
        paint(c, fill: fill, border: border, width: line)
    }

    private static func rounded(_ c: CGContext, _ rect: CGRect, _ radius: CGFloat,
                                fill: NSColor, stroke: NSColor? = ink, line: CGFloat = 1.55) {
        c.beginPath()
        c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        paint(c, fill: fill, border: stroke, width: line)
    }

    private static func paint(_ c: CGContext, fill: NSColor, border: NSColor?, width: CGFloat) {
        c.setFillColor(fill.cgColor)
        if let border {
            c.setStrokeColor(border.cgColor)
            c.setLineWidth(width)
            c.drawPath(using: .fillStroke)
        } else {
            c.fillPath()
        }
    }
}
