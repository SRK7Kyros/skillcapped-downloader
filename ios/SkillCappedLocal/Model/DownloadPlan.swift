import Foundation

/// What a lesson is, for the purpose of naming where it lands.
struct DownloadShape: Hashable {
  let kind: String        // "video" | "commentary" | "course"
  let title: String
  let role: String
  let category: String
  let courseTitle: String?
}

/// Where a lesson sits in its collection, and how large that collection is —
/// a course's own lesson order, or the catalogue order within one videos /
/// commentaries folder. `CatalogIndex.fileNumber` is what works it out.
struct FileNumber: Codable, Hashable, Sendable {
  let index: Int
  let total: Int
}

/// Where a download lands and what it is called.
///
/// The layout is the one the desktop downloader writes, so a phone download and
/// a desktop download of the same course merge into one course instead of two:
///
///     Videos/<Role>/<Category>/<NN> - <Title> <label>.<ext>
///     Courses/<Role>/<Course>/<NN> - <Title> <label>.<ext>
///     Commentaries/<Role>/<NN> - <Title> <label>.<ext>
///
/// Nothing else identifies a file on disk — `CatalogIndex.locate` says which
/// lesson a name is. A name written before the number existed keeps its
/// `<Title> [<uuid>] <label>` shape and is still read, because a library is not
/// migrated.
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

  /// `01 - ` — the index padded to the width the collection's size needs, so a
  /// nine-lesson course reads `1 - ` while a twelve-lesson one reads `01 - ` and
  /// both sort in watching order. Mirrors `numberPrefix` in the desktop build.
  static func numberPrefix(_ number: FileNumber?) -> String {
    guard let number else { return "" }
    let width = max(1, String(max(1, number.total)).count)
    let digits = String(number.index)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits + " - "
  }

  /// `<NN> - <Title> 1080p.mp4` — no number when the lesson is in no collection.
  static func fileName(title: String, number: FileNumber?, qualityLabel: String, extension ext: String = "mp4", maxLength: Int = maxSegmentLength) -> String {
    let prefix = numberPrefix(number)
    let suffix = " \(qualityLabel).\(ext)"
    let room = max(12, maxLength - prefix.count - suffix.count)
    return prefix + sanitize(title, maxLength: room) + suffix
  }

  /// Absolute destination, honouring the same path budget the desktop uses.
  static func destination(root: URL, shape: DownloadShape, number: FileNumber?, qualityLabel: String, extension ext: String = "mp4") -> URL {
    let components = folder(for: shape)
    let suffixLength = numberPrefix(number).count + " \(qualityLabel).\(ext)".count
    let folderLength = components.reduce(0) { $0 + $1.count + 1 }
    let room = maxPath - root.path.count - folderLength - suffixLength
    let nameBudget = max(12, min(maxSegmentLength, room))
    var url = root
    for component in components { url.appendPathComponent(component, isDirectory: true) }
    return url.appendingPathComponent(
      fileName(title: shape.title, number: number, qualityLabel: qualityLabel, extension: ext, maxLength: nameBudget),
      isDirectory: false
    )
  }

  /// A duration-derived estimate, used as the starting point for a probe — and
  /// only for a video that publishes no manifest.
  static func expectedSegments(durationSec: Int) -> Int {
    max(1, Int(ceil(Double(max(0, durationSec)) / segmentSeconds)))
  }
}
