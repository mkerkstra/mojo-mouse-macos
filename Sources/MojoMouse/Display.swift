import AppKit

struct DisplayPixels {
  let bytes: [UInt8]
  static func render(_ text: String) throws -> DisplayPixels {
    guard text.count <= 120 else {
      throw MouseFailure(message: "Use a shorter message; the display is only 96 × 39 pixels.")
    }
    let clean = text.replacingOccurrences(of: "\\n", with: "\n")
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byCharWrapping
    var attributes: [NSAttributedString.Key: Any] = [:]
    var bounds = NSRect.zero
    var fits = false
    for size in stride(from: CGFloat(18), through: 8, by: -1) {
      attributes = [
        .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
        .foregroundColor: NSColor.white, .paragraphStyle: paragraph,
      ]
      bounds = (clean as NSString).boundingRect(
        with: NSSize(width: 94, height: 1000),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
      if bounds.height <= 37 {
        fits = true
        break
      }
    }
    guard fits || clean.isEmpty else {
      throw MouseFailure(message: "That message needs more than two lines. Try fewer characters.")
    }
    let image = NSImage(size: NSSize(width: 96, height: 39))
    image.lockFocus()
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: 96, height: 39).fill()
    NSGraphicsContext.current?.imageInterpolation = .none
    NSGraphicsContext.current?.shouldAntialias = false
    (clean as NSString).draw(
      with: NSRect(x: 1, y: max(0, (39 - bounds.height) / 2), width: 94, height: bounds.height),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let pixels = NSBitmapImageRep(data: tiff) else {
      throw MouseFailure(message: "Could not render the message.")
    }
    // NSImage may use the display's backing scale. Resample its pixels to
    // the physical panel's exact 96 × 39 resolution before page packing.
    var bytes = [UInt8](repeating: 0, count: 512)
    for y in 0..<39 {
      for x in 0..<96 {
        let px = min(pixels.pixelsWide - 1, x * pixels.pixelsWide / 96)
        let py = min(pixels.pixelsHigh - 1, y * pixels.pixelsHigh / 39)
        guard let color = pixels.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) else {
          continue
        }
        if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.4 {
          bytes[x + (y / 8) * 96] |= 1 << UInt8(y % 8)
        }
      }
    }
    return DisplayPixels(bytes: bytes)
  }
}
