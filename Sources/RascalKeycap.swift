import AppKit
import CoreText

/// The orange trophy uses the same coordinate system for its artwork and the cat's fingers.
struct RascalKeycap {
    let center: CGPoint
    let width: CGFloat
    let angle: CGFloat

    private var placement: CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: angle)
            .scaledBy(x: width / 100, y: width / 100)
    }

    var leftContact: CGPoint { CGPoint(x: -38, y: 4).applying(placement) }
    var rightContact: CGPoint { CGPoint(x: 38.5, y: -6).applying(placement) }

    func draw(in context: CGContext) {
        guard width > 0 else { return }
        context.saveGState()
        context.concatenate(placement)
        if let image = Self.image {
            context.interpolationQuality = .high
            context.draw(image, in: Self.bounds)
        } else {
            Self.paint(in: context)
        }
        context.restoreGState()
    }

    private static let bounds = CGRect(x: -55, y: -59, width: 110, height: 116)
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Render once at a higher resolution than the largest displayed key. A very fine,
    // fixed grain gives the orange plastic the matte finish of the illustrated icon.
    private static let image: CGImage? = {
        let density = 4
        let w = Int(bounds.width) * density, h = Int(bounds.height) * density
        guard let canvas = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                         CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = canvas.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        canvas.scaleBy(x: CGFloat(density), y: CGFloat(density))
        canvas.translateBy(x: -bounds.minX, y: -bounds.minY)
        paint(in: canvas)
        var seed: UInt32 = 1927
        for i in stride(from: 0, to: h * w * 4, by: 4) where pixels[i + 3] == 255 {
            seed = seed &* 1664525 &+ 1013904223
            let grain = Int(seed >> 28) - 7
            for channel in 0..<3 {
                pixels[i + channel] = UInt8(clamping: Int(pixels[i + channel]) + grain)
            }
        }
        return canvas.makeImage()
    }()

    private static func color(_ rgb: Int) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    private static func roundedOutline(_ corners: [CGPoint], radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func near(_ point: CGPoint, toward other: CGPoint) -> CGPoint {
            let dx = other.x - point.x, dy = other.y - point.y
            let t = min(0.45, radius / max(1, hypot(dx, dy)))
            return CGPoint(x: point.x + t * dx, y: point.y + t * dy)
        }
        for (i, corner) in corners.enumerated() {
            let before = near(corner, toward: corners[(i + corners.count - 1) % corners.count])
            let after = near(corner, toward: corners[(i + 1) % corners.count])
            if i == 0 { path.move(to: before) } else { path.addLine(to: before) }
            path.addQuadCurve(to: after, control: corner)
        }
        path.closeSubpath()
        return path
    }

    private static func paint(in c: CGContext) {
        func tint(_ path: CGPath, _ colors: [Int], from a: CGPoint, to b: CGPoint) {
            guard let gradient = CGGradient(colorsSpace: space, colors: colors.map(color) as CFArray, locations: nil) else { return }
            c.saveGState()
            c.addPath(path)
            c.clip()
            c.drawLinearGradient(gradient, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            c.restoreGState()
        }

        let body = roundedOutline([CGPoint(x: -36, y: 51), CGPoint(x: 32, y: 52),
                                   CGPoint(x: 43, y: 44), CGPoint(x: 50, y: -43),
                                   CGPoint(x: 45, y: -51), CGPoint(x: -45, y: -52),
                                   CGPoint(x: -50, y: -47), CGPoint(x: -44, y: 40)], radius: 7)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -1.4), blur: 2.1, color: CGColor(gray: 0.12, alpha: 0.48))
        c.setFillColor(color(0xA23F04))
        c.addPath(body)
        c.fillPath()
        c.restoreGState()
        tint(body, [0xFFA331, 0xDB6304, 0x873402], from: CGPoint(x: -48, y: 30), to: CGPoint(x: 46, y: -29))

        let face = roundedOutline([CGPoint(x: -36, y: 51), CGPoint(x: 34, y: 51),
                                   CGPoint(x: 35, y: -17), CGPoint(x: -35, y: -15)], radius: 6.8)
        let skirt = roundedOutline([CGPoint(x: -35, y: -12), CGPoint(x: 34, y: -15),
                                    CGPoint(x: 49, y: -49), CGPoint(x: -49, y: -52)], radius: 4.0)
        c.saveGState()
        c.addPath(body)
        c.clip()
        tint(skirt, [0xF68716, 0xCC5702, 0xA23F02], from: CGPoint(x: -26, y: -13), to: CGPoint(x: 17, y: -52))
        c.restoreGState()
        tint(face, [0xFFA138, 0xFA8C1C, 0xEF7C0E], from: CGPoint(x: -33, y: 49), to: CGPoint(x: 36, y: -20))
        c.saveGState()
        c.addPath(face)
        c.clip()
        // Round the molded lip with a broad soft highlight and a narrower lit edge.
        for (weight, opacity) in [(5.2, 0.18), (2.5, 0.29)] {
            c.saveGState()
            c.setAlpha(opacity)
            let rim = face.copy(strokingWithWidth: weight, lineCap: .round, lineJoin: .round, miterLimit: 1)
            tint(rim, [0xFFF2BC, 0xFFB552, 0xFFBD5B], from: CGPoint(x: -34, y: 48), to: CGPoint(x: 34, y: -19))
            c.restoreGState()
        }
        c.restoreGState()

        let bold = NSFont.systemFont(ofSize: 29.5, weight: .bold)
        let rounded = bold.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: bold.pointSize) } ?? bold
        let legend = NSAttributedString(string: "ESC", attributes: [
            .font: rounded, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ])
        let line = CTLineCreateWithAttributedString(legend)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        c.saveGState()
        c.textMatrix = .identity
        c.setShadow(offset: CGSize(width: 0, height: -0.65), blur: 0.62, color: color(0xBD5E12))
        c.setFillColor(color(0xFFF0C6))
        c.textPosition = CGPoint(x: -ink.midX, y: 17.8 - ink.midY)
        CTLineDraw(line, c)
        c.restoreGState()
    }
}
