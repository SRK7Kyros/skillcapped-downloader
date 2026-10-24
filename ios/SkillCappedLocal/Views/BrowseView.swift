import SwiftUI

struct BrowseView: View {
  let scan: LibraryScan

  @EnvironmentObject private var store: LibraryStore
  @EnvironmentObject private var player: PlayerCoordinator
  @EnvironmentObject private var progress: ProgressStore
  @EnvironmentObject private var downloads: DownloadManager

  @StateObject private var exporter = LessonExport()

  @State private var query = ""
  @State private var role = ""

  /// Courses this screen has already let go of. The scan is a value from the last
  /// scan, so a deleted course has to leave *this* screen at once.
  @State private var removedCourses: Set<String> = []
  @State private var exportingCourse: Course?
  @State private var deletingCourse: Course?
  @State private var notice: String?

  private var roles: [String] {
    var seen: Set<String> = []
    var found: [String] = []
    for course in scan.courses where !course.role.isEmpty {
      if seen.insert(course.role).inserted { found.append(course.role) }
    }
    return found.sorted()
  }

  private var courses: [Course] {
    scan.courses
      .filter { !removedCourses.contains($0.id) }
      .filter { matches($0.title, $0.role, $0.category) }
  }

  private var videos: [Lesson] {
    scan.videos.filter { matches($0.title, $0.role, "") }
  }

  private var commentaries: [Lesson] {
    scan.commentaries.filter { matches($0.title, $0.role, "") }
  }

  private func matches(_ title: String, _ itemRole: String, _ category: String) -> Bool {
    if !role.isEmpty, itemRole != role { return false }
    return Search.matches(title + " " + itemRole + " " + category, query: query)
  }

  /// Lessons already started and not finished, most recent first.
  private var continueWatching: [Lesson] {
    let all = scan.courses.flatMap(\.lessons) + scan.videos + scan.commentaries
    var byKey: [String: Lesson] = [:]
    for lesson in all { byKey[lesson.progressKey] = lesson }
    return progress.recentKeys(limit: 10).compactMap { byKey[$0] }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        summary
        if !continueWatching.isEmpty { ContinueShelf(lessons: continueWatching) }
        if !roles.isEmpty { roleChips }

        if !courses.isEmpty {
          sectionHeader("Courses", detail: Format.count(courses.count, "course", "courses"))
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 158, maximum: 240), spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
          ) {
            ForEach(courses) { course in
              NavigationLink(value: course) {
                CourseCard(course: course)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .buttonStyle(.plain)
              .contextMenu { courseActions(course) }
            }
          }
        }

        if !videos.isEmpty {
          sectionHeader("Videos", detail: Format.count(videos.count, "video", "videos"))
          lessonList(videos)
        }

        if !commentaries.isEmpty {
          sectionHeader("Commentaries", detail: Format.count(commentaries.count, "recording", "recordings"))
          lessonList(commentaries)
        }

