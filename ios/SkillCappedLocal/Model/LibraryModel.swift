import Foundation

struct Lesson: Identifiable, Hashable {
  let id: String
  let url: URL
  let title: String
  let role: String
  let quality: String?
  let seconds: Int
  let bytes: Int64
  let modified: Date?
  let itemId: String?
  let needsDownload: Bool
  /// The poster the site prints for this lesson. It matters most for a transport
  /// stream: iOS cannot decode a frame out of one, so without the hosted poster a
  /// lesson downloaded on the phone would only ever have a gradient.
  var thumb: String = ""

  var posterURL: URL? { WebLink.url(thumb) }
}

struct Course: Identifiable, Hashable {
  let id: String
  let title: String
  let role: String
  let category: String
  let date: Date?
  let lessons: [Lesson]
  /// The course card the site prints — portrait, with its title baked into the
  /// top. A local frame is only the stand-in when the catalogue has no poster.
  var thumb: String = ""

  var bytes: Int64 { lessons.reduce(0) { $0 + $1.bytes } }
  var seconds: Int { lessons.reduce(0) { $0 + $1.seconds } }
  var bannerURL: URL? { lessons.first?.url }
  var posterURL: URL? { WebLink.url(thumb) }

  /// What the card draws: the printed poster when the catalogue knows one, and a
  /// frame out of the first lesson otherwise.
  var artURL: URL? { posterURL ?? bannerURL }
}

struct LibraryScan: Equatable {
  let rootName: String
  let rootPath: String
  let courses: [Course]
  let videos: [Lesson]
  let commentaries: [Lesson]
  let totalBytes: Int64
  let catalogDate: Date?
  let scannedAt: Date

  static let empty = LibraryScan(
    rootName: "",
    rootPath: "",
    courses: [],
    videos: [],
    commentaries: [],
    totalBytes: 0,
    catalogDate: nil,
    scannedAt: Date(timeIntervalSince1970: 0)
  )

  var lessonCount: Int {
    courses.reduce(0) { $0 + $1.lessons.count } + videos.count + commentaries.count
  }

  var isEmpty: Bool { courses.isEmpty && videos.isEmpty && commentaries.isEmpty }

  /// Every catalogue id the library already holds, so a remote row can say
  /// "on disk" whether the file came from this phone or from the desktop.
  var onDiskIds: Set<String> {
    var ids: Set<String> = []
    for lesson in videos + commentaries {
      if let id = lesson.itemId { ids.insert(id) }
    }
    for course in courses {
      for lesson in course.lessons {
        if let id = lesson.itemId { ids.insert(id) }
      }
    }
    return ids
  }
}
