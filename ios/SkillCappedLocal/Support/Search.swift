import Foundation

/// One search rule for both surfaces: every word has to appear somewhere in the
/// row, accents and case ignored. Cheap enough to run per keystroke over a few
/// thousand catalogue rows.
enum Search {
  static func matches(_ haystack: String, query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    let folded = fold(haystack)
    return trimmed.split(separator: " ").allSatisfy { folded.contains(fold(String($0))) }
  }

  private static func fold(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
  }
}
