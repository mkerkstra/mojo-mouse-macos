import Foundation

// HID++ protocol layouts informed by MIT-licensed libratbag; see THIRD_PARTY_NOTICES.md.
// This backend never reads/writes onboard memory, firmware, button maps, or LED storage.
struct HIDUsagePair {
  let page: Int
  let usage: Int
}

enum LogitechCatalog {
  static let models: [Int: String] = [
    0xc07d: "G502 Proteus Core", 0xc332: "G502 Proteus Spectrum", 0xc08b: "G502 HERO",
    0xc083: "G403", 0xc08f: "G403 HERO", 0xc084: "G102 / G203",
    0xc092: "G102 / G203 LIGHTSYNC", 0xc09d: "G102 / G103 / G203",
  ]
  static func accepts(vendor: Int, product: Int, usagePages: [Int], transport: String) -> Bool {
    vendor == 0x046d && models[product] != nil
      && usagePages.contains(where: { (0xff00...0xffff).contains($0) })
      && transport == "USB"
  }
  static func requiresInputPermission(_ usages: [HIDUsagePair]) -> Bool {
    usages.contains { $0.page == 1 && [1, 2, 6, 7].contains($0.usage) }
  }

}

struct HIDPPPacket {
  let bytes: [UInt8]
  init(feature: UInt8, function: UInt8, softwareID: UInt8, parameters: [UInt8] = []) throws {
    guard function < 16, (2...15).contains(softwareID), parameters.count <= 16 else {
      throw MouseFailure(message: "Invalid Logitech request.")
    }
    bytes =
      [0x11, 0xff, feature, (function << 4) | softwareID] + parameters
      + Array(repeating: 0, count: 16 - parameters.count)
  }
  // Unrelated notifications and responses to other software are ignored. A matching
  // malformed/error response aborts the operation rather than looking like success.
  func response(_ report: [UInt8]) throws -> [UInt8]? {
    guard
      (report.count == 7 && report.first == 0x10)
        || (report.count == 20 && report.first == 0x11)
    else { return nil }
    guard report[1] == bytes[1] else { return nil }
    if report[2] == 0xff || report[2] == 0x8f, report[3] == bytes[2], report[4] == bytes[3] {
      throw MouseFailure(
        message:
          "Logitech rejected the request (HID++ error \(report[5])). Refresh before retrying.")
    }
    guard report[2] == bytes[2], report[3] == bytes[3] else { return nil }
    return Array(report.dropFirst(4))
  }
}

protocol HIDPPTransport: AnyObject {
  func request(feature: UInt8, function: UInt8, parameters: [UInt8]) throws -> [UInt8]
}

struct LogitechDPIRange: Equatable {
  let values: [Int]
  let step: Int?
  var minimum: Int { values.min() ?? 0 }
  var maximum: Int { values.max() ?? 0 }
  init(reply: [UInt8]) throws {
    guard reply.count == 16, reply[0] == 0 else {
      throw MouseFailure(message: "Unsupported Logitech DPI list.")
    }
    var values: [Int] = []
    var step: Int?
    for offset in stride(from: 1, through: 13, by: 2) {
      let value = Int(reply[offset]) << 8 | Int(reply[offset + 1])
      if value == 0 { break }
      if value > 0xe000 {
        guard step == nil else { throw MouseFailure(message: "Ambiguous Logitech DPI range.") }
        step = value - 0xe000
      } else {
        guard value < 0xe000 else { throw MouseFailure(message: "Invalid Logitech DPI range.") }
        values.append(value)
      }
    }
    guard !values.isEmpty, values == values.sorted(), Set(values).count == values.count else {
      throw MouseFailure(message: "Unsupported Logitech DPI range.")
    }
    if let step {
      guard values.count == 2, (values[1] - values[0]) % step == 0 else {
        throw MouseFailure(message: "Unsupported Logitech DPI range.")
      }
    }
    self.values = values
    self.step = step
  }
  func contains(_ dpi: Int) -> Bool {
    if let step { return (minimum...maximum).contains(dpi) && (dpi - minimum) % step == 0 }
    return values.contains(dpi)
  }
  var label: String {
    if let step { return "\(minimum)–\(maximum), in steps of \(step)" }
    return values.map(String.init).joined(separator: ", ")
  }
}

struct LogitechState: Equatable {
  let mode: Int?
  let dpi: Int?
  let dpiRange: LogitechDPIRange?
  let rate: Int?
  let rates: [Int]
  let features: [UInt16: UInt8]
  var hostControls: Bool { mode == nil || mode == 2 }
}

