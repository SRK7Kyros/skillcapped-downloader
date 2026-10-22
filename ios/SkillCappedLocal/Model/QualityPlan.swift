import Foundation

/// One rendition the CDN publishes. The id is the number in the segment address
/// (`HIDDEN2500-00001.ts`); the label is what the downloader writes into a file
/// name, so it is also what the scanner reads back.
struct QualityTier: Codable, Hashable, Identifiable {
  let id: Int
  let label: String
  let short: String
  let height: Int

  static let hd720 = QualityTier(id: 1500, label: "720p", short: "720", height: 720)
  static let hd1080 = QualityTier(id: 2500, label: "1080p", short: "1080", height: 1080)
  static let uhd2160 = QualityTier(id: 4500, label: "2160p", short: "4K", height: 2160)

  /// Every rendition the downloader knows today. A tier that shows up later is
  /// still usable — the app records whatever labels it sees.
  static let standard: [QualityTier] = [hd720, hd1080, uhd2160]

  static func byId(_ id: Int) -> QualityTier? {
    standard.first { $0.id == id }
  }

  /// Resolves either the file-name label (`2160p`) or the name the app shows
  /// (`4K`), so a priority list may be written in either vocabulary.
  static func byLabel(_ label: String) -> QualityTier? {
    standard.first {
      $0.label.lowercased() == label.lowercased() || $0.short.lowercased() == label.lowercased()
    }
  }

  /// Height parsed out of a label, so an unknown tier still sorts sensibly.
  static func height(of label: String) -> Int {
    if let tier = byLabel(label) { return tier.height }
    let digits = label.prefix { $0.isNumber }
    return Int(digits) ?? 0
  }

  static func id(of label: String) -> Int? {
    if let tier = byLabel(label) { return tier.id }
    // `1080p` is not a CDN id; only the known tiers have one.
    return nil
  }
}

/// Which rendition a download asks for, and what to fall back to when the CDN
/// does not publish it. The preference is a plain ordered list of labels the
/// user can rearrange — `1080p → 720p → 4K` means "1080p if it exists, else
/// 720p, else 4K", not "the best available".
enum QualityPlan {
  /// The order the app ships with: the phone-friendly pick first, then the
  /// smaller one, then the largest.
  static let defaultPriority = ["1080p", "720p", "4K"]

  /// Every label worth offering, best first: the known tiers, then anything the
  /// catalogue has shown us that this build does not know by name.
  static func knownLabels(extra: [String] = []) -> [String] {
    var labels = QualityTier.standard.sorted { $0.height > $1.height }.map(\.label)
    for label in extra where !labels.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
      labels.append(label)
    }
    return labels
  }

  /// Best first, for a picker that lists what the CDN actually has.
  static func sorted(_ labels: [String]) -> [String] {
    labels.sorted { QualityTier.height(of: $0) > QualityTier.height(of: $1) }
  }

  /// The fallback chain for one download: the requested rendition, then the
  /// user's priority order, then every other known tier, best first.
  static func ladder(requested: String?, priority: [String], available: [String]) -> [String] {
    var chain: [String] = []
    func add(_ label: String) {
      let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      guard !chain.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
      chain.append(trimmed)
    }
    if let requested { add(requested) }
    for label in priority { add(label) }
    for label in sorted(available) { add(label) }
    for label in knownLabels() { add(label) }
    return chain
  }

  /// The rendition to download: the first link of the ladder the CDN publishes.
  static func pick(requested: String?, priority: [String], available: [String]) -> String? {
    let offered = available.map { $0.lowercased() }
    guard !offered.isEmpty else { return nil }
    for label in ladder(requested: requested, priority: priority, available: available) {
      if offered.contains(label.lowercased()) { return canonical(label, available: available) }
    }
    return sorted(available).first
  }

  /// Keep the CDN's own spelling of a label (e.g. `4K` rather than `2160p` when
  /// that is what the file carries).
  private static func canonical(_ label: String, available: [String]) -> String {
    available.first { $0.caseInsensitiveCompare(label) == .orderedSame } ?? label
  }
}
