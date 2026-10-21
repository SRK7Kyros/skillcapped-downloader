import Foundation

/// Walks a content root the downloader wrote and turns it into courses and
/// loose videos, using `.skillcapped/catalog.json` for titles, durations and
/// the order a course lists its lessons in.
enum LibraryScanner {
  private enum Bucket {
    case course(folder: String, role: String)
    case video(role: String, category: String)
    case commentary(role: String)
  }

  private static let keys: [URLResourceKey] = [
    .isRegularFileKey,
    .fileSizeKey,
    .contentModificationDateKey,
    .isUbiquitousItemKey,
    .ubiquitousItemDownloadingStatusKey,
  ]

  static func scan(root: URL, catalog: CatalogIndex = .empty) -> LibraryScan {
    let manager = FileManager.default
    let rootComponents = root.standardizedFileURL.pathComponents
    let resourceKeys = Set(keys)

    var courseLessons: [String: [Lesson]] = [:]
    var courseMeta: [String: CatalogItem] = [:]
    var courseFolderMeta: [String: (title: String, role: String, date: Date?)] = [:]
    var videos: [Lesson] = []
    var commentaries: [Lesson] = []

    let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: nil)
    while let url = enumerator?.nextObject() as? URL {
      let components = url.standardizedFileURL.pathComponents
      guard components.count > rootComponents.count else { continue }
      let relative = Array(components[rootComponents.count...])
      guard !relative.contains(where: { $0.hasPrefix(".") }) else { continue }
      guard DownloadName.playableExtensions.contains(url.pathExtension.lowercased()) else { continue }

      let values = try? url.resourceValues(forKeys: resourceKeys)
      guard values?.isRegularFile == true else { continue }

      let name = DownloadName.parse(url.lastPathComponent)
      let item = name.id.flatMap { catalog.item($0) }
      let bucket = bucket(for: relative)
      let folderRole = role(of: bucket)
      let catalogTitle = item?.title ?? ""
      let role = (item?.role).flatMap { $0.isEmpty ? nil : $0 } ?? folderRole

      let lesson = Lesson(
        id: relative.joined(separator: "/"),
        url: url,
        title: catalogTitle.isEmpty ? name.title : catalogTitle,
        role: role,
        quality: name.quality,
        seconds: item?.durationSec ?? 0,
        bytes: Int64(values?.fileSize ?? 0),
        modified: values?.contentModificationDate,
        itemId: item?.id,
        needsDownload: needsDownload(values)
      )

      switch bucket {
      case let .course(folder, _):
        let catalogCourseId = name.id.flatMap { catalog.courseByLesson[$0] }
        let catalogCourse = catalogCourseId.flatMap { catalog.item($0) }
        let title = catalogCourse?.title ?? item?.courseTitle ?? folder
        let key = catalogCourseId.map { "catalog:\($0)" } ?? "folder:\(role)|\(title.lowercased())"
        if let catalogCourse { courseMeta[key] = catalogCourse }
        if courseFolderMeta[key] == nil {
          courseFolderMeta[key] = (
            title,
            catalogCourse?.role ?? role,
            catalogCourse?.date ?? lesson.modified
          )
        }
        courseLessons[key, default: []].append(lesson)

      case .video:
        videos.append(lesson)

      case .commentary:
        commentaries.append(lesson)
      }
    }

    var courses: [Course] = []
    for (key, lessons) in courseLessons {
      let meta = courseMeta[key]
      let fallback = courseFolderMeta[key]
      let ordered = lessons.sorted { first, second in
        let firstIndex = orderIndex(first, course: meta, catalog: catalog)
        let secondIndex = orderIndex(second, course: meta, catalog: catalog)
        if firstIndex != secondIndex { return firstIndex < secondIndex }
        return first.title.localizedStandardCompare(second.title) == .orderedAscending
      }
      courses.append(Course(
        id: key,
        title: meta?.title ?? fallback?.title ?? "Untitled course",
        role: meta?.role ?? fallback?.role ?? "",
        category: meta?.category ?? "",
        date: meta?.date ?? fallback?.date,
        lessons: ordered
      ))
    }
    courses.sort { first, second in
      let firstDate = first.date ?? .distantPast
      let secondDate = second.date ?? .distantPast
      if firstDate != secondDate { return firstDate > secondDate }
      return first.title.localizedStandardCompare(second.title) == .orderedAscending
    }

    let sortedCommentaries = commentaries.sorted {
      $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
    let sortedVideos = videos.sorted { first, second in
      let firstDate = first.modified ?? .distantPast
      let secondDate = second.modified ?? .distantPast
      if firstDate != secondDate { return firstDate > secondDate }
      return first.title.localizedStandardCompare(second.title) == .orderedAscending
    }

    let courseBytes = courses.reduce(Int64(0)) { $0 + $1.bytes }
    let videoBytes = sortedVideos.reduce(Int64(0)) { $0 + $1.bytes }
    let commentaryBytes = sortedCommentaries.reduce(Int64(0)) { $0 + $1.bytes }

    return LibraryScan(
      rootName: root.lastPathComponent,
      rootPath: root.path,
      courses: courses,
      videos: sortedVideos,
      commentaries: sortedCommentaries,
      totalBytes: courseBytes + videoBytes + commentaryBytes,
      catalogDate: catalog.generatedAt,
      scannedAt: Date()
    )
  }

  private static func orderIndex(_ lesson: Lesson, course: CatalogItem?, catalog: CatalogIndex) -> Int {
    guard let course, let itemId = lesson.itemId else { return Int.max }
    return catalog.order(of: itemId, in: course.id) ?? Int.max
  }

  private static func needsDownload(_ values: URLResourceValues?) -> Bool {
    guard let values, values.isUbiquitousItem == true else { return false }
    return values.ubiquitousItemDownloadingStatus != .current
  }

  private static func bucket(for relative: [String]) -> Bucket {
    let top = relative.first?.lowercased() ?? ""
    let role = relative.count > 1 ? relative[1] : ""
    switch top {
    case "courses":
      let folder = relative.count > 2 ? relative[2] : "unsorted"
      return .course(folder: folder, role: role)
    case "commentaries":
      return .commentary(role: role)
    case "videos":
      return .video(role: role, category: relative.count > 2 ? relative[2] : "")
    default:
      let parent = relative.count > 1 ? relative[relative.count - 2] : ""
      return .video(role: role, category: top.isEmpty ? parent : top)
    }
  }

  private static func role(of bucket: Bucket) -> String {
    switch bucket {
    case let .course(_, role): return role
    case let .video(role, _): return role
    case let .commentary(role): return role
    }
  }
}