final class LogitechController {
  private let transport: HIDPPTransport
  private var features: [UInt16: UInt8] = [:]
  init(_ transport: HIDPPTransport) throws {
    self.transport = transport
    let token = UInt8.random(in: 1...255)
    let version = try transport.request(feature: 0, function: 1, parameters: [0, 0, token])
    guard version.count >= 3, version[0] >= 2, version[2] == token else {
      throw MouseFailure(message: "This device did not confirm HID++ 2 support.")
    }
    for feature: UInt16 in [0x2201, 0x8060, 0x8100, 0x8070, 0x8071] {
      let reply = try transport.request(
        feature: 0, function: 0, parameters: [UInt8(feature >> 8), UInt8(feature & 255)])
      guard reply.count >= 3 else {
        throw MouseFailure(message: "Incomplete Logitech feature list.")
      }
      if reply[0] != 0 { features[feature] = reply[0] }
    }
    guard Set(features.values).count == features.count else {
      throw MouseFailure(message: "Conflicting Logitech feature indexes.")
    }
  }
  private func call(_ feature: UInt16, _ function: UInt8, _ parameters: [UInt8] = []) throws
    -> [UInt8]
  {
    guard let index = features[feature] else {
      throw MouseFailure(message: "This Logitech firmware does not offer that control.")
    }
    return try transport.request(feature: index, function: function, parameters: parameters)
  }
  private func mode() throws -> Int? {
    guard features[0x8100] != nil else { return nil }
    let reply = try call(0x8100, 2)
    guard let value = reply.first, [1, 2].contains(value) else {
      throw MouseFailure(message: "Unknown Logitech onboard mode. Changes are blocked.")
    }
    return Int(value)
  }
  func read() throws -> LogitechState {
    let mode = try mode()
    var dpi: Int?
    var range: LogitechDPIRange?
    var rate: Int?
    var rates: [Int] = []
    if features[0x2201] != nil {
      let count = try call(0x2201, 0)
      guard count.first == 1 else {
        throw MouseFailure(message: "Only the single-sensor Logitech format is supported.")
      }
      let supported = try LogitechDPIRange(reply: call(0x2201, 1, [0]))
      range = supported
      let reply = try call(0x2201, 2, [0])
      guard reply.count >= 3, reply[0] == 0 else {
        throw MouseFailure(message: "Incomplete Logitech DPI reply.")
      }
      let current = Int(reply[1]) << 8 | Int(reply[2])
      guard supported.contains(current) else {
        throw MouseFailure(message: "Logitech returned an unexpected current DPI.")
      }
      dpi = current
    }
    if features[0x8060] != nil {
      let list = try call(0x8060, 0)
      guard let flags = list.first, flags != 0 else {
        throw MouseFailure(message: "Logitech returned no supported polling rates.")
      }
      // Bit n represents n+1 milliseconds; do not confuse it with powers of two.
      rates = (1...8).filter { flags & (1 << ($0 - 1)) != 0 }
      let reply = try call(0x8060, 1)
      guard let value = reply.first, rates.contains(Int(value)) else {
        throw MouseFailure(message: "Unknown Logitech polling rate.")
      }
      rate = Int(value)
    }
    return LogitechState(
      mode: mode, dpi: dpi, dpiRange: range, rate: rate, rates: rates, features: features)
  }
  // Each action changes one setting, after a fresh compare. No automatic writes,
  // EEPROM rewrites, or bundled MJ-189 snapshots can reach this protocol.
  func setDPI(_ dpi: Int, expected: LogitechState) throws -> LogitechState {
    let before = try read()
    guard before == expected, before.hostControls, before.dpiRange?.contains(dpi) == true else {
      throw MouseFailure(message: "Refresh, enable live controls, and choose a supported DPI.")
    }
    if before.dpi == dpi { return before }
    try callDPI(dpi)
    let after = try read()
    guard after.dpi == dpi, after.mode == before.mode, after.rate == before.rate else {
      throw MouseFailure(message: "DPI readback did not match. Refresh to inspect the mouse.")
    }
    return after
  }
  private func callDPI(_ dpi: Int) throws {
    _ = try call(0x2201, 3, [0, UInt8(dpi >> 8), UInt8(dpi & 255)])
  }
  func setRate(_ rate: Int, expected: LogitechState) throws -> LogitechState {
    let before = try read()
    guard before == expected, before.hostControls, before.rates.contains(rate) else {
      throw MouseFailure(message: "Refresh, enable live controls, and choose a supported rate.")
    }
    if before.rate == rate { return before }
    _ = try call(0x8060, 2, [UInt8(rate)])
    let after = try read()
    guard after.rate == rate, after.mode == before.mode, after.dpi == before.dpi else {
      throw MouseFailure(message: "Polling readback did not match. Refresh to inspect the mouse.")
    }
    return after
  }
  // Recovery intentionally does not require a readable DPI/rate snapshot. A failed
  // live setting must never prevent the user from returning to onboard mode.
  func restoreOnboard() throws {
    let reply = try call(0x8100, 2)
    guard let current = reply.first else {
      throw MouseFailure(message: "Logitech did not report its mode. Reconnect and refresh.")
    }
    if current != 1 { _ = try call(0x8100, 1, [1]) }
    guard try mode() == 1 else {
      throw MouseFailure(message: "Logitech did not confirm onboard mode. Reconnect and refresh.")
    }
  }
  func setMode(_ value: Int, expected: LogitechState) throws -> LogitechState {
    guard [1, 2].contains(value), try read() == expected, expected.mode != nil else {
      throw MouseFailure(message: "The mouse settings changed. Refresh before changing modes.")
    }
    if expected.mode == value { return expected }
    _ = try call(0x8100, 1, [UInt8(value)])
    let after = try read()
    guard after.mode == value else {
      throw MouseFailure(message: "Logitech did not confirm the mode. Refresh to inspect it.")
    }
    return after
  }
}
