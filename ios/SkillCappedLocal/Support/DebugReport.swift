import Foundation

/// Everything the app knows about the background queue, as one block of text.
///
/// Settings lists a handful of journal lines, which is enough to read on the phone
/// but not to send anywhere: a screenshot of a scrolling form cannot be searched,
/// and the lines above the fold — usually the ones that explain the ones below —
/// are not in the picture at all. This assembles the whole journal with the facts
/// that give it meaning, so the copy button and its tests read the same text.
struct DebugReport {
  let app: String
  let folder: String
  let source: String
  let queued: Int
  let onDisk: String
  let activity: LiveActivityReport
  let journal: [String]
  let limit: Int

  /// How much of the journal is here, and whether older lines were dropped — a
  /// readout that looks complete but is not is worse than one that says so.
  var journalHeading: String {
    if journal.isEmpty { return "Background queue (nothing recorded)" }
    if journal.count >= limit {
      return "Background queue (last \(journal.count) lines, older ones dropped)"
    }
    return "Background queue (\(journal.count) line\(journal.count == 1 ? "" : "s"))"
  }

  /// One string, ready for the clipboard: what the build is, where the library
  /// lives, what the queue is doing, why the card is or is not showing, then the
  /// journal as it was written — oldest first, one event per line.
  var text: String {
    var lines = [
      "SkillCapped Local \(app)",
      "Folder: \(folder) — \(source)",
      "Queue: \(queued) in the queue · \(onDisk) on disk",
      "Live Activity: \(activity.verdict.sentence)"
    ]
    lines += activity.facts.map { "  \($0)" }
    lines.append("\(journalHeading):")
    lines += journal.isEmpty ? ["  (none)"] : journal
    return lines.joined(separator: "\n")
  }
}
