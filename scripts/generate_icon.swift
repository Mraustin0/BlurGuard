import Cocoa

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// ── Background ───────────────────────────────────────────────────
let bgGrad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [CGColor(red: 0.05, green: 0.08, blue: 0.18, alpha: 1),
             CGColor(red: 0.09, green: 0.15, blue: 0.34, alpha: 1)] as CFArray,
    locations: [0, 1])!

ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
    cornerWidth: 220, cornerHeight: 220, transform: nil))
ctx.clip()
ctx.drawLinearGradient(bgGrad,
    start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

// ── Glow rings ───────────────────────────────────────────────────
for i in 0..<4 {
    let r = CGFloat(200 + i * 80)
    ctx.setStrokeColor(CGColor(red: 0.4, green: 0.65, blue: 1.0,
        alpha: CGFloat(0.07 - Double(i) * 0.015)))
    ctx.setLineWidth(CGFloat(22 - i * 4))
    ctx.strokeEllipse(in: CGRect(x: 512 - r, y: 512 - r, width: r * 2, height: r * 2))
}

// ── Shield ───────────────────────────────────────────────────────
let sw: CGFloat = 430, sh: CGFloat = 490
let sx = (1024 - sw) / 2, sy: CGFloat = 260

let shield = CGMutablePath()
shield.move(to: CGPoint(x: sx + sw/2, y: sy + sh))
shield.addCurve(to: CGPoint(x: sx, y: sy + sh*0.36),
    control1: CGPoint(x: sx + sw*0.10, y: sy + sh*0.87),
    control2: CGPoint(x: sx,           y: sy + sh*0.62))
shield.addLine(to: CGPoint(x: sx, y: sy + sh*0.18))
shield.addCurve(to: CGPoint(x: sx + sw/2, y: sy),
    control1: CGPoint(x: sx,           y: sy + sh*0.06),
    control2: CGPoint(x: sx + sw*0.25, y: sy))
shield.addCurve(to: CGPoint(x: sx + sw, y: sy + sh*0.18),
    control1: CGPoint(x: sx + sw*0.75, y: sy),
    control2: CGPoint(x: sx + sw,      y: sy + sh*0.06))
shield.addLine(to: CGPoint(x: sx + sw, y: sy + sh*0.36))
shield.addCurve(to: CGPoint(x: sx + sw/2, y: sy + sh),
    control1: CGPoint(x: sx + sw,      y: sy + sh*0.62),
    control2: CGPoint(x: sx + sw*0.90, y: sy + sh*0.87))
shield.closeSubpath()

ctx.saveGState()
ctx.addPath(shield)
ctx.clip()
let shieldGrad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [CGColor(red: 0.32, green: 0.60, blue: 1.00, alpha: 1),
             CGColor(red: 0.12, green: 0.30, blue: 0.78, alpha: 1)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(shieldGrad,
    start: CGPoint(x: 512, y: sy + sh), end: CGPoint(x: 512, y: sy), options: [])
ctx.restoreGState()

ctx.addPath(shield)
ctx.setStrokeColor(CGColor(red: 0.6, green: 0.82, blue: 1.0, alpha: 0.5))
ctx.setLineWidth(9)
ctx.strokePath()

// ── Lock — draw order: shackle → body → keyhole ──────────────────
let lockCX: CGFloat = 512
let bw: CGFloat = 150, bh: CGFloat = 120
let bx = lockCX - bw / 2, by: CGFloat = 548

let shackleR: CGFloat = 48
let shackleLW: CGFloat = 32
let shackleCY = by + shackleLW / 2          // shackle arc centre at top of body

// 1. Shackle (draw first so body covers the legs naturally)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
ctx.setLineWidth(shackleLW)
ctx.setLineCap(.butt)
// Full arc from right leg down-left to left leg (top half = visible above body)
ctx.beginPath()
ctx.addArc(center: CGPoint(x: lockCX, y: shackleCY),
    radius: shackleR, startAngle: 0, endAngle: .pi, clockwise: true)
ctx.strokePath()
// Two vertical legs going into the body
ctx.setLineCap(.round)
ctx.beginPath()
ctx.move(to: CGPoint(x: lockCX + shackleR, y: shackleCY))
ctx.addLine(to: CGPoint(x: lockCX + shackleR, y: by + bh * 0.4))
ctx.move(to: CGPoint(x: lockCX - shackleR, y: shackleCY))
ctx.addLine(to: CGPoint(x: lockCX - shackleR, y: by + bh * 0.4))
ctx.strokePath()

// 2. Lock body (covers leg bottoms)
ctx.addPath(CGPath(roundedRect: CGRect(x: bx, y: by, width: bw, height: bh),
    cornerWidth: 24, cornerHeight: 24, transform: nil))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
ctx.fillPath()

// 3. Keyhole
let ky = by + 38
ctx.setFillColor(CGColor(red: 0.15, green: 0.32, blue: 0.80, alpha: 1))
ctx.fillEllipse(in: CGRect(x: lockCX - 17, y: ky, width: 34, height: 34))
ctx.fill(CGRect(x: lockCX - 10, y: ky + 15, width: 20, height: 28))

image.unlockFocus()

// ── Export ───────────────────────────────────────────────────────
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let tiff = image.tiffRepresentation,
      let bmp  = NSBitmapImageRep(data: tiff),
      let png  = bmp.representation(using: .png, properties: [:])
else { print("Failed"); exit(1) }
try! png.write(to: out)
print("Saved \(out.lastPathComponent)")
