import Foundation

enum Packet {
  static func command(_ opcode: UInt8, parameters: [UInt8] = []) throws -> [UInt8] {
    guard parameters.count <= 6 else {
      throw MouseFailure(message: "Too many parameters for a mouse command.")
    }
    var data = [opcode] + parameters
    data += [UInt8](repeating: 0, count: 7 - data.count)
    data.append(~data.reduce(UInt8(0), &+))
    return data
  }
}
