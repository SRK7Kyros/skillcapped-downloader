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
    // Which catalogue courses claim a folder's lessons, and the first item seen
    // for it. A folder is only described by a catalogue that agrees with itself.
    var courseClaims: [String: Set<String>] = [:]
    var courseCandidates: [String: CatalogItem] = [:]
    var courseFolderMeta: [String: (title: String, role: String, date: Date?)] = [:]
    var videos: [Lesson] = []
    var commentaries: [Lesson] = []

    let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: nil)
    while let url = enumerator?.nextObject() as? URL {
      let components = url.standardizedFileURL.pathComponents
      guard components.count > rootComponents.count else { continue }
      var relative = Array(components[rootComponents.count...])
      // iCloud Drive can hand a lesson over as its hidden shadow file
      // (".Name [id] 1080p.mp4.icloud") while the bytes are still in the cloud.
      // The lesson exists, so it is listed at the name it restores to and the
      // bytes are asked for when it is played — never at scan time.
      let placeholder = placeholderSibling(of: url)
      if let placeholder {
        relative[relative.count - 1] = placeholder.lastPathComponent
      }
      guard !relative.contains(where: { $0.hasPrefix(".") }) else { continue }
      let lessonURL = placeholder ?? url
      guard DownloadName.playableExtensions.contains(lessonURL.pathExtension.lowercased()) else { continue }

      let values = try? url.resourceValues(forKeys: resourceKeys)
      guard values?.isRegularFile == true else { continue }

      let name = DownloadName.parse(lessonURL.lastPathComponent)
      let item = name.id.flatMap { catalog.item($0) }
      let bucket = bucket(for: relative)
      let folderRole = role(of: bucket)
      let catalogTitle = item?.title ?? ""
      let role = (item?.role).flatMap { $0.isEmpty ? nil : $0 } ?? folderRole

      let lesson = Lesson(
        id: relative.joined(separator: "/"),
        url: lessonURL,
        title: catalogTitle.isEmpty ? name.title : catalogTitle,
        role: role,
        quality: name.quality,
        seconds: item?.durationSec ?? 0,
        bytes: placeholder == nil ? Int64(values?.fileSize ?? 0) : 0,
        modified: values?.contentModificationDate,
        itemId: item?.id ?? name.id,
        needsDownload: placeholder != nil || needsDownload(values),
        thumb: item?.thumb ?? ""
      )

      switch bucket {
      case let .course(folder, _):
        // A course on disk is its folder: this app and the desktop both write
        // one folder per course. Keying on a catalogue id instead split one
        // folder into two cards with the same title whenever the catalogue
        // disagreed about which course owns a lesson — the desktop's own
        // catalog.json and the site can name different courses for one id.
        let key = "folder:\(role)|\(folder.lowercased())"
        let catalogCourse = name.id
          .flatMap { catalog.courseByLesson[$0] }
          .flatMap { catalog.item($0) }
        if let catalogCourse {
          courseClaims[key, default: []].insert(catalogCourse.id)
          if courseCandidates[key] == nil { courseCandidates[key] = catalogCourse }
        }
        if courseFolderMeta[key] == nil {
          let courseTitle = item?.courseTitle ?? ""
          courseFolderMeta[key] = (
            courseTitle.isEmpty ? folder : courseTitle,
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
      // Only a single claimant describes the folder; two courses naming one
      // folder's lessons means the catalogue cannot be trusted with its title.
      let meta = courseClaims[key]?.count == 1 ? courseCandidates[key] : nil
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
        lessons: ordered,
        thumb: meta?.thumb ?? ""
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

  /// `.Name [id] 1080p.mp4.icloud` → `Name [id] 1080p.mp4`, the path iCloud
  /// restores the lesson to once its bytes land. Every other name is nil, and so
  /// is a shadow whose visible copy is already on disk — that lesson is listed
  /// once, from the real file.
  private static func placeholderSibling(of url: URL) -> URL? {
    let name = url.lastPathComponent
    guard name.hasPrefix("."), url.pathExtension.lowercased() == "icloud" else { return nil }
    let visible = String(name.dropFirst().dropLast(".icloud".count))
    guard !visible.isEmpty else { return nil }
    let sibling = url.deletingLastPathComponent().appendingPathComponent(visible)
    guard !FileManager.default.fileExists(atPath: sibling.path) else { return nil }
    return sibling
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
