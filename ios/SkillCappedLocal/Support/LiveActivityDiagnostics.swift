import ActivityKit
import Foundation
import UIKit

/// Why the lock-screen card is, or is not, showing.
///
/// The card is drawn by a widget in another process, so a card that never appears
/// leaves no trace inside the app: it asked, iOS answered, the lock screen stayed
/// empty. These are the facts the chain is made of — whether the phone allows
/// cards at all, whether the widget that draws one is installed and signed,
/// whether that widget belongs to this app, and what iOS said when asked — so a
/// device the developer does not hold can answer for itself.
enum LiveActivityVerdict: Equatable {
  case cardsOff
  case noExtension
  case unsignedExtension
  case foreignExtension(String)
  case refused(String)
  case idle
  case showing(Int)

  /// Read in the order the chain fails: a card cannot be refused for a reason
  /// further down than the first fact that is already untrue.
  static func of(
    enabled: Bool,
    extensionPresent: Bool,
    extensionSigned: Bool,
    extensionIdentifier: String?,
    appIdentifier: String?,
    cards: [String],
    error: String?
  ) -> LiveActivityVerdict {
    guard enabled else { return .cardsOff }
    guard extensionPresent else { return .noExtension }
    guard extensionSigned else { return .unsignedExtension }
    if let id = extensionIdentifier, let app = appIdentifier, !id.hasPrefix(app) {
      return .foreignExtension(id)
    }
    if let error, !error.isEmpty { return .refused(error) }
    return cards.isEmpty ? .idle : .showing(cards.count)
  }

  /// One sentence, in words that can be read as they are.
  var sentence: String {
    switch self {
    case .cardsOff:
      return "Live Activities are off — turn on Settings › SkillCapped Local › Live Activities."
    case .noExtension:
      return "The widget that draws the card is missing from this build — reinstall the app."
    case .unsignedExtension:
      return "The card's widget carries no signature, so iOS will not load it. The sideloader has to sign the app's extensions too."
    case .foreignExtension(let id):
      return "The card's widget calls itself \(id), which is not this app's — iOS ignores it."
    case .refused(let why):
      return "iOS refused the card: \(why)"
    case .idle:
      return "Everything the card needs is in place — it appears when a download starts."
    case .showing(let count):
      return count == 1
        ? "One card is live — it should be on the lock screen and in the island."
        : "\(count) cards are live — they should be on the lock screen."
    }
  }
}

/// The facts behind the verdict, gathered on the device that has them.
struct LiveActivityReport {
  let enabled: Bool
  let cards: [String]
  let extensionPresent: Bool
  let extensionSigned: Bool
  let extensionIdentifier: String?
  let appIdentifier: String?
  let systemVersion: String
  let error: String?

  var verdict: LiveActivityVerdict {
    .of(
      enabled: enabled,
      extensionPresent: extensionPresent,
      extensionSigned: extensionSigned,
      extensionIdentifier: extensionIdentifier,
      appIdentifier: appIdentifier,
      cards: cards,
      error: error
    )
  }

  /// The facts the verdict was read from, so a screenshot answers the question
  /// even when the verdict itself is the surprising part.
  var facts: [String] {
    [
      "Cards allowed: \(enabled ? "yes" : "no")",
      "Cards live: \(cards.isEmpty ? "none" : cards.joined(separator: ", "))",
      "Widget: \(extensionPresent ? "installed" : "missing")\(extensionSigned ? ", signed" : ", unsigned")",
      "Widget id: \(extensionIdentifier ?? "—")",
      "App id: \(appIdentifier ?? "—")",
      "System: iOS \(systemVersion)",
      "Last refusal: \(error ?? "none")"
    ]
  }
}

enum LiveActivityInspector {
  static let widgetName = "SkillCappedLocalWidget"

  static func read(error: String?) -> LiveActivityReport {
    let url = widgetURL()
    return LiveActivityReport(
      enabled: ActivityAuthorizationInfo().areActivitiesEnabled,
      cards: Activity<DownloadActivityAttributes>.activities.map(stateName),
      extensionPresent: url != nil,
      extensionSigned: url.map(isSigned) ?? false,
      extensionIdentifier: url.flatMap { Bundle(url: $0)?.bundleIdentifier },
      appIdentifier: Bundle.main.bundleIdentifier,
      systemVersion: UIDevice.current.systemVersion,
      error: error
    )
  }

  /// Where the widget sits inside the installed app. iOS only registers an
  /// extension it found here, so its absence is the first thing to rule out.
  static func widgetURL() -> URL? {
    let url = Bundle.main.bundleURL
      .appendingPathComponent("PlugIns")
      .appendingPathComponent("\(widgetName).appex")
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  /// A bundle iOS will load carries its own seal; one a sideloader left unsigned
  /// has none and is skipped without a word.
  static func isSigned(_ url: URL) -> Bool {
    FileManager.default.fileExists(
      atPath: url.appendingPathComponent("_CodeSignature/CodeResources").path
    )
  }

  static func stateName(_ activity: Activity<DownloadActivityAttributes>) -> String {
    switch activity.activityState {
    case .active:
      return "active"
    case .stale:
      return "stale"
    case .ended:
      return "ended"
    case .dismissed:
      return "dismissed"
    @unknown default:
      return "unknown"
    }
  }
}
