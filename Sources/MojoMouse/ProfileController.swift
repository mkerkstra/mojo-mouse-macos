import Foundation

protocol MouseSession: AnyObject {
  func state() throws -> MouseState
  func readButtons() throws -> [UInt8]
  func pollingRate() throws -> Int
  func rawPollingRate() throws -> Int
  func writeProfile(_ data: [UInt8], expected: MouseState) throws -> MouseState
  func writeButtons(_ data: [UInt8], expected: [UInt8]) throws
  func setPollingRate(_ rate: Int) throws
  func setSideMode(_ mode: Int) throws
  func sendTextPixels(_ bytes: [UInt8]) throws
}
extension MouseConnection: MouseSession {}

final class ProfileController {
  let store: LibraryStore
  init(store: LibraryStore = .shared) { self.store = store }
  func snapshot(_ mouse: MouseSession, validate: Bool = true) throws -> FullSnapshot {
    let state = try mouse.state()
    let snapshot = FullSnapshot(
      profile: state.profile, data: state.data, buttons: try mouse.readButtons(),
      rate: try mouse.rawPollingRate())
    if validate { try snapshot.validate() }
    return snapshot
  }
  @discardableResult func apply(
    _ profile: NamedProfile, to mouse: MouseSession, textPixels: [UInt8]? = nil,
    experimental: Bool = false
  ) throws -> FullSnapshot {
    try profile.validate()
    if profile.display.mode == "text", textPixels?.count != 512 {
      throw MouseFailure(message: "The custom text was not rendered.")
    }
    let original = try snapshot(mouse)
    var desired =
      profile.scope == "lighting"
      ? profile.snapshot.mergingLighting(into: original) : profile.snapshot
    desired.profile = original.profile
    try desired.validate()
    try WritePolicy.validate(desired, comparedTo: original, experimental: experimental)
    let changed =
      original.data != desired.data || original.buttons != desired.buttons
      || original.rate != desired.rate
    if changed { try store.backup(original) }
    do {
      _ = try mouse.writeProfile(
        desired.data, expected: MouseState(profile: original.profile, data: original.data))
      try mouse.writeButtons(desired.buttons, expected: original.buttons)
      if desired.rate != original.rate { try mouse.setPollingRate(desired.rate) }
      let actual = try snapshot(mouse)
      guard actual.profile == original.profile, actual.data == desired.data,
        actual.buttons == desired.buttons,
        actual.rate == desired.rate
      else {
        throw MouseFailure(message: "The mouse did not confirm the complete profile.")
      }
    } catch {
      guard changed else { throw error }
      do {
        let partial: FullSnapshot
        do { partial = try snapshot(mouse, validate: false) } catch {
          // Retry a transient read failure without rejecting an invalid partial
          // profile. Never blindly overwrite an unreadable/stale device state.
          Thread.sleep(forTimeInterval: 0.02)
          partial = try snapshot(mouse, validate: false)
        }
        guard partial.profile == original.profile else {
          throw SlotChangedFailure(profile: original.profile)
        }
        _ = try mouse.writeProfile(
          original.data, expected: MouseState(profile: partial.profile, data: partial.data))
        try mouse.writeButtons(original.buttons, expected: partial.buttons)
        if partial.rate != original.rate { try mouse.setPollingRate(original.rate) }
        let restored = try snapshot(mouse)
        guard restored.profile == original.profile, restored.data == original.data,
          restored.buttons == original.buttons,
          restored.rate == original.rate
        else {
          throw MouseFailure(message: "Backup verification failed.")
        }
        throw RestoredFailure(cause: error.localizedDescription)
      } catch let slot as SlotChangedFailure {
        throw MouseFailure(
          message:
            "The active hardware profile changed during apply. Recovery did not write to the newly selected slot. Profile \(slot.profile + 1) may have changed; select it, reload, and use your backup if needed."
        )
      } catch let restored as RestoredFailure {
        throw MouseFailure(
          message:
            "Profile could not be applied. Your previous settings were restored and verified. \(restored.cause)"
        )
      } catch {
        throw MouseFailure(
          message:
            "Profile application was interrupted and rollback could not be verified. Some settings may have changed. Reconnect, reload, and use your backup if needed."
        )
      }
    }
    do {
      switch profile.display.mode {
      case "blank": try mouse.sendTextPixels([UInt8](repeating: 0, count: 512))
      case "logo": try mouse.setSideMode(0)
      case "text":
        guard let textPixels, textPixels.count == 512 else {
          throw MouseFailure(message: "The custom text was not rendered.")
        }
        try mouse.sendTextPixels(textPixels)
      default: break
      }
    } catch {
      throw MouseFailure(
        message:
          "Profile settings were saved and verified, but the side-display change failed: \(error.localizedDescription)"
      )
    }
    return desired
  }
  private struct SlotChangedFailure: Error { let profile: Int }
  private struct RestoredFailure: Error { let cause: String }
}
