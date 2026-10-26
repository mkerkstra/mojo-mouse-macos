import Foundation
import IOKit.hid
import IOKit.hidsystem

struct LogitechDevice {
  let identity: UInt64
  let product: Int
  let hid: IOHIDDevice
  let requiresInputPermission: Bool
  var name: String { LogitechCatalog.models[product] ?? "Unknown Logitech mouse" }
  var usbID: String { String(format: "046d:%04x", product) }
}

final class LogitechHID: HIDPPTransport {
  private static let access = NSLock()
  private static var sequence: UInt8 = 2
  private let device: IOHIDDevice
  private let loop: CFRunLoop
  private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
  private var reports: [[UInt8]] = []

  // Enumerating descriptors does not open mouse/keyboard input interfaces.
  static func discover() -> [LogitechDevice] {
    guard AppInfo.allowsExperimental else { return [] }
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    let matches = LogitechCatalog.models.keys.sorted().map {
      [kIOHIDVendorIDKey: 0x046d, kIOHIDProductIDKey: $0] as [String: Any]
    }
    IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    return devices.compactMap { device in
      let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
      let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
      let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
      let primaryUsage =
        IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
      let pairs =
        IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]]
        ?? []
      let usages =
        pairs.compactMap { pair -> HIDUsagePair? in
          guard let page = pair[kIOHIDDeviceUsagePageKey] as? Int,
            let usage = pair[kIOHIDDeviceUsageKey] as? Int
          else { return nil }
          return HIDUsagePair(page: page, usage: usage)
        } + [HIDUsagePair(page: page, usage: primaryUsage)]
      let transport =
        IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
      guard
        LogitechCatalog.accepts(
          vendor: vendor, product: product, usagePages: usages.map(\.page), transport: transport),
        let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement]
      else { return nil }
      let inputTypes: [IOHIDElementType] = [
        kIOHIDElementTypeInput_Misc, kIOHIDElementTypeInput_Button, kIOHIDElementTypeInput_Axis,
      ]
      let input = elements.contains { element in
        IOHIDElementGetReportID(element) == 0x11 && IOHIDElementGetUsagePage(element) >= 0xff00
          && inputTypes.contains(IOHIDElementGetType(element))
      }
      let output = elements.contains {
        IOHIDElementGetReportID($0) == 0x11 && IOHIDElementGetUsagePage($0) >= 0xff00
          && IOHIDElementGetType($0) == kIOHIDElementTypeOutput
      }
      var identity: UInt64 = 0
      guard input, output,
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &identity)
          == kIOReturnSuccess
      else { return nil }
      return LogitechDevice(
        identity: identity, product: product, hid: device,
        requiresInputPermission: LogitechCatalog.requiresInputPermission(usages))
    }.sorted { $0.product == $1.product ? $0.identity < $1.identity : $0.product < $1.product }
  }
  init(identity: UInt64) throws {
    Self.access.lock()
    guard AppInfo.allowsExperimental,
      let found = Self.discover().first(where: { $0.identity == identity })
    else {
      buffer.deallocate()
      Self.access.unlock()
      throw MouseFailure(message: "The selected Logitech mouse disconnected. Scan again.")
    }
    // Check only; never call IOHIDRequestAccess or silently trigger a permission request
    // for a composite interface that includes keyboard/pointer collections.
    if found.requiresInputPermission
      && IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted
    {
      buffer.deallocate()
      Self.access.unlock()
      throw MouseFailure(
        message:
          "This Logitech USB interface includes keyboard/pointer controls. To use it, manually add this app with + in System Settings → Privacy & Security → Input Monitoring, then restart. Review the guide first; no permission is requested automatically."
      )
    }
    // Keep device/loop uninitialized until open succeeds. On a throwing partial
    // initialization Swift does not run deinit, so this branch owns cleanup once.
    let result = IOHIDDeviceOpen(found.hid, 0)  // Shared access, never seize normal input.
    guard result == kIOReturnSuccess else {
      buffer.deallocate()
      Self.access.unlock()
      throw MouseConnection.error(result, "Open Logitech configuration interface")
    }
    device = found.hid
    loop = CFRunLoopGetCurrent()
    IOHIDDeviceRegisterInputReportCallback(
      device, buffer, 64,
      { context, result, _, type, reportID, report, count in
        guard let context, result == kIOReturnSuccess, type == kIOHIDReportTypeInput,
          (reportID == 0x10 && count == 7) || (reportID == 0x11 && count == 20)
        else { return }
        let owner = Unmanaged<LogitechHID>.fromOpaque(context).takeUnretainedValue()
        // Notifications can arrive without a request; bound memory even on noisy firmware.
        if owner.reports.count < 64 {
          owner.reports.append(Array(UnsafeBufferPointer(start: report, count: count)))
        }
      }, Unmanaged.passUnretained(self).toOpaque())
    IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
  }
  deinit {
    IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
    IOHIDDeviceClose(device, 0)
    buffer.deallocate()
    Self.access.unlock()
  }
  func request(feature: UInt8, function: UInt8, parameters: [UInt8]) throws -> [UInt8] {
    // All requests and this sequence are serialized by the lifetime connection lock.
    Self.sequence = Self.sequence == 15 ? 2 : Self.sequence + 1
    let packet = try HIDPPPacket(
      feature: feature, function: function, softwareID: Self.sequence, parameters: parameters)
    CFRunLoopRunInMode(.defaultMode, 0.002, false)
    reports.removeAll()
    var bytes = packet.bytes
    let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, &bytes, bytes.count)
    guard result == kIOReturnSuccess else {
      throw MouseConnection.error(result, "Send Logitech command")
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 1.5
    while ProcessInfo.processInfo.systemUptime < deadline {
      while !reports.isEmpty {
        if let response = try packet.response(reports.removeFirst()) { return response }
      }
      CFRunLoopRunInMode(.defaultMode, 0.01, false)
    }
    throw MouseFailure(
      message: "Logitech did not reply. Quit other mouse utilities, reconnect, then refresh.")
  }
}
