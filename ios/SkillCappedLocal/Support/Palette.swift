import SwiftUI

/// The console's dark palette, so the phone build reads as the same product.
enum Palette {
  static let bg = Color(red: 0.039, green: 0.039, blue: 0.047)
  static let surface = Color.white.opacity(0.045)
  static let surfaceStrong = Color.white.opacity(0.075)
  static let line = Color.white.opacity(0.10)
  static let ink = Color.white.opacity(0.96)
  static let inkDim = Color.white.opacity(0.72)
  static let inkFaint = Color.white.opacity(0.50)
  static let brand = Color(red: 0.13, green: 0.88, blue: 0.42)
  static let warn = Color(red: 0.98, green: 0.72, blue: 0.25)
  static let danger = Color(red: 0.95, green: 0.32, blue: 0.31)

  /// Deterministic cover colours for a lesson whose file cannot yield a frame.
  static func gradient(for seed: String) -> [Color] {
    var hash: UInt64 = 5381
    for byte in seed.utf8 {
      hash = (hash &* 33) &+ UInt64(byte)
    }
    let hue = Double(hash % 360) / 360
    let second = (hue + 0.09).truncatingRemainder(dividingBy: 1)
    return [
      Color(hue: hue, saturation: 0.38, brightness: 0.32),
      Color(hue: second, saturation: 0.52, brightness: 0.14),
    ]
  }
}
