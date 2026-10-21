import Foundation

enum Format {
  static func bytes(_ value: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    formatter.includesUnit = true
    return formatter.string(fromByteCount: value)
  }

  static func clock(_ seconds: Int) -> String {
    guard seconds > 0 else { return "--:--" }
    let total = seconds
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }

  static func roleLabel(_ role: String) -> String {
    switch role.lowercased() {
    case "adc": return "ADC"
    case "top": return "Top"
    case "jungle": return "Jungle"
    case "mid": return "Mid"
    case "support": return "Support"
    case "": return "All roles"
    default: return role.capitalized
    }
  }

  static func date(_ date: Date?) -> String? {
    guard let date else { return nil }
    return date.formatted(.dateTime.year().month(.abbreviated).day())
  }

  static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
    "\(value) \(value == 1 ? singular : plural)"
  }
}
