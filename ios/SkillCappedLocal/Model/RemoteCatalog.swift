import Foundation

/// The catalogue as the desktop downloader builds it: the upstream course dump,
/// flattened into rows, plus the metadata the site shows beside them.
struct RemoteCatalog: Codable {
  let season: String
  let patch: String
  let generatedAt: Date
  let dumpUrl: String
  let roles: [String]
  let categories: [String]
  let items: [CatalogItem]

  var index: CatalogIndex { CatalogIndex(items: items, generatedAt: generatedAt) }

  func course(_ id: String) -> CatalogItem? { items.first { $0.id == id && $0.isCourse } }

  func item(_ id: String) -> CatalogItem? { items.first { $0.id == id } }

  func lessons(of course: CatalogItem) -> [CatalogItem] {
    let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    return course.lessonIds.compactMap { byId[$0] }
  }

  func items(kind: String) -> [CatalogItem] {
    items.filter { $0.kind == kind }
  }
}

enum CatalogError: LocalizedError {
  case lookup(Int)
  case dump(Int)
  case shape

  var errorDescription: String? {
    switch self {
    case let .lookup(status): return "The content location answered HTTP \(status)."
    case let .dump(status): return "The course dump answered HTTP \(status)."
    case .shape: return "The course dump did not look like a catalogue."
    }
  }
}

/// Fetches the catalogue straight from the site's own public documents — the
/// same two requests the desktop app makes, so the phone needs no server.
///
/// 1. a Firestore document names the current dump (its address is versioned);
/// 2. the dump itself is a 2 MB JSON document of videos, courses and smurfs.
enum CatalogService {
  static let firebaseKey = "AIzaSyAgHWuN2OEx5R827dHlKO9HsOuBwZ017n0"
  static let locationDoc = "https://firestore.googleapis.com/v1/projects/sc-site-a8f24/databases/(default)/documents/content-location/lol-content-location?key=\(firebaseKey)"
  static let roles = ["all", "top", "jungle", "mid", "adc", "support"]
  static let cacheAge: TimeInterval = 30 * 60

