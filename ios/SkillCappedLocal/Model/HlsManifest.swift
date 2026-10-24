import Foundation

/// A rendition's own segment list — `HIDDEN<quality>.m3u8`, published beside the
/// parts it names.
///
/// The manifest is the authority on where a video ends. The distribution keeps
/// 200-answering parts from an older, longer encode behind the manifest's last
/// entry, so a tail found by probing appends footage that is not part of the
/// video (a two-minute lesson arriving as ten, with its own holes). Only a video
/// that publishes no manifest is probed.
enum HlsManifest {
  struct Listing: Equatable {
    let count: Int
    let seconds: Double
  }

  static func url(uuid: String, qualityId: Int) -> URL? {
    URL(string: "\(SegmentDownloader.cdnOrigin)/\(uuid)/HIDDEN\(qualityId).m3u8")
  }

  /// `nil` unless the whole listing is understood: an `#EXTM3U` header, one
  /// positive `#EXTINF` per part, and part numbers running exactly 1..n.
  static func listing(_ text: String) -> Listing? {
    var durations: [Double] = []
    var pending: Double?
    var sawHeader = false

    for raw in text.split(whereSeparator: \.isNewline) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty { continue }

      let upper = line.uppercased()
      if upper.hasPrefix("#EXTM3U") {
        sawHeader = true
        continue
      }
      if upper.hasPrefix("#EXTINF:") {
        pending = duration(line.dropFirst("#EXTINF:".count))
        continue
      }
      if line.hasPrefix("#") { continue }

      guard let seconds = pending, partNumber(line) == durations.count + 1 else { return nil }
      durations.append(seconds)
      pending = nil
    }

    guard sawHeader, !durations.isEmpty, pending == nil else { return nil }
    return Listing(count: durations.count, seconds: durations.reduce(0, +))
  }

  private static func duration(_ field: Substring) -> Double? {
    let value = field.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
    guard let seconds = Double(value.trimmingCharacters(in: .whitespaces)),
          seconds.isFinite, seconds > 0
    else { return nil }
    return seconds
  }

  /// The `<#####>` in `HIDDEN<quality>-<#####>.ts`, whether the line is a bare
  /// file name, an absolute address or carrying a query string.
  private static func partNumber(_ line: String) -> Int? {
    let path = line.split(separator: "?").first.map(String.init) ?? line
    let name = path.split(separator: "/").last.map(String.init) ?? path
    let lower = name.lowercased()
    guard lower.hasPrefix("hidden"), lower.hasSuffix(".ts") else { return nil }

    let core = name.dropFirst("hidden".count).dropLast(".ts".count)
    let parts = core.split(separator: "-")
    guard parts.count == 2, !parts[0].isEmpty, parts[0].allSatisfy(\.isNumber),
          let number = Int(parts[1])
    else { return nil }
    return number
  }
}
