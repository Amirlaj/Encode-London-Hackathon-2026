import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(red: 0.075, green: 0.19, blue: 0.16, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
NSColor(red: 0.79, green: 0.93, blue: 0.39, alpha: 1).setStroke()
let frame = NSBezierPath(roundedRect: NSRect(x: 218, y: 218, width: 588, height: 588), xRadius: 155, yRadius: 155)
frame.lineWidth = 36
frame.stroke()
let play = NSBezierPath()
play.move(to: NSPoint(x: 430, y: 354))
play.line(to: NSPoint(x: 430, y: 670))
play.line(to: NSPoint(x: 666, y: 512))
play.close()
NSColor(red: 0.79, green: 0.93, blue: 0.39, alpha: 1).setFill()
play.fill()
NSGraphicsContext.restoreGraphicsState()
let url = URL(fileURLWithPath: "Replay/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: url)
print("Generated AppIcon.png")
