import Foundation
import IOKit.hid

struct MouseFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

struct Lighting: Codable, Equatable {
  var body: [UInt8]
  var wheel: [UInt8]
  init(_ profile: [UInt8]) {
    body = Array(profile[73..<79])
    wheel = Array(profile[100..<124])
  }
  var bodyOn: Bool { body[0] != 0 }
  var wheelOn: Bool { wheel.contains { $0 > 0 } }
  func merging(into profile: [UInt8]) -> [UInt8] {
    var result = profile
    result.replaceSubrange(73..<79, with: body)
    result.replaceSubrange(100..<124, with: wheel)
    return result
  }
}

struct MouseState {
  let profile: Int
  let data: [UInt8]
  var lighting: Lighting { Lighting(data) }
}

// Only the MJ-189 vendor configuration interface is opened. No input capture,
// exclusive access, or firmware updates are used. All writes are explicitly
// scoped by the profile controller, and readable settings are verified.
final class MouseConnection {
  private static let access = NSLock()
  private let manager: IOHIDManager
  private let device: IOHIDDevice
  private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
  private var reports: [[UInt8]] = []
  private let loop: CFRunLoop

  init() throws {
    Self.access.lock()
    manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    IOHIDManagerSetDeviceMatching(
      manager,
      [
        kIOHIDVendorIDKey: 0x260d,
        kIOHIDProductIDKey: 0x1027,
        kIOHIDPrimaryUsagePageKey: 0xff01,
        kIOHIDPrimaryUsageKey: 0xff01,
      ] as CFDictionary)
    let result = IOHIDManagerOpen(manager, 0)
    guard result == kIOReturnSuccess else {
      buffer.deallocate()
      Self.access.unlock()
      throw Self.error(result, "Connect to mouse")
    }
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, devices.count == 1,
      let found = devices.first
    else {
      IOHIDManagerClose(manager, 0)
      buffer.deallocate()
      Self.access.unlock()
      throw MouseFailure(message: "Connect one MJ-189 by USB, then click Refresh.")
    }
    device = found
    loop = CFRunLoopGetCurrent()
    IOHIDDeviceRegisterInputReportCallback(
      device, buffer, 64,
      { context, result, _, type, _, report, count in
        guard let context, result == kIOReturnSuccess, type == kIOHIDReportTypeInput, count == 64
        else { return }
        let owner = Unmanaged<MouseConnection>.fromOpaque(context).takeUnretainedValue()
        owner.reports.append(Array(UnsafeBufferPointer(start: report, count: count)))
      }, Unmanaged.passUnretained(self).toOpaque())
    IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
  }
  deinit {
    IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerClose(manager, 0)
    buffer.deallocate()
    Self.access.unlock()
  }
  static func discovery() -> (identity: UInt64?, count: Int) {
    let match =
      [
        kIOProviderClassKey: "IOUSBHostDevice",
        "IOPropertyMatch": ["idVendor": 0x260d, "idProduct": 0x1027],
      ] as CFDictionary
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == kIOReturnSuccess
    else { return (nil, 0) }
    defer { IOObjectRelease(iterator) }
    var count = 0
    var identity: UInt64?
    while true {
      let service = IOIteratorNext(iterator)
      if service == 0 { break }
      var value: UInt64 = 0
      if IORegistryEntryGetRegistryEntryID(service, &value) == kIOReturnSuccess { identity = value }
      count += 1
      IOObjectRelease(service)
    }
    return (count == 1 ? identity : nil, count)
  }
  static func error(_ code: IOReturn, _ action: String) -> MouseFailure {
    MouseFailure(
      message:
        "\(action) failed (\(String(format: "0x%08x", code))). Reconnect the mouse and try again.")
  }
  private func pump(_ seconds: TimeInterval) {
    CFRunLoopRunInMode(.defaultMode, seconds, false)
  }
  private func command(_ opcode: UInt8, _ parameters: [UInt8] = []) throws {
    var bytes = try Packet.command(opcode, parameters: parameters)
    let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, &bytes, bytes.count)
    guard result == kIOReturnSuccess else { throw Self.error(result, "Send mouse command") }
    pump(0.012)
  }
  private func reply(_ opcode: UInt8) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 8)
    var count = bytes.count
    let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &bytes, &count)
    guard result == kIOReturnSuccess else { throw Self.error(result, "Read mouse settings") }
    guard count == 8, bytes[0] == opcode else {
      throw MouseFailure(
        message: "The mouse returned an unexpected reply. No further settings were sent.")
    }
    return bytes
  }
  func activeProfile() throws -> Int {
    try command(0x84)
    let bytes = try reply(0x84)
    guard bytes[1] < 6 else {
      throw MouseFailure(message: "The active mouse profile could not be identified.")
    }
    return Int(bytes[1])
  }
  func readProfile(_ profile: Int) throws -> [UInt8] {
    guard (0..<6).contains(profile) else { throw MouseFailure(message: "Invalid mouse profile.") }
    pump(0.015)
    reports.removeAll()
    try command(0x86, [UInt8(profile)])
    let header = try reply(0x86)
    guard header[1] == profile, header[2] == 128 else {
      throw MouseFailure(message: "This mouse firmware uses an unsupported settings format.")
    }
    let deadline = Date().addingTimeInterval(1)
    while reports.count < 2 && Date() < deadline { pump(0.01) }
    guard reports.count == 2 else {
      throw MouseFailure(
        message: "Could not read the complete mouse profile. Reconnect and try again.")
    }
    let data = reports.flatMap { $0 }
    reports.removeAll()
    return data
  }
  // The text slot can be blanked without assuming the picture slot is empty.
  func showSideLogo(_ show: Bool) throws {
    if show { try setSideMode(0) } else { try sendTextPixels([UInt8](repeating: 0, count: 512)) }
  }
  func setSideMode(_ mode: Int) throws {
    guard (0...6).contains(mode) else { throw MouseFailure(message: "Invalid display mode.") }
    try command(0x0a, [UInt8(mode)])
    pump(0.08)
  }
  func sendTextPixels(_ bytes: [UInt8]) throws {
    guard bytes.count == 512 else { throw MouseFailure(message: "Invalid display image.") }
    for page in 0..<4 {
      try command(0x09, [UInt8(page), 128, 0])
      pump(0.064)
      try output(Array(bytes[page * 128..<(page + 1) * 128]))
      pump(0.08)
    }
    try setSideMode(5)
  }
  private func output(_ data: [UInt8]) throws {
    guard data.count % 64 == 0 else { throw MouseFailure(message: "Invalid mouse packet length.") }
    for offset in stride(from: 0, to: data.count, by: 64) {
      var packet = Array(data[offset..<offset + 64])
      let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &packet, 64)
      guard result == kIOReturnSuccess else { throw Self.error(result, "Save mouse settings") }
      pump(0.016)
    }
  }
  func readButtons() throws -> [UInt8] {
    pump(0.03)
    reports.removeAll()
    try command(0x87, [0, 0, 128])
    let header = try reply(0x87)
    guard header[1] == 0, header[2] == 128 else {
      throw MouseFailure(message: "Unsupported button map format.")
    }
    let deadline = Date().addingTimeInterval(1)
    while reports.count < 2 && Date() < deadline { pump(0.01) }
    guard reports.count == 2 else {
      throw MouseFailure(message: "Could not read the complete button map.")
    }
    let data = reports.flatMap { $0 }
    reports.removeAll()
    return data
  }
  func writeButtons(_ data: [UInt8], expected: [UInt8]) throws {
    guard data.count == 128, expected.count == 128 else {
      throw MouseFailure(message: "Invalid button map.")
    }
    guard
      stride(from: 0, to: 36, by: 4).contains(where: { Array(data[$0..<$0 + 4]) == [1, 0, 240, 0] })
    else {
      throw MouseFailure(message: "Keep at least one of the nine buttons assigned to Left click.")
    }
    guard try readButtons() == expected else {
      throw MouseFailure(message: "Button assignments changed. Reload before applying.")
    }
    if data == expected { return }
    try command(0x07, [0, 0, 128])
    pump(0.064)
    try output(data)
    pump(0.12)
    guard try readButtons() == data else {
      throw MouseFailure(
        message: "Button map verification failed. Reload to check the current settings.")
    }
  }
  func rawPollingRate() throws -> Int {
    try command(0x83)
    return Int(try reply(0x83)[1])
  }
  func pollingRate() throws -> Int {
    let rate = try rawPollingRate()
    guard [1, 2, 4, 8].contains(rate) else { throw MouseFailure(message: "Unknown polling rate.") }
    return rate
  }

  func setPollingRate(_ rate: Int) throws {
    guard [1, 2, 4, 8].contains(rate) else {
      throw MouseFailure(message: "Choose a supported polling rate.")
    }
    try command(0x03, [UInt8(rate)])
    pump(0.1)
    guard try pollingRate() == rate else {
      throw MouseFailure(message: "Polling rate verification failed.")
    }
  }
  func setLiftOff(_ height: Int) throws {
    guard [2, 3].contains(height) else { throw MouseFailure(message: "Choose 2 or 3 mm.") }
    try command(0x0b, [UInt8(height)])
    pump(0.12)
  }
  func writeProfile(_ data: [UInt8], expected: MouseState) throws -> MouseState {
    guard data.count == 128 else { throw MouseFailure(message: "Invalid profile length.") }
    guard try activeProfile() == expected.profile,
      try readProfile(expected.profile) == expected.data
    else {
      throw MouseFailure(message: "The mouse settings changed. Reload before applying.")
    }
    if data == expected.data { return expected }
    try command(0x06, [UInt8(expected.profile), 128])
    pump(0.064)
    try output(data)
    pump(0.12)
    let result = try readProfile(expected.profile)
    guard result == data else {
      throw MouseFailure(
        message: "Profile verification failed. Reload to check the current settings.")
    }
    return MouseState(profile: expected.profile, data: result)
  }
  func sendMacro(slot: Int, data: [UInt8]) throws {
    guard (1...16).contains(slot), data.count == 128 else {
      throw MouseFailure(message: "Invalid macro slot or length.")
    }
    try command(0x08, [UInt8(slot), 128])
    pump(0.064)
    try output(data)
    pump(0.12)
  }
  func setRapidFire(key: Int, count: Int, x: Int, y: Int) throws {
    guard (0...255).contains(key), (0...255).contains(count), (-127...127).contains(x),
      (-127...127).contains(y)
    else { throw MouseFailure(message: "Rapid-fire values are outside the supported range.") }
    try command(
      0x04,
      [UInt8(key), UInt8(count), UInt8(truncatingIfNeeded: x), UInt8(truncatingIfNeeded: y), 0])
    pump(0.12)
  }
  func state() throws -> MouseState {
    let profile = try activeProfile()
    return MouseState(profile: profile, data: try readProfile(profile))
  }
  func apply(_ lighting: Lighting, to state: MouseState) throws -> MouseState {
    guard lighting.body.count == 6, lighting.wheel.count == 24 else {
      throw MouseFailure(message: "The saved lighting settings are invalid.")
    }
    guard try activeProfile() == state.profile else {
      throw MouseFailure(message: "The mouse profile changed. Click Refresh and try again.")
    }
    let fresh = try readProfile(state.profile)
    guard fresh == state.data else {
      throw MouseFailure(
        message: "Mouse settings changed while editing. Click Refresh and try again.")
    }
    let data = lighting.merging(into: fresh)
    if data == fresh { return state }
    // Enforce the lighting-only boundary even if the UI is changed later.
    let permitted = Set(73..<79).union(100..<124)
    precondition((0..<128).allSatisfy { permitted.contains($0) || fresh[$0] == data[$0] })
    try command(0x06, [UInt8(state.profile), 128])
    pump(0.064)
    for start in stride(from: 0, to: 128, by: 64) {
      var packet = Array(data[start..<start + 64])
      let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &packet, 64)
      guard result == kIOReturnSuccess else { throw Self.error(result, "Save lighting settings") }
      pump(0.012)
    }
    pump(0.08)
    let actual = try readProfile(state.profile)
    guard actual == data else {
      throw MouseFailure(
        message:
          "The mouse did not confirm the new settings. Click Refresh to check its current state.")
    }
    guard try activeProfile() == state.profile else {
      throw MouseFailure(
        message: "Lighting was saved, but the active profile changed. Click Refresh.")
    }
    return MouseState(profile: state.profile, data: actual)
  }
}
