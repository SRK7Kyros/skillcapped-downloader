import Foundation

extension Bundle {
  var appVersion: String {
    let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(short) (\(build))"
  }
}