  static func cacheURL() -> URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return caches.appendingPathComponent("remote-catalog.json", isDirectory: false)
  }

  /// A cache younger than `maxAge` is served without touching the network; a
  /// failure falls back to the newest cached copy so browse still works offline.
  static func load(force: Bool = false, maxAge: TimeInterval = cacheAge) async throws -> RemoteCatalog {
    let cache = cacheURL()
    if !force, let cached = JSONFile.load(RemoteCatalog.self, from: cache),
       Date().timeIntervalSince(cached.generatedAt) < maxAge {
      return cached
    }
    do {
      let (dump, url) = try await fetchDump()
      let catalog = build(dump: dump, dumpUrl: url)
      JSONFile.save(catalog, to: cache)
      return catalog
    } catch {
      if let cached = JSONFile.load(RemoteCatalog.self, from: cache) { return cached }
      throw error
    }
  }

  static func fetchDump() async throws -> (dump: Dump, url: String) {
    guard let locationURL = URL(string: locationDoc) else { throw CatalogError.shape }
    let location = try await get(locationURL)
    let document = try? JSONSerialization.jsonObject(with: location) as? [String: Any]
    let fields = document?["fields"] as? [String: Any]
    let dumpUrl = (fields?["dumpUrl"] as? [String: Any])?["stringValue"] as? String
    guard let dumpUrl, let url = URL(string: dumpUrl) else { throw CatalogError.shape }

    let data = try await get(url)
    guard let dump = try? JSONDecoder().decode(Dump.self, from: data) else { throw CatalogError.shape }
    return (dump, dumpUrl)
  }

  private static func get(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = 45
    request.setValue("SkillCappedLocal/2.0 (iOS)", forHTTPHeaderField: "User-Agent")
    var lastError: Error = CatalogError.shape
    for attempt in 1...3 {
      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
          lastError = url.absoluteString.contains("firestore")
            ? CatalogError.lookup(http.statusCode)
            : CatalogError.dump(http.statusCode)
        } else {
          return data
        }
      } catch {
        lastError = error
      }
      if attempt < 3 {
        try? await Task.sleep(for: .milliseconds(400 * attempt))
      }
    }
    throw lastError
  }

  // MARK: - Flattening

  /// Course titles carry a `{role}` token the site substitutes when it renders.
  static func displayTitle(_ raw: String) -> String {
    let labels = ["all": "All Roles", "top": "Top", "jungle": "Jungle", "mid": "Mid", "adc": "ADC", "support": "Support"]
    var title = raw
    for (token, label) in labels {
      title = title.replacingOccurrences(of: "{\(token)}", with: "(\(label))", options: .caseInsensitive)
    }
    return title
  }

  static func build(dump: Dump, dumpUrl: String) -> RemoteCatalog {
    let tagName = { (id: Int) -> String in
      guard id >= 0, id < dump.tagInfo.count else { return "" }
      return dump.tagInfo[id].name
    }

    var courseOfVideo: [String: String] = [:]
    var lessonIdsByTitle: [String: [String]] = [:]
    for (rawTitle, entry) in dump.videosToCourses {
      let title = displayTitle(rawTitle)
      let ids = entry.chapters.flatMap { $0.vids.map(\.uuid) }.filter { !$0.isEmpty }
      lessonIdsByTitle[title] = ids
      for id in ids where courseOfVideo[id] == nil { courseOfVideo[id] = title }
    }

    var items: [CatalogItem] = []

    for video in dump.videos where !video.uuid.isEmpty {
      let category = tagName(video.tId)
      items.append(CatalogItem(
        id: video.uuid,
        kind: "video",
        title: video.title.isEmpty ? video.uuid : video.title,
        role: video.role.isEmpty ? "all" : video.role,
        durationSec: video.durSec,
        date: video.rDate > 0 ? Date(timeIntervalSince1970: video.rDate / 1000) : nil,
        category: category,
        tags: [category, video.role].filter { !$0.isEmpty },
        thumb: video.tSS,
        courseTitle: courseOfVideo[video.uuid]
      ))
    }

    for commentary in dump.commentaries where !commentary.uuid.isEmpty {
      let category = tagName(commentary.tId)
      let title = commentary.staff.isEmpty
        ? "Commentary \(commentary.uuid)"
        : "\(commentary.staff) — \(commentary.yourChampion.isEmpty ? "Smurf" : commentary.yourChampion)"
      items.append(CatalogItem(
        id: commentary.uuid,
        kind: "commentary",
        title: title,
        role: commentary.role.isEmpty ? "all" : commentary.role,
        durationSec: commentary.durSec,
        date: commentary.rDate > 0 ? Date(timeIntervalSince1970: commentary.rDate / 1000) : nil,
        category: category,
        tags: [category, commentary.role, commentary.staff, commentary.yourChampion].filter { !$0.isEmpty },
        thumb: commentary.tSS,
        staff: commentary.staff.isEmpty ? nil : commentary.staff,
        champions: [commentary.yourChampion, commentary.theirChampion].filter { !$0.isEmpty }.joined(separator: " vs "),
        kda: "\(commentary.k)/\(commentary.d)/\(commentary.a)"
      ))
    }

    for course in dump.courses where !course.uuid.isEmpty {
      let title = displayTitle(course.title.isEmpty ? course.uuid : course.title)
      let lessonIds = lessonIdsByTitle[title] ?? []
      let thumb = [course.courseImage3, course.courseImage2, course.courseImage].first { !$0.isEmpty } ?? ""
      items.append(CatalogItem(
        id: course.uuid,
        kind: "course",
        title: title,
        role: course.role.isEmpty ? "all" : course.role,
        date: course.rDate > 0 ? Date(timeIntervalSince1970: course.rDate / 1000) : nil,
        category: course.tags.last ?? "",
        tags: course.tags,
        thumb: thumb,
        lessonIds: lessonIds,
        videoCount: lessonIds.count
      ))
    }

    items.sort { first, second in
      (first.date ?? .distantPast) > (second.date ?? .distantPast)
    }

    let categories = Array(Set(items.flatMap(\.tags).filter { !$0.isEmpty })).sorted()

    return RemoteCatalog(
      season: dump.seasonLabel,
      patch: dump.patch.patchVal,
      generatedAt: Date(),
      dumpUrl: dumpUrl,
      roles: roles,
      categories: categories,
      items: items
    )
  }
}

// MARK: - The upstream dump

