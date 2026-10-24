import SwiftUI

/// One course on this phone.
///
/// Landscape is the one arrangement where the art can be an anchor rather than a
/// banner: the poster fills the left edge, whole and still, and the course's
/// words and *Play* are pinned above the lessons — the only thing that scrolls.
/// Portrait stacks instead: a poster a third of the width beside the words (never
/// cropped, never the page), then the lessons in the room below. The columns are
/// landscape-only because on a portrait phone a poster column eats the list.
///
/// A lesson row is a file, so it answers to the two things a file can do from
/// here: leave the phone, or go somewhere else as a file. Both are on the row
/// itself — a right swipe, or a long press — because the alternative is a
/// settings screen nobody finds.
struct CourseView: View {
  let course: Course

  @EnvironmentObject private var player: PlayerCoordinator
  @EnvironmentObject private var progress: ProgressStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var store: LibraryStore

  @StateObject private var exporter = LessonExport()

  /// Lessons this screen has already let go of. The course it was handed is a
  /// value from the last scan, so a deleted row has to leave *this* screen at
  /// once, before the rescan that agrees with it exists.
  @State private var removed: Set<String> = []
  @State private var exporting: Lesson?
  @State private var deleting: Lesson?
  @State private var notice: String?

  /// The lessons still here, in the order the course lists them.
  private var visible: [Lesson] {
    course.lessons.filter { !removed.contains($0.id) }
  }

  var body: some View {
    GeometryReader { proxy in
      if CourseLayout.isSideBySide(proxy.size) {
        sideBySide(proxy.size)
      } else {
        stacked(proxy.size)
      }
    }
    .background(Palette.bg.ignoresSafeArea())
    .navigationTitle(course.title)
    .navigationBarTitleDisplayMode(.inline)
    .alert("Delete this video?", isPresented: deleteShown, presenting: deleting) { lesson in
      Button("Delete", role: .destructive) { delete(lesson) }
      Button("Cancel", role: .cancel) {}
    } message: { lesson in
      Text("“\(lesson.title)” leaves this phone, freeing \(Format.bytes(lesson.bytes)). It can be downloaded again from the catalogue.")
    }
  }

  // MARK: - Landscape: poster pinned left, words and lessons on the right

  private func sideBySide(_ size: CGSize) -> some View {
    let side = CourseLayout.posterColumn(size: size, ratio: PosterShape.portrait)
    return HStack(alignment: .top, spacing: 0) {
      // The column is exactly as wide as the art needs to fill the height at its
      // own shape, so the poster is whole — and it never scrolls.
      PosterArt(
        url: course.artURL,
        seed: course.title,
        fallback: PosterShape.portraitArt,
        window: PosterShape.portrait,
        fill: CGSize(width: side, height: size.height),
        targetWidth: 900
      )

      Rectangle()
        .fill(Palette.line)
        .frame(width: 1)

      VStack(spacing: 0) {
        hero(pinned: true)
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, 10)

        Rectangle()
          .fill(Palette.line)
          .frame(height: 1)

        lessons(compact: CourseLayout.lessonsAreTight(width: size.width, side: side))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }

  // MARK: - Portrait: a small poster beside the words, lessons underneath

  private func stacked(_ size: CGSize) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 14) {
        PosterArt(
          url: course.artURL,
          seed: course.title,
          fallback: PosterShape.portraitArt,
          window: PosterShape.portrait,
          width: CourseLayout.heroWidth(for: size.width),
          targetWidth: 420
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Palette.line, lineWidth: 1)
        }

