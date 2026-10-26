// Original vector artwork; generate exact pixel sizes without display backing scale.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let context = NSGraphicsContext.current!.cgContext
  context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  NSColor(srgbRed: 0.09, green: 0.27, blue: 0.22, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 192, yRadius: 192
  ).fill()
  NSColor(srgbRed: 0.85, green: 0.96, blue: 0.90, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 344, y: 248, width: 336, height: 528), xRadius: 168, yRadius: 168
  ).fill()
  NSColor(srgbRed: 0.09, green: 0.27, blue: 0.22, alpha: 1).setFill()
  NSBezierPath(roundedRect: NSRect(x: 496, y: 608, width: 32, height: 88), xRadius: 16, yRadius: 16)
    .fill()
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(
    to: output.appendingPathComponent("icon-\(size).png"))
}
