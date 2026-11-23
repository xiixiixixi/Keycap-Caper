import AppKit
import ImageIO

/// Portrait artwork and animation anchors share a 385-unit, top-down artboard.
final class CompanionPortrait {
    private static let artSize: CGFloat = 385
    private static let dog = CompanionPortrait(
        asset: "Pickles", frame: CGRect(x: 76, y: 48, width: 168, height: 168),
        eyes: [CGRect(x: 113, y: 124, width: 55, height: 49), CGRect(x: 214, y: 142, width: 53, height: 50)],
        fur: CGRect(x: 145, y: 303, width: 85, height: 65), lidFur: CGRect(x: 165, y: 99, width: 32, height: 27), hoof: false)
    private static let rabbit = CompanionPortrait(
        asset: "Pipkin", frame: CGRect(x: 70, y: 47, width: 180, height: 180),
        eyes: [CGRect(x: 111, y: 190, width: 57, height: 46), CGRect(x: 207, y: 182, width: 56, height: 50)],
        fur: CGRect(x: 157, y: 311, width: 69, height: 51), lidFur: CGRect(x: 169, y: 161, width: 30, height: 24), hoof: false)
    private static let giraffe = CompanionPortrait(
        asset: "Periscope", frame: CGRect(x: 68, y: 49, width: 184, height: 184),
        eyes: [CGRect(x: 134, y: 82, width: 46, height: 42), CGRect(x: 208, y: 76, width: 42, height: 42)],
        fur: CGRect(x: 167, y: 306, width: 49, height: 65), lidFur: CGRect(x: 171, y: 59, width: 23, height: 18), hoof: true)

    static func forCharacter(_ character: PetCharacter) -> CompanionPortrait? {
        switch character {
        case .cat: return nil
        case .dog: return dog
        case .rabbit: return rabbit
        case .giraffe: return giraffe
        }
    }

    let eyeCenter: CGPoint
    private let frame: CGRect
    private let image: CGImage
    private let eyes: [PortraitEye]
    private let paw: CGImage

