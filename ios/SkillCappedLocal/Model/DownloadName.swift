import Foundation

/// The downloader names every finished lesson `<title> [<uuid>] <quality>.<ext>`.
/// Files without the suffix (a hand-copied video, say) keep their own name.
struct DownloadName: Equatable {
  let title: String
  let id: String?
  let quality: String?

  static let playableExtensions: Set<String> = ["mp4", "m4v", "mov", "ts", "m2ts"]

  private static let pattern: NSRegularExpression? = try? NSRegularExpression(
    pattern: #"^(.*?)\s*\[([a-z0-9]{6,12})\]\s*(\d{3,4}p)$"#,
    options: [.caseInsensitive]
  )

  static func parse(_ fileName: String) -> DownloadName {
    let base = (fileName as NSString).deletingPathExtension
    let fallback = DownloadName(title: base, id: nil, quality: nil)
    guard let pattern, !base.isEmpty else { return fallback }

    let range = NSRange(base.startIndex..<base.endIndex, in: base)
    guard let match = pattern.firstMatch(in: base, options: [], range: range),
          match.numberOfRanges == 4,
          let titleRange = Range(match.range(at: 1), in: base),
          let idRange = Range(match.range(at: 2), in: base),
          let qualityRange = Range(match.range(at: 3), in: base)
    else { return fallback }

    let title = base[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
    return DownloadName(
      title: title.isEmpty ? base : title,
      id: base[idRange].lowercased(),
      quality: base[qualityRange].lowercased()
    )
  }
}
