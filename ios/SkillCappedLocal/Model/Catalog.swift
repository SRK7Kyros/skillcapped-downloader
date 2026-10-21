import Foundation

/// One entry of the downloader's `.skillcapped/catalog.json`.
struct CatalogItem: Decodable {
  let id: String
  let kind: String
  let title: String
  let role: String
  let durationSec: Int
  let date: Date?
  let category: String
  let tags: [String]
  let courseTitle: String?
  let lessonIds: [String]
  let videoCount: Int

  private enum CodingKeys: String, CodingKey {
    case id, kind, title, role, durationSec, date, category, tags, thumb, courseTitle, lessonIds, videoCount
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
    } else {
      date = nil
    }
    category = (try? box.decode(String.self, forKey: .category)) ?? ""
    tags = (try? box.decode([String].self, forKey: .tags)) ?? []
    courseTitle = (try? box.decodeIfPresent(String.self, forKey: .courseTitle)) ?? nil
    lessonIds = (try? box.decode([String].self, forKey: .lessonIds)) ?? []
    videoCount = (try? box.decode(Int.self, forKey: .videoCount)) ?? 0
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

  init(items: [CatalogItem], generatedAt: Date?) {
    var byId: [String: CatalogItem] = [:]
    var courseByLesson: [String: String] = [:]
    var lessonOrder: [String: [String: Int]] = [:]
    var courseByTitle: [String: String] = [:]

    for item in items { byId[item.id] = item }
    for item in items where item.kind == "course" {
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

  func order(of lessonId: String, in courseId: String) -> Int? {
    lessonOrder[courseId]?[lessonId]
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
}