        if courses.isEmpty && videos.isEmpty && commentaries.isEmpty {
          Text("Nothing matches “\(query)”.")
            .font(.subheadline)
            .foregroundStyle(Palette.inkDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 4)
      .padding(.bottom, 36)
    }
    .background(Palette.bg.ignoresSafeArea())
    .searchable(
      text: $query,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search courses and lessons"
    )
    .refreshable { store.rescan() }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let work = exporter.work {
        ExportBanner(work: work) { exporter.cancel() }
      }
    }
    .confirmationDialog(
      exportingCourse.map { "Export all of “\($0.title)”" } ?? "Export",
      isPresented: exportShown,
      titleVisibility: .visible,
      presenting: exportingCourse
    ) { course in
      Button("Convert to MP4 and share") { exporter.share(course.lessons, converting: true) }
      Button("Share the videos as they are") { exporter.share(course.lessons, converting: false) }
      Button("Cancel", role: .cancel) {}
    } message: { course in
      Text(conversionNote(course))
    }
    .alert(
      deletingCourse.map { "Delete all \(Format.count(onThisPhone($0).count, "video", "videos"))?" } ?? "Delete",
      isPresented: deleteShown,
      presenting: deletingCourse
    ) { course in
      Button("Delete", role: .destructive) { delete(course) }
      Button("Cancel", role: .cancel) {}
    } message: { course in
      let freed = Format.bytes(onThisPhone(course).reduce(Int64(0)) { $0 + $1.bytes })
      Text("“\(course.title)” leaves this phone, freeing \(freed). Its videos can be downloaded again from the catalogue.")
    }
    .alert("Could not finish", isPresented: failureShown, presenting: failureText) { _ in
      Button("OK") {}
    } message: { text in
      Text(text)
    }
  }

  // MARK: - A whole course's two actions

  /// A course answers the two questions one lesson does — leave the phone, or go
  /// somewhere else as a file — for every video it holds.
  @ViewBuilder private func courseActions(_ course: Course) -> some View {
    let plan = LessonExportPlan.batch(course.lessons)
    if !plan.isEmpty {
      let count = Format.count(plan.lessons.count, "video", "videos")
      Button {
        export(course, plan: plan)
      } label: {
        Label("Export all \(count)", systemImage: "square.and.arrow.up")
      }
      .tint(Palette.brand)

      Button(role: .destructive) {
        deletingCourse = course
      } label: {
        Label("Delete all \(count)", systemImage: "trash")
      }
      .tint(Palette.danger)
    }
  }

  /// A course of MP4s already opens anywhere, so it goes straight out; one holding
  /// a transport stream asks first, because that answer costs a copy of a lesson.
  private func export(_ course: Course, plan: LessonExportPlan.Batch) {
    guard plan.asksFirst else {
      exporter.share(course.lessons, converting: false)
      return
    }
    exportingCourse = course
  }

  private func conversionNote(_ course: Course) -> String {
    let count = LessonExportPlan.batch(course.lessons).converts.count
    if count == 1 {
      return "One video is a transport stream. An MP4 opens anywhere; shared as it is, that file only plays here."
    }
    return "\(count) of these are transport streams. An MP4 opens anywhere; shared as they are, those files only play here."
  }

  /// Every video of a course that is on this phone, which is every one a delete
  /// can touch — a lesson only in iCloud is a shadow file, not bytes here.
  private func onThisPhone(_ course: Course) -> [Lesson] {
    course.lessons.filter(LessonExportPlan.isOnThisPhone)
  }

  private func delete(_ course: Course) {
    var removed = 0
    var failed: [String] = []
    for lesson in course.lessons where LessonExportPlan.isOnThisPhone(lesson) {
      do {
        try FileManager.default.removeItem(at: lesson.url)
      } catch {
        failed.append(lesson.title)
        continue
      }
      removed += 1
      // The queue entry is forgotten rather than asked to remove a file that is
      // already gone; a lesson that came from the desktop has no entry at all.
      downloads.forget(lesson.id)
      progress.clear(key: lesson.progressKey)
    }

    // A course is its folder, so its card only goes once every video it holds is
    // gone: one still in iCloud is a row the next scan finds again.
    if removed == course.lessons.count {
      withAnimation(.easeInOut(duration: 0.2)) {
        _ = removedCourses.insert(course.id)
      }
    }
    store.rescan()

    if failed.isEmpty {
      notice = nil
    } else if failed.count == 1 {
      notice = "“\(failed[0])” could not be deleted."
    } else {
      notice = "\(failed.count) videos could not be deleted."
    }
  }

  // MARK: - What is asked, and what went wrong

  private var exportShown: Binding<Bool> {
    Binding(get: { exportingCourse != nil }, set: { if !$0 { exportingCourse = nil } })
  }

  private var deleteShown: Binding<Bool> {
    Binding(get: { deletingCourse != nil }, set: { if !$0 { deletingCourse = nil } })
  }

  private var failureText: String? {
    notice ?? exporter.failure
  }

  private var failureShown: Binding<Bool> {
    Binding(
      get: { failureText != nil },
      set: { shown in
        guard !shown else { return }
        notice = nil
        exporter.failure = nil
      }
    )
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(Format.count(scan.lessonCount, "lesson", "lessons") + " on this phone")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Palette.inkDim)
      Text("\(Format.bytes(scan.totalBytes)) · \(Format.count(scan.courses.count, "course", "courses"))"
           + (scan.catalogDate.map { " · catalogue \(Format.date($0) ?? "")" } ?? ""))
        .font(.caption2)
        .foregroundStyle(Palette.inkFaint)
    }
  }

  private var roleChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        chip("All roles", value: "")
        ForEach(roles, id: \.self) { name in
          chip(Format.roleLabel(name), value: name)
        }
      }
      .padding(.vertical, 1)
    }
  }

  private func chip(_ label: String, value: String) -> some View {
    Button {
      role = value
    } label: {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(role == value ? Palette.bg : Palette.inkDim)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(role == value ? Palette.brand : Palette.surface, in: Capsule())
        .overlay {
          Capsule().stroke(role == value ? Color.clear : Palette.line, lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
  }

  private func sectionHeader(_ title: String, detail: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.headline)
        .foregroundStyle(Palette.ink)
      Spacer()
      Text(detail)
        .font(.caption2)
        .foregroundStyle(Palette.inkFaint)
    }
  }

  private func lessonList(_ lessons: [Lesson]) -> some View {
    LazyVStack(spacing: 0) {
      ForEach(lessons) { lesson in
        Button {
          player.play(lesson, in: lessons)
        } label: {
          LessonRow(lesson: lesson, progress: progress.fraction(for: lesson.progressKey))
        }
        .buttonStyle(.plain)
        if lesson.id != lessons.last?.id {
          Divider().overlay(Palette.line)
        }
      }
    }
  }
}
