import SwiftUI

struct BrowseView: View {
  let scan: LibraryScan

  @EnvironmentObject private var store: LibraryStore
  @EnvironmentObject private var player: PlayerCoordinator

  @State private var query = ""
  @State private var role = ""

  private var roles: [String] {
    var seen: Set<String> = []
    var found: [String] = []
    for course in scan.courses where !course.role.isEmpty {
      if seen.insert(course.role).inserted { found.append(course.role) }
    }
    return found.sorted()
  }

  private var courses: [Course] {
    scan.courses.filter { matches($0.title, $0.role, $0.category) }
  }

  private var videos: [Lesson] {
    scan.videos.filter { matches($0.title, $0.role, "") }
  }

  private var commentaries: [Lesson] {
    scan.commentaries.filter { matches($0.title, $0.role, "") }
  }

  private func matches(_ title: String, _ itemRole: String, _ category: String) -> Bool {
    if !role.isEmpty, itemRole != role { return false }
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    let haystack = (title + " " + itemRole + " " + category).lowercased()
    return trimmed.split(separator: " ").allSatisfy { haystack.contains($0.lowercased()) }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        summary
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
              }
              .buttonStyle(.plain)
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
          player.play(lesson)
        } label: {
          LessonRow(lesson: lesson)
        }
        .buttonStyle(.plain)
        if lesson.id != lessons.last?.id {
          Divider().overlay(Palette.line)
        }
      }
    }
  }
}
