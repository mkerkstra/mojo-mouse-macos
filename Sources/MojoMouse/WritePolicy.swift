import Foundation

enum WritePolicy {
  static let knownProfileOffsets = Set([35, 36, 71]).union(37..<69).union(73..<79).union(100..<124)
  static func validate(
    _ desired: FullSnapshot, comparedTo current: FullSnapshot, experimental: Bool
  ) throws {
    try desired.validate()
    guard current.data.count == 128, current.buttons.count == 128 else {
      throw MouseFailure(message: "The comparison profile is invalid.")
    }
    guard !experimental else { return }
    for i in 0..<128 where !knownProfileOffsets.contains(i) && desired.data[i] != current.data[i] {
      throw MouseFailure(
        message:
          "This profile changes vendor-specific bytes. Review it with experimental controls enabled before applying."
      )
    }
    for start in stride(from: 0, to: 128, by: 4) {
      let code = Array(desired.buttons[start..<start + 4])
      if code != Array(current.buttons[start..<start + 4]) && !knownButton(code) {
        throw MouseFailure(
          message:
            "This profile changes an unverified button action. Enable experimental controls to review it manually; automatic rules will not apply that change."
        )
      }
    }
  }
  static func knownButton(_ b: [UInt8]) -> Bool {
    guard b.count == 4 else { return false }
    if b == [0, 0, 0, 0] || b == [10, 7, 0, 0] || b == [10, 240, 30, 2] { return true }
    if b[0] == 1 && b[1] == 0 && b[3] == 0
      && ([240, 241, 242, 243, 244, 247, 248] as [UInt8]).contains(b[2])
    {
      return true
    }
    if b[0] == 7 && b[1] == 0 && b[3] == 0 && (1...3).contains(b[2]) { return true }
    if b[0] == 3 && b[1] == 0 {
      return (b[3] == 0 && ([181, 182, 183, 205, 226, 233, 234] as [UInt8]).contains(b[2]))
        || b == [3, 0, 131, 1] || b == [3, 0, 35, 2] || b == [3, 0, 33, 2]
    }
    if b[0] == 0 && b[1] == 0 {
      let key: (UInt8) -> Bool = { (4...115).contains($0) || (224...231).contains($0) }
      return (key(b[2]) && b[3] == 0) || ((224...231).contains(b[2]) && (4...115).contains(b[3]))
    }
    return false
  }
}