/// Shapes of the upstream course dump, parsed tolerantly: it is a third-party
/// document with no version field, so a renamed or missing field must degrade
/// one record instead of blanking the catalogue.
struct Dump: Decodable {
  struct Patch: Decodable {
    let patchVal: String
    init(patchVal: String = "") { self.patchVal = patchVal }
    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: CodingKeys.self)
      patchVal = (try? box.decode(String.self, forKey: .patchVal)) ?? ""
    }
    private enum CodingKeys: String, CodingKey { case patchVal }
  }

  struct Tag: Decodable {
    let name: String
    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: CodingKeys.self)
      name = (try? box.decode(String.self, forKey: .name)) ?? ""
    }
    private enum CodingKeys: String, CodingKey { case name }
  }

  struct Video: Decodable {
    let uuid: String
    let title: String
    let role: String
    let tId: Int
    let durSec: Int
    let rDate: Double
    let tSS: String

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: CodingKeys.self)
      uuid = (try? box.decode(String.self, forKey: .uuid)) ?? ""
      title = (try? box.decode(String.self, forKey: .title)) ?? ""
      role = (try? box.decode(String.self, forKey: .role)) ?? "all"
      tId = (try? box.decode(Int.self, forKey: .tId)) ?? 0
      durSec = (try? box.decode(Int.self, forKey: .durSec)) ?? 0
      rDate = (try? box.decode(Double.self, forKey: .rDate)) ?? 0
      tSS = (try? box.decode(String.self, forKey: .tSS)) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case uuid, title, role, tId, durSec, rDate, tSS }
  }

  struct Commentary: Decodable {
    let uuid: String
    let role: String
    let tId: Int
    let durSec: Int
    let rDate: Double
    let tSS: String
    let staff: String
    let yourChampion: String
    let theirChampion: String
    let k: Int
    let d: Int
    let a: Int

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: CodingKeys.self)
      uuid = (try? box.decode(String.self, forKey: .uuid)) ?? ""
      role = (try? box.decode(String.self, forKey: .role)) ?? "all"
      tId = (try? box.decode(Int.self, forKey: .tId)) ?? 0
      durSec = (try? box.decode(Int.self, forKey: .durSec)) ?? 0
      rDate = (try? box.decode(Double.self, forKey: .rDate)) ?? 0
      tSS = (try? box.decode(String.self, forKey: .tSS)) ?? ""
      staff = (try? box.decode(String.self, forKey: .staff)) ?? ""
      yourChampion = (try? box.decode(String.self, forKey: .yourChampion)) ?? ""
      theirChampion = (try? box.decode(String.self, forKey: .theirChampion)) ?? ""
      k = (try? box.decode(Int.self, forKey: .k)) ?? 0
      d = (try? box.decode(Int.self, forKey: .d)) ?? 0
      a = (try? box.decode(Int.self, forKey: .a)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
      case uuid, role, tId, durSec, rDate, tSS, staff, yourChampion, theirChampion, k, d, a
    }
  }

  struct Course: Decodable {
    let uuid: String
    let title: String
    let role: String
    let rDate: Double
    let tags: [String]
    let courseImage: String
    let courseImage2: String
    let courseImage3: String

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: CodingKeys.self)
      uuid = (try? box.decode(String.self, forKey: .uuid)) ?? ""
      title = (try? box.decode(String.self, forKey: .title)) ?? ""
      role = (try? box.decode(String.self, forKey: .role)) ?? "all"
      rDate = (try? box.decode(Double.self, forKey: .rDate)) ?? 0
      tags = (try? box.decode([String].self, forKey: .tags)) ?? []
      courseImage = (try? box.decode(String.self, forKey: .courseImage)) ?? ""
      courseImage2 = (try? box.decode(String.self, forKey: .courseImage2)) ?? ""
      courseImage3 = (try? box.decode(String.self, forKey: .courseImage3)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
      case uuid, title, role, rDate, tags, courseImage, courseImage2, courseImage3
    }
  }

  struct CourseEntry: Decodable {
    struct Chapter: Decodable {
      struct Vid: Decodable {
        let uuid: String
        init(from decoder: Decoder) throws {
          let box = try decoder.container(keyedBy: CodingKeys.self)
          uuid = (try? box.decode(String.self, forKey: .uuid)) ?? ""
        }
        private enum CodingKeys: String, CodingKey { case uuid }
      }

      let title: String
      let vids: [Vid]

      init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? box.decode(String.self, forKey: .title)) ?? ""
        vids = (try? box.decode([Vid].self, forKey: .vids)) ?? []
      }

      private enum CodingKeys: String, CodingKey { case title, vids }
    }

    let chapters: [Chapter]

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: CodingKeys.self)
      chapters = (try? box.decode([Chapter].self, forKey: .chapters)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case chapters }
  }

  let seasonLabel: String
  let patch: Patch
  let tagInfo: [Tag]
  let videos: [Video]
  let commentaries: [Commentary]
  let courses: [Course]
  let videosToCourses: [String: CourseEntry]

  init(from decoder: Decoder) throws {
    let box = try decoder.container(keyedBy: CodingKeys.self)
    seasonLabel = (try? box.decode(String.self, forKey: .seasonLabel)) ?? ""
    patch = (try? box.decode(Patch.self, forKey: .patch)) ?? Patch()
    tagInfo = (try? box.decode([Tag].self, forKey: .tagInfo)) ?? []
    videos = (try? box.decode([Video].self, forKey: .videos)) ?? []
    commentaries = (try? box.decode([Commentary].self, forKey: .commentaries)) ?? []
    courses = (try? box.decode([Course].self, forKey: .courses)) ?? []
    videosToCourses = (try? box.decode([String: CourseEntry].self, forKey: .videosToCourses)) ?? [:]
  }

  private enum CodingKeys: String, CodingKey {
    case seasonLabel, patch, tagInfo, videos, commentaries, courses, videosToCourses
  }
}
