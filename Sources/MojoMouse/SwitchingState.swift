import Foundation

struct SwitchingState {
  var generation = 0
  var suspended = false
  var pausedUntil: Date?
  var lastKey: String?
  var retryAfter = Date.distantPast
  var failureCount = 0

  mutating func changed(clearPause: Bool) {
    generation += 1
    lastKey = nil
    failureCount = 0
    retryAfter = .distantPast
    if clearPause { pausedUntil = nil }
  }
  mutating func pause(at now: Date, minutes: Int = 60) {
    generation += 1
    lastKey = nil
    pausedUntil = now.addingTimeInterval(Double(minutes) * 60)
  }
  mutating func resume() { changed(clearPause: true) }
  mutating func sleep() {
    generation += 1
    suspended = true
    lastKey = nil
  }
  mutating func wake(at now: Date) {
    generation += 1
    suspended = false
    lastKey = nil
    retryAfter = now.addingTimeInterval(3)
  }
  func accepts(token: Int, at now: Date) -> Bool {
    token == generation && !suspended && (pausedUntil == nil || pausedUntil! <= now)
  }
  mutating func failed(at now: Date) {
    lastKey = nil
    failureCount += 1
    retryAfter = now.addingTimeInterval(min(300, 30 * pow(2, Double(min(failureCount - 1, 4)))))
  }
  mutating func succeeded(key: String) {
    lastKey = key
    failureCount = 0
    retryAfter = .distantPast
  }
}
