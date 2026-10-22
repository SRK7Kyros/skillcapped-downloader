import Foundation

/// One normalised row of the catalogue — the same shape the downloader writes to
/// `.skillcapped/catalog.json`, and what the upstream course dump is flattened
/// into. Tolerant on purpose: a missing or renamed field degrades one row
/// instead of blanking the whole catalogue.
struct CatalogItem: Codable, Hashable, Identifiable {
  let id: String
  let kind: String
  let title: String
  let role: String
  let durationSec: Int
  let date: Date?
  let category: String
  let tags: [String]
  let thumb: String
  let courseTitle: String?
  let lessonIds: [String]
  let videoCount: Int
  let staff: String?
  let champions: String?
  let kda: String?

  var isCourse: Bool { kind == "course" }
  var isCommentary: Bool { kind == "commentary" }

  /// Only an http(s) address is worth handing to an image view.
  var thumbURL: URL? {
    guard let url = URL(string: thumb), let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http" else { return nil }
    return url
  }

  init(
    id: String,
    kind: String,
    title: String,
    role: String = "all",
    durationSec: Int = 0,
    date: Date? = nil,
    category: String = "",
    tags: [String] = [],
    thumb: String = "",
    courseTitle: String? = nil,
    lessonIds: [String] = [],
    videoCount: Int = 0,
    staff: String? = nil,
    champions: String? = nil,
    kda: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.role = role
    self.durationSec = durationSec
    self.date = date
    self.category = category
    self.tags = tags
    self.thumb = thumb
    self.courseTitle = courseTitle
    self.lessonIds = lessonIds
    self.videoCount = videoCount
    self.staff = staff
    self.champions = champions
    self.kda = kda
  }

  private enum CodingKeys: String, CodingKey {
    case id, kind, title, role, durationSec, date, category, tags, thumb, courseTitle, lessonIds, videoCount
    case staff, champions, kda
  }

  init(from decoder: Decoder) throws {
    let box = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? box.decode(String.self, forKey: .id)) ?? ""
    kind = (try? box.decode(String.self, forKey: .kind)) ?? ""
    title = (try? box.decode(String.self, forKey: .title)) ?? ""
    role = (try? box.decode(String.self, forKey: .role)) ?? ""
    durationSec = (try? box.decode(Int.self, forKey: .durationSec)) ?? 0
    if let millis = try? box.decode(Double.self, forKey: .date), millis > 0 {
      date = Date(timeIntervalSince1970: millis / 1000)
    } else if let seconds = try? box.decode(Double.self, forKey: .date), seconds > 0 {
      date = Date(timeIntervalSince1970: seconds)
    } else {
      date = nil
    }
    category = (try? box.decode(String.self, forKey: .category)) ?? ""
    tags = (try? box.decode([String].self, forKey: .tags)) ?? []
    thumb = (try? box.decode(String.self, forKey: .thumb)) ?? ""
    courseTitle = (try? box.decodeIfPresent(String.self, forKey: .courseTitle)) ?? nil
    lessonIds = (try? box.decode([String].self, forKey: .lessonIds)) ?? []
    videoCount = (try? box.decode(Int.self, forKey: .videoCount)) ?? 0
    staff = (try? box.decodeIfPresent(String.self, forKey: .staff)) ?? nil
    champions = (try? box.decodeIfPresent(String.self, forKey: .champions)) ?? nil
    kda = (try? box.decodeIfPresent(String.self, forKey: .kda)) ?? nil
  }

  func encode(to encoder: Encoder) throws {
    var box = encoder.container(keyedBy: CodingKeys.self)
    try box.encode(id, forKey: .id)
    try box.encode(kind, forKey: .kind)
    try box.encode(title, forKey: .title)
    try box.encode(role, forKey: .role)
    try box.encode(durationSec, forKey: .durationSec)
    try box.encode(date.map { $0.timeIntervalSince1970 * 1000 } ?? 0, forKey: .date)
    try box.encode(category, forKey: .category)
    try box.encode(tags, forKey: .tags)
    try box.encode(thumb, forKey: .thumb)
    try box.encodeIfPresent(courseTitle, forKey: .courseTitle)
    try box.encode(lessonIds, forKey: .lessonIds)
    try box.encode(videoCount, forKey: .videoCount)
    try box.encodeIfPresent(staff, forKey: .staff)
    try box.encodeIfPresent(champions, forKey: .champions)
    try box.encodeIfPresent(kda, forKey: .kda)
  }
}

/// Lookup side of the catalogue: item by id, which course a lesson belongs to,
/// and the order a course lists its lessons in.
struct CatalogIndex {
  let byId: [String: CatalogItem]
  let courseByLesson: [String: String]
  let lessonOrder: [String: [String: Int]]
  let courseByTitle: [String: String]
  let generatedAt: Date?

  static let empty = CatalogIndex(items: [], generatedAt: nil)

  var isEmpty: Bool { byId.isEmpty }
  var items: [CatalogItem] { Array(byId.values) }

  init(items: [CatalogItem], generatedAt: Date?) {
    var byId: [String: CatalogItem] = [:]
    var courseByLesson: [String: String] = [:]
    var lessonOrder: [String: [String: Int]] = [:]
    var courseByTitle: [String: String] = [:]

    for item in items { byId[item.id] = item }
    for item in items where item.isCourse {
      courseByTitle[item.title.lowercased()] = item.id
      var order: [String: Int] = [:]
      for (index, lessonId) in item.lessonIds.enumerated() {
        order[lessonId] = index
        courseByLesson[lessonId] = item.id
      }
      lessonOrder[item.id] = order
    }

    self.byId = byId
    self.courseByLesson = courseByLesson
    self.lessonOrder = lessonOrder
    self.courseByTitle = courseByTitle
    self.generatedAt = generatedAt
  }

  func item(_ id: String) -> CatalogItem? { byId[id] }

  func course(_ id: String) -> CatalogItem? {
    guard let item = byId[id], item.isCourse else { return nil }
    return item
  }

  func order(of lessonId: String, in courseId: String) -> Int? {
    lessonOrder[courseId]?[lessonId]
  }

  /// The lessons of a course, in the order the course lists them.
  func lessons(of course: CatalogItem) -> [CatalogItem] {
    course.lessonIds.compactMap { byId[$0] }
  }

  static func decode(_ data: Data) -> CatalogIndex? {
    struct Payload: Decodable {
      let generatedAt: Double?
      let items: [CatalogItem]
    }
    guard let payload = try? JSONDecoder().decode(Payload.self, from: data), !payload.items.isEmpty else { return nil }
    let stamp = payload.generatedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    return CatalogIndex(items: payload.items, generatedAt: stamp)
  }

  /// Reads `<root>/.skillcapped/catalog.json`, the copy the downloader already keeps.
  static func load(root: URL) -> CatalogIndex? {
    let url = root.appendingPathComponent(".skillcapped", isDirectory: true)
      .appendingPathComponent("catalog.json", isDirectory: false)
    guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
    return decode(data)
  }

  /// Both indexes at once, the local copy winning where the two disagree: it was
  /// written beside the files it names.
  static func merged(primary: CatalogIndex, secondary: CatalogIndex) -> CatalogIndex {
    guard !primary.isEmpty else { return secondary }
    guard !secondary.isEmpty else { return primary }
    var items = secondary.byId
    for (id, item) in primary.byId { items[id] = item }
    return CatalogIndex(items: Array(items.values), generatedAt: primary.generatedAt ?? secondary.generatedAt)
  }
}