        hero(pinned: false)
      }
      .padding(16)

      Rectangle()
        .fill(Palette.line)
        .frame(height: 1)

      lessons(compact: false)
    }
  }

  // MARK: - Words

  /// Role, title, the numbers and *Play* — the block that stays put while the
  /// lessons move (see `CourseHero` for the two arrangements).
  private func hero(pinned: Bool) -> some View {
    CourseHero(role: course.role, title: course.title, meta: meta, pinned: pinned) {
      playButton(compact: pinned)
    }
  }

  @ViewBuilder private func playButton(compact: Bool) -> some View {
    if let first = visible.first {
      Button {
        player.play(first, in: visible)
      } label: {
        CoursePill(title: "Play", systemImage: "play.fill", compact: compact)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Play \(course.title) from the first lesson")
    }
  }

  private var meta: String {
    var parts = [Format.count(visible.count, "lesson", "lessons")]
    let bytes = visible.reduce(Int64(0)) { $0 + $1.bytes }
    let seconds = visible.reduce(0) { $0 + $1.seconds }
    if bytes > 0 { parts.append(Format.bytes(bytes)) }
    if seconds > 0 { parts.append(Format.clock(seconds)) }
    return parts.joined(separator: " · ")
  }

  // MARK: - The list that scrolls

  /// A list rather than a stack of rows because swipe actions are the platform's
  /// own here: the row, the reveal, the haptics and the VoiceOver actions all
  /// come with `List`, and a hand-rolled gesture would fight the row's own tap.
  private func lessons(compact: Bool) -> some View {
    List {
      ForEach(Array(visible.indices), id: \.self) { index in
        row(visible[index], index: index, compact: compact)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .environment(\.defaultMinListRowHeight, 0)
    .contentMargins(.bottom, 28, for: .scrollContent)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let work = exporter.work {
        banner(work)
      }
    }
    .confirmationDialog(
      exporting.map { "Export “\($0.title)”" } ?? "Export",
      isPresented: exportShown,
      titleVisibility: .visible,
      presenting: exporting
    ) { lesson in
      Button("Convert to MP4 and share") { exporter.remux(lesson) }
      Button("Share the file as it is") { exporter.asIs(lesson) }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("An MP4 opens anywhere. Shared as it is, the file only plays here — a transport stream most players will not open.")
    }
    .alert("Could not finish", isPresented: failureShown, presenting: failureText) { _ in
      Button("OK") {}
    } message: { text in
      Text(text)
    }
  }

  private func row(_ lesson: Lesson, index: Int, compact: Bool) -> some View {
    Button {
      player.play(lesson, in: visible)
    } label: {
      LessonRow(
        lesson: lesson,
        index: index + 1,
        progress: progress.fraction(for: lesson.progressKey),
        compact: compact
      )
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
    .listRowBackground(Palette.bg)
    .listRowSeparator(.hidden)
    .overlay(alignment: .bottom) {
      if lesson.id != visible.last?.id {
        Rectangle()
          .fill(Palette.line)
          .frame(height: 1)
      }
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      actions(for: lesson)
    }
    .contextMenu {
      actions(for: lesson)
    }
  }

  /// The same two things a right swipe offers, so a long press finds them too.
  /// A lesson that is still only in iCloud has no file to move or remove.
  @ViewBuilder private func actions(for lesson: Lesson) -> some View {
    if LessonExportPlan.isOnThisPhone(lesson) {
      Button {
        export(lesson)
      } label: {
        Label("Export", systemImage: "square.and.arrow.up")
      }
      .tint(Palette.brand)

      Button(role: .destructive) {
        deleting = lesson
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  // MARK: - The two actions

  /// A file the system can already hand to anything goes straight to the sheet; a
  /// transport stream asks first, because one answer costs a copy of the lesson.
  private func export(_ lesson: Lesson) {
    guard LessonExportPlan.shape(for: lesson.url) == .remux else {
      exporter.asIs(lesson)
      return
    }
    exporting = lesson
  }

  private func delete(_ lesson: Lesson) {
    do {
      try FileManager.default.removeItem(at: lesson.url)
    } catch {
      notice = "“\(lesson.title)” could not be deleted: \(error.localizedDescription)"
      return
    }
    // The queue entry is forgotten rather than asked to remove the file again,
    // which by now is gone — and a lesson that came from the desktop has no entry
    // at all.
    downloads.forget(lesson.id)
    progress.clear(key: lesson.progressKey)
    withAnimation(.easeInOut(duration: 0.2)) {
      _ = removed.insert(lesson.id)
    }
    store.rescan()
  }

  // MARK: - The export banner

  /// Where the repackaging says how far along it is, and how to stop it.
  private func banner(_ work: LessonExport.Work) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(work.stage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(Palette.ink)
        Spacer(minLength: 8)
        Text(work.fraction, format: .percent.precision(.fractionLength(0)))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(Palette.inkFaint)
        Button("Stop") { exporter.cancel() }
          .font(.caption.weight(.semibold))
          .foregroundStyle(Palette.brand)
      }

      Text(work.title)
        .font(.caption2)
        .foregroundStyle(Palette.inkFaint)
        .lineLimit(1)

      ProgressView(value: min(max(work.fraction, 0), 1))
        .tint(Palette.brand)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.surfaceStrong)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Palette.line)
        .frame(height: 1)
    }
  }

  // MARK: - What is asked, and what went wrong

  private var exportShown: Binding<Bool> {
    Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } })
  }

  private var deleteShown: Binding<Bool> {
    Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
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
}
