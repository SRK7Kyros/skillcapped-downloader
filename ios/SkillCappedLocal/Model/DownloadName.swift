import Foundation

/// What a file name says about the lesson behind it. Two shapes exist: a name
/// written now is `<NN> - <Title> <quality>`, and anything written before the
/// number is `<Title> [<uuid>] <quality>`. Files with neither (a hand-copied
/// video, say) keep their own name.
struct DownloadName: Equatable {
  let title: String
  let id: String?
  let number: Int?
  let quality: String?

  static let playableExtensions: Set<String> = ["mp4", "m4v", "mov", "ts", "m2ts"]

  private static let legacy: NSRegularExpression? = try? NSRegularExpression(
    pattern: #"^(.*?)\s*\[([a-z0-9]{6,12})\]\s*(\d{3,4}p)$"#,
    options: [.caseInsensitive]
  )

  private static let numbered: NSRegularExpression? = try? NSRegularExpression(
    pattern: #"^(\d+)\s*-\s*(.*)\s+(\d{3,4}p)$"#,
    options: [.caseInsensitive]
  )

  static func parse(_ fileName: String) -> DownloadName {
    let base = (fileName as NSString).deletingPathExtension
    let fallback = DownloadName(title: base, id: nil, number: nil, quality: nil)
    guard !base.isEmpty else { return fallback }

    // Legacy first: a title that begins with digits ("3 - Wave Control") would
    // otherwise be read as a number and lose the uuid that identifies it.
    if let match = match(legacy, in: base), match.numberOfRanges == 4,
       let titleRange = Range(match.range(at: 1), in: base),
       let idRange = Range(match.range(at: 2), in: base),
       let qualityRange = Range(match.range(at: 3), in: base) {
      let title = base[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
      return DownloadName(
        title: title.isEmpty ? base : title,
        id: base[idRange].lowercased(),
        number: nil,
        quality: base[qualityRange].lowercased()
      )
    }

    if let match = match(numbered, in: base), match.numberOfRanges == 4,
       let numberRange = Range(match.range(at: 1), in: base),
       let titleRange = Range(match.range(at: 2), in: base),
       let qualityRange = Range(match.range(at: 3), in: base) {
      let title = base[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
      return DownloadName(
        title: title.isEmpty ? base : title,
        id: nil,
        number: Int(base[numberRange]),
        quality: base[qualityRange].lowercased()
      )
    }

    return fallback
  }

  private static func match(_ pattern: NSRegularExpression?, in text: String) -> NSTextCheckingResult? {
    guard let pattern else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return pattern.firstMatch(in: text, options: [], range: range)
  }
}
