import Foundation

/// Small atomic JSON files for the app's own state — progress, the download
/// queue, sources and preferences. One place that knows where they live and how
/// they are written, so a half-written file can never replace a good one.
enum JSONFile {
  static func directory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("SkillCappedLocal", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static func url(_ name: String) -> URL {
    directory().appendingPathComponent(name + ".json", isDirectory: false)
  }

  static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try? decoder.decode(type, from: data)
  }

  static func save<T: Encodable>(_ value: T, to url: URL) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    guard let data = try? encoder.encode(value) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }

  static func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }
}
