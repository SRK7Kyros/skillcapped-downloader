import Foundation

/// One normalised row of the catalogue — the same shape the downloader writes to
/// `.skillcapped/catalog.json`, and what the upstream course dump is flattened
/// into. Tolerant on purpose: a missing or renamed field degrades one row
/// instead of blanking the whole catalogue.
struct CatalogItem: Codable, Hashable, Identifiable, Sendable {
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
  var thumbURL: URL? { WebLink.url(thumb) }

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
/// the order a course lists its lessons in, and the number each lesson carries
/// in its file name.
struct CatalogIndex: Sendable {
  let byId: [String: CatalogItem]
  let courseByLesson: [String: String]
  let lessonOrder: [String: [String: Int]]
  let courseByTitle: [String: String]
  let generatedAt: Date?
  /// Every item, sorted by id — the order the numbering pass walks, so the phone
  /// and the desktop number a catalogue the same way.
  let ordered: [CatalogItem]
  let numbers: [String: FileNumber]
  private let byFolderTitle: [String: String]
  private let byFolder: [String: [String]]

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

    let ordered = byId.values.sorted { CatalogIndex.precedes($0.id, $1.id) }

    var byFolderTitle: [String: String] = [:]
    var byFolder: [String: [String]] = [:]
    for item in ordered where !item.isCourse {
      let folder = CatalogIndex.folder(of: item)
      byFolder[folder, default: []].append(item.id)
      let key = folder + "\u{1}" + CatalogIndex.titleKey(item.title)
      if byFolderTitle[key] == nil { byFolderTitle[key] = item.id }
    }

    self.byId = byId
    self.courseByLesson = courseByLesson
    self.lessonOrder = lessonOrder
    self.courseByTitle = courseByTitle
    self.generatedAt = generatedAt
    self.ordered = ordered
    self.numbers = CatalogIndex.fileNumbers(of: ordered)
    self.byFolderTitle = byFolderTitle
    self.byFolder = byFolder
  }

  func item(_ id: String) -> CatalogItem? { byId[id] }

  /// The number a lesson carries in its file name, or nil when it is in no
  /// collection (a course itself, or a stray pointing at a course's folder).
  func fileNumber(for id: String) -> FileNumber? { numbers[id] }

  /// Turns a file's folder and title back into the lesson it is — the name no
  /// longer carries an id, so this is what identifies a numbered file. A long
  /// title is truncated to the path budget when written, so a name that is a
  /// prefix of one is accepted too; the shortest such match wins, which is the
  /// title a truncation actually came from.
  func locate(folder: String, title: String) -> CatalogItem? {
    let key = CatalogIndex.titleKey(title)
    if let id = byFolderTitle[folder + "\u{1}" + key] { return byId[id] }
    guard key.count >= 12, let candidates = byFolder[folder] else { return nil }
    var best: CatalogItem?
    var bestLength = 0
    for id in candidates {
      guard let item = byId[id] else { continue }
      let candidate = CatalogIndex.titleKey(item.title)
      if candidate.hasPrefix(key), best == nil || candidate.count < bestLength {
        best = item
        bestLength = candidate.count
      }
    }
    return best
  }

  /// The folder a lesson lands in, spelled the way the download does.
  static func folder(of item: CatalogItem) -> String {
    DownloadPlan.folder(for: shape(of: item)).joined(separator: "/")
  }

  static func shape(of item: CatalogItem) -> DownloadShape {
    DownloadShape(
      kind: item.kind,
      title: item.title,
      role: item.role,
      category: item.category,
      courseTitle: item.courseTitle
    )
  }

  private static func titleKey(_ title: String) -> String {
    DownloadPlan.sanitize(title, maxLength: 90).lowercased()
  }

  /// UTF-16 code unit order — exactly what JavaScript's `<` does, so a title two
  /// lessons share orders the same on both surfaces.
  static func precedes(_ first: String, _ second: String) -> Bool {
    first.utf16.lexicographicallyPrecedes(second.utf16)
  }

  private static func seconds(_ item: CatalogItem) -> Double {
    item.date?.timeIntervalSince1970 ?? 0
  }

  /// Newest first, then title, then id — mirrors `compareLessons` in the desktop
  /// build. A course's lessons take the course's own order instead.
  static func compareLessons(_ first: CatalogItem, _ second: CatalogItem) -> Int {
    let firstDate = seconds(first)
    let secondDate = seconds(second)
    if firstDate != secondDate { return secondDate < firstDate ? -1 : 1 }
    let firstTitle = first.title.lowercased()
    let secondTitle = second.title.lowercased()
    if firstTitle != secondTitle { return precedes(firstTitle, secondTitle) ? -1 : 1 }
    if first.id == second.id { return 0 }
    return precedes(first.id, second.id) ? -1 : 1
  }

  private static func fileNumbers(of ordered: [CatalogItem]) -> [String: FileNumber] {
    var numbers: [String: FileNumber] = [:]
    let known = Set(ordered.map { $0.id })

    for course in ordered where course.isCourse {
      let lessons = course.lessonIds
      for (offset, id) in lessons.enumerated() where known.contains(id) && numbers[id] == nil {
        numbers[id] = FileNumber(index: offset + 1, total: lessons.count)
      }
    }

    // A course owns its folder, so a lesson the course does not list takes no
    // number rather than a number that would collide with the course's own.
    let courseFolders = Set(ordered.filter { $0.isCourse }.map { folder(of: $0) })

    var groups: [String: [CatalogItem]] = [:]
    for item in ordered where !item.isCourse && numbers[item.id] == nil {
      let key = folder(of: item)
      if courseFolders.contains(key) { continue }
      groups[key, default: []].append(item)
    }

    for group in groups.values {
      let sorted = group.sorted { compareLessons($0, $1) < 0 }
      for (offset, item) in sorted.enumerated() {
        numbers[item.id] = FileNumber(index: offset + 1, total: sorted.count)
      }
    }

    return numbers
  }

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
    // Sorted because the index is built in item order and its lesson → course
    // map is last-write-wins; a dictionary's order would decide which course
    // owns a lesson the two catalogues disagree about.
    let ordered = items.values.sorted { $0.id < $1.id }
    return CatalogIndex(items: ordered, generatedAt: primary.generatedAt ?? secondary.generatedAt)
  }
}