    private init?(asset: String, frame: CGRect, eyes eyeRects: [CGRect], fur: CGRect, lidFur: CGRect, hoof: Bool) {
        guard let url = Bundle.main.url(forResource: asset, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.image = image
        self.frame = frame
        let sourceScale = CGFloat(image.width) / Self.artSize
        let toSource = CGAffineTransform(scaleX: sourceScale, y: sourceScale)
        guard let furPatch = image.cropping(to: fur.applying(toSource).integral),
              let eyelid = image.cropping(to: lidFur.applying(toSource).integral),
              let paw = Self.paintPaw(fur: furPatch, hoof: hoof) else { return nil }
        self.paw = paw
        let targetScale = frame.width / Self.artSize
        self.eyes = eyeRects.compactMap { rect in
            // Include the fur around both eyelids to blend the moving eye with its face.
            let crop = rect.insetBy(dx: -rect.width * 0.17, dy: -rect.height * 0.17).applying(toSource).integral
            guard let detail = image.cropping(to: crop) else { return nil }
            let drawRect = CGRect(x: frame.minX + crop.minX * frame.width / CGFloat(image.width),
                                  y: frame.maxY - crop.maxY * frame.height / CGFloat(image.height),
                                  width: crop.width * frame.width / CGFloat(image.width),
                                  height: crop.height * frame.height / CGFloat(image.height))
            return PortraitEye(image: detail, eyelid: eyelid, frame: drawRect)
        }
        let midpoint = CGPoint(x: (eyeRects[0].midX + eyeRects[1].midX) * 0.5,
                               y: (eyeRects[0].midY + eyeRects[1].midY) * 0.5)
        eyeCenter = CGPoint(x: frame.minX + midpoint.x * targetScale,
                            y: frame.maxY - midpoint.y * targetScale)
    }

    func drawBody(in c: CGContext, gaze: CGVector, blink: CGFloat) {
        c.draw(image, in: frame)
        for eye in eyes { eye.draw(in: c, gaze: gaze, blink: blink) }
    }

    func drawPaw(in c: CGContext, toe: CGPoint, shoulder: CGPoint) {
        let dx = toe.x - shoulder.x
        let dy = shoulder.y - toe.y
        let length = min(43, max(27, hypot(dx, dy)))
        c.saveGState()
        c.translateBy(x: toe.x, y: toe.y)
        c.rotate(by: atan2(dx, dy))
        c.draw(paw, in: CGRect(x: -11, y: -1.5, width: 22, height: length + 3))
        c.restoreGState()
    }

    private static func paintPaw(fur: CGImage, hoof: Bool) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let c = CGContext(data: nil, width: 88, height: 152, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.scaleBy(x: 4, y: 4)
        let shape = CGMutablePath()
        let bottom = CGPoint(x: 10.8, y: 1.8)
        shape.move(to: bottom)
        shape.addCurve(to: CGPoint(x: 1.6, y: 8), control1: CGPoint(x: 5, y: 0), control2: CGPoint(x: 0.8, y: 3))
        shape.addCurve(to: CGPoint(x: 4.8, y: 22), control1: CGPoint(x: 0.8, y: 14), control2: CGPoint(x: 4, y: 16.8))
        shape.addCurve(to: CGPoint(x: 11, y: 37.5), control1: CGPoint(x: 5, y: 30), control2: CGPoint(x: 5.4, y: 36.7))
        shape.addCurve(to: CGPoint(x: 18, y: 22), control1: CGPoint(x: 17, y: 37), control2: CGPoint(x: 18.5, y: 30))
        shape.addCurve(to: CGPoint(x: 20.3, y: 7.8), control1: CGPoint(x: 18, y: 16), control2: CGPoint(x: 21.8, y: 13))
        shape.addCurve(to: bottom, control1: CGPoint(x: 19.8, y: 3), control2: CGPoint(x: 16.2, y: 0))
        shape.closeSubpath()
        c.addPath(shape)
        c.clip()
        c.draw(fur, in: CGRect(x: 0, y: 0, width: 22, height: 38))
        let edgeTint = CGColor(srgbRed: 0.19, green: 0.12, blue: 0.10, alpha: 0.42)
        let clear = CGColor(gray: 0.5, alpha: 0)
        if let shade = CGGradient(colorsSpace: space, colors: [edgeTint, clear, clear, edgeTint] as CFArray,
                                  locations: [0, 0.22, 0.66, 1]) {
            c.drawLinearGradient(shade, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 22, y: 0), options: [])
        }
        if hoof {
            let tip = CGMutablePath()
            tip.move(to: CGPoint(x: 0, y: 6.8))
            tip.addQuadCurve(to: CGPoint(x: 22, y: 8.2), control: CGPoint(x: 11, y: 17.8))
            tip.addLine(to: CGPoint(x: 22, y: 0))
            tip.addLine(to: .zero)
            tip.closeSubpath()
            c.setFillColor(CGColor(srgbRed: 0.32, green: 0.21, blue: 0.15, alpha: 1))
            c.addPath(tip)
            c.fillPath()
        }
        c.setLineCap(.round)
        c.setLineWidth(0.65)
        c.setStrokeColor(hoof ? CGColor(srgbRed: 0.13, green: 0.08, blue: 0.07, alpha: 0.75) : edgeTint)
        for x: CGFloat in (hoof ? [11] : [6.8, 13.1]) {
            c.move(to: CGPoint(x: x, y: 1.7))
            c.addQuadCurve(to: CGPoint(x: x + 0.4, y: hoof ? 7.2 : 5.8), control: CGPoint(x: x - 0.8, y: 4))
            c.strokePath()
        }
        if let fade = CGGradient(colorsSpace: space,
                                 colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray,
                                 locations: [0, 1]) {
            c.setBlendMode(.destinationIn)
            c.drawLinearGradient(fade, start: CGPoint(x: 0, y: 28), end: CGPoint(x: 0, y: 38),
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        return c.makeImage()
    }
}

// Move the pixels of each painted eye. This preserves its original iris, highlights,
// irregular eyelids and surrounding fur throughout motion, with no second pupil.
private final class PortraitEye {
    private let frame: CGRect
    private let width: Int
    private let height: Int
    private let original: [UInt8]
    private let lid: [UInt8]
    private let canvas: CGContext
    private let output: UnsafeMutablePointer<UInt8>
    private var lastX = Int.min
    private var lastY = Int.min
    private var lastBlink = Int.min
    private var lastImage: CGImage?

    init?(image: CGImage, eyelid: CGImage, frame: CGRect) {
        self.frame = frame
        width = max(20, Int(ceil(frame.width * 3)))
        height = max(20, Int(ceil(frame.height * 3)))
        guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = canvas.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        canvas.interpolationQuality = .high
        canvas.draw(eyelid, in: CGRect(x: 0, y: 0, width: width, height: height))
        lid = Array(UnsafeBufferPointer(start: bytes, count: height * width * 4))
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.canvas = canvas
        output = bytes
        original = Array(UnsafeBufferPointer(start: bytes, count: height * width * 4))
    }

    func draw(in c: CGContext, gaze: CGVector, blink: CGFloat) {
        let hx = Int((min(1, max(-1, gaze.dx)) * 24).rounded())
        let vy = Int((min(1, max(-1, gaze.dy)) * 24).rounded())
        let closed = Int((min(1, max(0, blink)) * 24).rounded())
        if hx == 0 && vy == 0 && closed == 0 { return }
        if hx != lastX || vy != lastY || closed != lastBlink {
            lastImage = nil
            let rx = Double(width) / 2
            let ry = Double(height) / 2
            let shiftX = Double(hx) / 24 * rx * 0.32
            let shiftY = -Double(vy) / 24 * ry * 0.21
            let blink = Double(closed) / 24
            for y in 0..<height {
                let v = (Double(y) + 0.5 - ry) / ry
                for x in 0..<width {
                    let u = (Double(x) + 0.5 - rx) / rx
                    let alpha = max(0, 1 - u*u - v*v)
                    guard alpha > 0 else { continue } // outside the eye patch always stays original
                    let falloff = alpha * alpha
                    let sx = Double(x) - shiftX * falloff
                    let sy = Double(y) - shiftY * falloff
                    let destination = 4 * (y * width + x)
                    sample(x: sx, y: sy, to: destination)
                    if closed > 0 {
                        // A curved upper and lower eyelid are painted with forehead
                        // fibers from the same animal. Their soft edges meet in a seam.
                        let h = sqrt(max(0, 1 - u*u))
                        let seam = 0.22 * h - 0.22 * u*u
                        let top = -h + (h + seam) * blink
                        let bottom = h + (seam - h) * blink
                        let coverage = min(1, max(0, max(top - v, v - bottom) * 28 + 0.5))
                        let feather = min(1, alpha * 5) * coverage
                        let crease = max(0, 1 - abs(v - top) * 10) * max(0, 1 - u*u)
                        let shade = 1 - 0.09 * h - 0.42 * crease
                        for channel in 0..<3 {
                            let base = Double(output[destination + channel])
                            let fur = Double(lid[destination + channel]) * shade
                            output[destination + channel] = UInt8(min(255, max(0, base + (fur - base) * feather)))
                        }
                    }
                }
            }
            lastImage = canvas.makeImage()
            lastX = hx
            lastY = vy
            lastBlink = closed
        }
        if let lastImage { c.draw(lastImage, in: frame) }
    }

    private func sample(x: Double, y: Double, to destination: Int) {
        let sx = min(Double(width - 1), max(0, x))
        let sy = min(Double(height - 1), max(0, y))
        let column = Int(sx)
        let row = Int(sy)
        let dx = sx - Double(column)
        let dy = sy - Double(row)
        let left = 4 * (row * width + column)
        let right = left + (column + 1 < width ? 4 : 0)
        let down = row + 1 < height ? width * 4 : 0
        for channel in 0..<4 {
            let a = Double(original[left + channel])
            let b = Double(original[right + channel])
            let c = Double(original[left + down + channel])
            let d = Double(original[right + down + channel])
            let top = a + (b - a) * dx
            let bottom = c + (d - c) * dx
            output[destination + channel] = UInt8(min(255, max(0, top + (bottom - top) * dy)))
        }
    }
}
