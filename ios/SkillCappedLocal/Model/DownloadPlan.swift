import Foundation

/// What a lesson is, for the purpose of naming where it lands.
struct DownloadShape: Hashable {
  let kind: String        // "video" | "commentary" | "course"
  let title: String
  let role: String
  let category: String
  let courseTitle: String?
}

/// Where a download lands and what it is called.
///
/// The layout is the one the desktop downloader writes, so a phone download and
/// a desktop download of the same course merge into one course instead of two:
///
///     Videos/<Role>/<Category>/<Title> [uuid] <label>.<ext>
///     Courses/<Role>/<Course>/<Title> [uuid] <label>.<ext>
///     Commentaries/<Role>/<Title> [uuid] <label>.<ext>
///
/// The phone writes `.ts` (the transport stream the CDN served, which is what iOS
/// can play); the desktop writes `.mp4`.
enum DownloadPlan {
  static let segmentSeconds = 10.0
  static let maxSegments = 20_000
  private static let maxSegmentLength = 90
  private static let maxPath = 240
  private static let illegal = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
  private static let reserved: Set<String> = [
    "con", "prn", "aux", "nul",
    "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
    "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
  ]

  /// One path segment that is safe on every platform the desktop build targets —
  /// a library written here has to be readable there, and the other way round.
  static func sanitize(_ input: String, maxLength: Int = maxSegmentLength) -> String {
    let normalized = input.precomposedStringWithCanonicalMapping
    var name = normalized.unicodeScalars
      .map { illegal.contains($0) ? " " : String($0) }
      .joined()
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = name.last, last == "." || last == " " { name.removeLast() }
    if name.isEmpty { name = "untitled" }
    if reserved.contains(name.lowercased()) { name += "_" }
    if name.count > maxLength {
      name = String(name.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
      while let last = name.last, last == "." || last == " " { name.removeLast() }
      if name.isEmpty { name = "untitled" }
    }
    return name
  }

  /// Folder components relative to a library root.
  static func folder(for shape: DownloadShape) -> [String] {
    let role = sanitize(shape.role.isEmpty ? "all" : shape.role)
    switch shape.kind {
    case "commentary":
      return ["Commentaries", role]
    case "course":
      return ["Courses", role, sanitize(shape.title)]
    default:
      if let courseTitle = shape.courseTitle, !courseTitle.isEmpty {
        return ["Courses", role, sanitize(courseTitle)]
      }
      return ["Videos", role, sanitize(shape.category.isEmpty ? "General" : shape.category)]
    }
  }

  /// `Title [uuid] 1080p.mp4` — the uuid and label are what make dedupe and a
  /// later rescan possible.
  static func fileName(title: String, id: String, qualityLabel: String, extension ext: String = "mp4", maxLength: Int = maxSegmentLength) -> String {
    let suffix = " [\(id)] \(qualityLabel).\(ext)"
    let room = max(12, maxLength - suffix.count)
    return sanitize(title, maxLength: room) + suffix
  }

  /// Absolute destination, honouring the same path budget the desktop uses.
  static func destination(root: URL, shape: DownloadShape, id: String, qualityLabel: String, extension ext: String = "mp4") -> URL {
    let components = folder(for: shape)
    let suffixLength = " [\(id)] \(qualityLabel).\(ext)".count
    let folderLength = components.reduce(0) { $0 + $1.count + 1 }
    let room = maxPath - root.path.count - folderLength - suffixLength
    let nameBudget = max(12, min(maxSegmentLength, room))
    var url = root
    for component in components { url.appendPathComponent(component, isDirectory: true) }
    return url.appendingPathComponent(
      fileName(title: shape.title, id: id, qualityLabel: qualityLabel, extension: ext, maxLength: nameBudget),
      isDirectory: false
    )
  }

  /// A duration-derived estimate; only its magnitude matters, the true tail is
  /// found by probing.
  static func expectedSegments(durationSec: Int) -> Int {
    max(1, Int(ceil(Double(max(0, durationSec)) / segmentSeconds)))
  }
}
