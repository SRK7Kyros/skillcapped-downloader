import SwiftUI

/// One lesson as the course page draws it.
///
/// The library and the catalogue describe a lesson from opposite ends: the
/// library starts at a file and may know what the catalogue says about it, while
/// the catalogue starts at the site's row and may have a file behind it. This is
/// what both are turned into, so the page has exactly one thing to draw — and a
/// value is simply absent when the surface that opened the page cannot know it
/// (a catalogue lesson that is not on this phone has no quality and no size).
struct CourseLesson: Identifiable {
  /// The catalogue id when there is one, else the file's own id — the same key
  /// the progress store, the queue and the player already use.
  let id: String
  let title: String
  /// The number the row prints, 1-based; `nil` prints none (the library's flat
  /// video lists are not a course, so they number nothing).
  let index: Int?
  /// The file on this phone, when there is one. Its presence is what makes a row
  /// playable, and what the row's accessory and its file actions read.
  let local: Lesson?
  /// A frame out of the file, when the file is here.
  let still: URL?
  /// The poster the site prints — the only art a transport stream can show, and
  /// the whole art of a lesson that is still remote.
  let remote: URL?
  let seconds: Int
  /// Only a file has a size; a lesson the catalogue lists alone does not.
  let bytes: Int64?
  let quality: String?
  /// What the row is doing while this phone has not got it.
  let state: RowState
  /// How much of it has been watched, when there is a file to resume.
  let progress: Double?
  /// The catalogue's own row, so the hero can fetch what is missing.
  let item: CatalogItem?
  /// A line the surface can add under the title when it knows something a file
  /// cannot say — a video's staff, champion or KDA, straight from the site. The
  /// row prints it in the same place on both surfaces; it is simply empty where
  /// there is nothing to say.
  let note: String?

  /// A lesson that is a shadow in iCloud — here by name, not yet by bytes.
  var needsDownload: Bool { local?.needsDownload ?? false }
}

extension CourseLesson {
  /// A row for a file this phone holds. `LessonRow` and the course page both
  /// build their rows here, so a lesson cannot be drawn two ways.
  static func here(_ lesson: Lesson, index: Int? = nil, progress: Double? = nil) -> CourseLesson {
    CourseLesson(
      id: lesson.id,
      title: lesson.title,
      index: index,
      local: lesson,
      still: lesson.url,
      remote: lesson.posterURL,
      seconds: lesson.seconds,
      bytes: lesson.bytes,
      quality: lesson.quality,
      state: .onDisk,
      progress: progress,
      item: nil,
      note: nil
    )
  }

  /// A catalogue row standing on its own — a video or a commentary in Discover's
  /// lists, where there is no course to number it and nothing on this phone yet.
  static func catalogue(_ item: CatalogItem, state: RowState) -> CourseLesson {
    CourseLesson(
      id: item.id,
      title: item.title,
      index: nil,
      local: nil,
      still: nil,
      remote: item.thumbURL,
      seconds: item.durationSec,
      bytes: nil,
      quality: nil,
      state: state,
      progress: nil,
      item: item,
      note: Self.note(for: item)
    )
  }

  /// What the site says about the video itself, joined the way a caption reads —
  /// the only one of these lines a file on disk cannot answer.
  static func note(for item: CatalogItem) -> String? {
    let parts = [item.staff, item.champions, item.kda, item.category]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

extension Array where Element == CourseLesson {
  /// The one numbers line both surfaces print, in one order: how many lessons,
  /// how many of them are here (only when that is not all of them), what they
  /// weigh on this phone, and how long they run.
  ///
  /// Every part is optional on purpose — a course whose lessons are all still in
  /// the catalogue has a count and a length and nothing else — so the same
  /// formula prints on the library's page and on Discover's, and a value appears
  /// in the same place on both as soon as it exists.
  var courseMeta: String {
    guard !isEmpty else { return "No published lessons" }

    var parts = [Format.count(count, "lesson", "lessons")]
    let here = reduce(0) { $0 + ($1.local == nil ? 0 : 1) }
    if here > 0, here < count { parts.append("\(here) on disk") }
    let bytes = reduce(Int64(0)) { $0 + ($1.local?.bytes ?? 0) }
    if bytes > 0 { parts.append(Format.bytes(bytes)) }
    let seconds = reduce(0) { $0 + max($1.seconds, 0) }
    if seconds > 0 { parts.append(Format.clock(seconds)) }
    return parts.joined(separator: " · ")
  }
}

/// Everything a course page draws, whichever surface opened it.
///
/// The library builds it from a `Course` (every row is a file) and Discover from
/// the catalogue's `CatalogItem` joined with the scan (some rows are files). The
/// page cannot tell the two apart, which is the point: one page, one geometry,
/// one set of rows, one place each value can appear in.
struct CoursePageModel {
  let role: String
  let title: String
  let art: URL?
  let seed: String
  let lessons: [CourseLesson]
}

extension CoursePageModel {
  /// A course this phone holds. Every lesson is a file, so every row plays and
  /// the page has nothing to download.
  static func library(_ course: Course, fraction: (String) -> Double?) -> CoursePageModel {
    CoursePageModel(
      role: course.role,
      title: course.title,
      art: course.artURL,
      seed: course.title,
      lessons: course.lessons.enumerated().map { index, lesson in
        .here(lesson, index: index + 1, progress: fraction(lesson.progressKey))
      }
    )
  }

  /// A course as the catalogue lists it, with whatever this phone already holds
  /// filled in row by row: a lesson with a file gets its size, its quality, its
  /// frame and a *Play*; one without stays a catalogue row with a download.
  ///
  /// `state` is the queue's answer for an id (`CatalogState.of`), taken as a
  /// closure so this join stays pure and can be reasoned about without a queue.
  @MainActor
  static func catalogue(
    _ course: CatalogItem,
    lessons items: [CatalogItem],
    scan: LibraryScan?,
    state: @MainActor (String) -> RowState,
    progress: @MainActor (String) -> Double?
  ) -> CoursePageModel {
    let held = scan?.lessonsByItemId ?? [:]
    return CoursePageModel(
      role: course.role,
      title: course.title,
      art: course.thumbURL,
      seed: course.title,
      lessons: items.enumerated().map { index, item in
        let file = held[item.id]
        // The catalogue's length stands in until a file can say its own.
        let seconds = (file?.seconds ?? 0) > 0 ? (file?.seconds ?? 0) : item.durationSec
        return CourseLesson(
          id: item.id,
          title: file?.title ?? item.title,
          index: index + 1,
          local: file,
          still: file?.url,
          remote: file?.posterURL ?? item.thumbURL,
          seconds: seconds,
          bytes: file?.bytes,
          quality: file?.quality,
          state: file == nil ? state(item.id) : .onDisk,
          progress: file.flatMap { progress($0.progressKey) },
          item: item,
          // A course row says what a lesson is by its title and its number; the
          // site's staff/champion caption belongs to the flat video lists, where
          // there is no course to give the row a context. Filling it here would
          // put a line on the catalogue's page that the library's cannot have.
          note: nil
        )
      }
    )
  }
}

/// One course, drawn once.
///
/// Landscape is the one arrangement where the art can be an anchor rather than a
/// banner: the poster fills the left edge, whole and still, and the course's
/// words and its pills are pinned above the lessons — the only thing that
/// scrolls. Portrait stacks instead: a poster a third of the width beside the
/// words (never cropped, never the page), then the lessons in the room below.
/// The columns are landscape-only because on a portrait phone a poster column
/// eats the list.
///
/// The library's course and the catalogue's course are this page — not two pages
/// that agree, one page with two sources. A lesson row is a file, so it answers
/// to the two things a file can do from here: leave the phone, or go somewhere
/// else as a file. Both are on the row itself — a left swipe, or a long press —
/// and a lesson this phone has not got does not offer them, because there is no
/// file to move or remove.
struct CoursePage: View {
  let page: CoursePageModel

  @EnvironmentObject private var player: PlayerCoordinator
  @EnvironmentObject private var progress: ProgressStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var store: LibraryStore

  @StateObject private var exporter = LessonExport()

  /// Rows this screen has already let go of. The page was handed a value from
  /// the last scan, so a deleted row has to leave *this* screen at once, before
  /// the rescan that agrees with it exists.
  @State private var removed: Set<String> = []
  @State private var exporting: CourseLesson?
  @State private var deleting: CourseLesson?
  @State private var notice: String?

  /// The lessons still here, in the order the page lists them.
  private var rows: [CourseLesson] {
    page.lessons.filter { !removed.contains($0.id) }
  }

  /// The rows this phone can play, in page order — the queue Play hands over.
  /// An iCloud shadow counts: the player fetches it and then plays it.
  private var playable: [Lesson] {
    rows.compactMap(\.local)
  }

  /// What the catalogue lists that this phone has not got and is not already
  /// fetching: the lessons the hero's download is for.
  private var missing: [CatalogItem] {
    rows.filter { $0.local == nil && $0.state == .remote }.compactMap(\.item)
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
    .navigationTitle(page.title)
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: - Landscape: poster pinned left, words and lessons on the right

  private func sideBySide(_ size: CGSize) -> some View {
    let side = CourseLayout.posterColumn(size: size, ratio: PosterShape.portrait)
    return HStack(alignment: .top, spacing: 0) {
      // The column is exactly as wide as the art needs to fill the height at its
      // own shape, so the poster is whole — and it never scrolls.
      PosterArt(
        url: page.art,
        seed: page.seed,
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
          url: page.art,
          seed: page.seed,
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

  /// Role, title, the numbers and the pills — the block that stays put while the
  /// lessons move (see `CourseHero` for the two arrangements).
  private func hero(pinned: Bool) -> some View {
    CourseHero(role: page.role, title: page.title, meta: rows.courseMeta, pinned: pinned) {
      heroActions(compact: pinned)
    }
  }

  /// Two things a course can offer, in the order a thumb expects: *Play* when
  /// any lesson is here, and the download for whatever is not. A library course
  /// has nothing missing, so it only ever shows Play — and a catalogue course
  /// that nothing has come down for shows only Download. The same rule, so the
  /// two surfaces cannot disagree about which pill a course has earned.
  @ViewBuilder private func heroActions(compact: Bool) -> some View {
    HStack(spacing: 8) {
      if let first = playable.first {
        Button {
          player.play(first, in: playable)
        } label: {
          CoursePill(title: "Play", systemImage: "play.fill", compact: compact)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(page.title) from the first lesson")
      }

      if !missing.isEmpty {
        Button {
          downloadMissing()
        } label: {
          CoursePill(title: "Download", systemImage: "arrow.down.circle.fill", compact: compact)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Download the missing lessons of \(page.title)")
      }
    }
  }

  // MARK: - The list that scrolls

  /// A list rather than a stack of rows because swipe actions are the platform's
  /// own here: the row, the reveal, the haptics and the VoiceOver actions all
  /// come with `List`, and a hand-rolled gesture would fight the row's own tap.
  private func lessons(compact: Bool) -> some View {
    List {
      ForEach(rows) { row in
        lessonRow(row, compact: compact)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .environment(\.defaultMinListRowHeight, 0)
    .contentMargins(.bottom, 28, for: .scrollContent)
    .overlay {
      if rows.isEmpty {
        emptyState
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let work = exporter.work {
        ExportBanner(work: work) { exporter.cancel() }
      }
    }
    .confirmationDialog(
      exporting.map { "Export “\($0.title)”" } ?? "Export",
      isPresented: exportShown,
      titleVisibility: .visible,
      presenting: exporting
    ) { row in
      if let file = row.local {
        Button("Convert to MP4 and share") { exporter.remux(file) }
        Button("Share the file as it is") { exporter.asIs(file) }
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("An MP4 opens anywhere. Shared as it is, the file only plays here — a transport stream most players will not open.")
    }
    .alert("Delete this video?", isPresented: deleteShown, presenting: deleting) { row in
      Button("Delete", role: .destructive) { delete(row) }
      Button("Cancel", role: .cancel) {}
    } message: { row in
      Text("“\(row.title)” leaves this phone, freeing \(Format.bytes(row.bytes ?? 0)). It can be downloaded again from the catalogue.")
    }
    .alert("Could not finish", isPresented: failureShown, presenting: failureText) { _ in
      Button("OK") {}
    } message: { text in
      Text(text)
    }
  }

  /// A catalogue course can list nothing the phone has a poster or a lesson for;
  /// a library course always holds at least the file it was built from.
  private var emptyState: some View {
    Text("This course has no published lessons in the catalogue — the site lists it but not its videos.")
      .font(.footnote)
      .foregroundStyle(Palette.inkDim)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(16)
  }

  private func lessonRow(_ row: CourseLesson, compact: Bool) -> some View {
    Button {
      act(on: row)
    } label: {
      CourseLessonRow(lesson: row, compact: compact)
    }
    .buttonStyle(.plain)
    .disabled(row.state.isBusy)
    .accessibilityIdentifier("course.lesson")
    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    .listRowBackground(Palette.bg)
    .listRowSeparator(.hidden)
    .overlay(alignment: .bottom) {
      if row.id != rows.last?.id {
        Rectangle()
          .fill(Palette.line)
          .frame(height: 1)
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      actions(for: row)
    }
    .contextMenu {
      actions(for: row)
    }
  }

  /// The same two things a left swipe offers, so a long press finds them too.
  /// A lesson that is still only in iCloud has no file to move or remove, and a
  /// lesson this phone has not got is not a file at all.
  @ViewBuilder private func actions(for row: CourseLesson) -> some View {
    if let file = row.local, LessonExportPlan.isOnThisPhone(file) {
      Button {
        export(row)
      } label: {
        Label("Export", systemImage: "square.and.arrow.up")
      }
      .tint(Palette.brand)

      Button(role: .destructive) {
        deleting = row
      } label: {
        Label("Delete", systemImage: "trash")
      }
      .tint(Palette.danger)
    }
  }

  // MARK: - Tapping a row

  /// A row that is here plays; a row that is not is fetched. One rule, so a
  /// catalogue row that has been downloaded behaves exactly like a library row.
  /// The queue itself decides what to skip: a lesson it is already fetching or
  /// already has is left alone, and one that failed is picked up again.
  private func act(on row: CourseLesson) {
    if let file = row.local {
      player.play(file, in: playable)
      return
    }
    guard let item = row.item else { return }
    downloads.enqueue([item.downloadRequest(courseTitle: page.title)], quality: nil)
  }

  private func downloadMissing() {
    guard !missing.isEmpty else { return }
    downloads.enqueue(missing.map { $0.downloadRequest(courseTitle: page.title) }, quality: nil)
  }

  // MARK: - The two file actions

  /// A file the system can already hand to anything goes straight to the sheet; a
  /// transport stream asks first, because one answer costs a copy of the lesson.
  private func export(_ row: CourseLesson) {
    guard let file = row.local else { return }
    guard LessonExportPlan.shape(for: file.url) == .remux else {
      exporter.asIs(file)
      return
    }
    exporting = row
  }

  private func delete(_ row: CourseLesson) {
    guard let file = row.local else { return }
    do {
      try FileManager.default.removeItem(at: file.url)
    } catch {
      notice = "“\(row.title)” could not be deleted: \(error.localizedDescription)"
      return
    }
    // The queue entry is forgotten rather than asked to remove the file again,
    // which by now is gone — and a lesson that came from the desktop has no entry
    // at all.
    downloads.forget(file.id)
    progress.clear(key: file.progressKey)
    withAnimation(.easeInOut(duration: 0.2)) {
      _ = removed.insert(row.id)
    }
    store.rescan()
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

/// One lesson row, in the one geometry every course page and the library's flat
/// lists share. What is under the title is what both surfaces can prove — how
/// long it runs, and how big the file is once there is a file — so nothing has
/// to be moved around when a lesson arrives.
struct CourseLessonRow: View {
  let lesson: CourseLesson
  /// A narrow column — the right-hand half of a course page on a phone — where a
  /// full-width still would leave no room for the words.
  var compact = false

  private var stillWidth: CGFloat { compact ? 82 : 104 }

  var body: some View {
    HStack(spacing: compact ? 10 : 12) {
      ZStack(alignment: .bottomTrailing) {
        PosterArt(
          url: lesson.still,
          seed: lesson.title,
          remote: lesson.remote,
          fallback: PosterShape.landscape,
          window: PosterShape.landscape,
          width: stillWidth,
          targetWidth: compact ? 260 : 320,
          glyphSize: compact ? 15 : 18
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        if let quality = lesson.quality {
          Text(quality)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
            .padding(4)
        }
      }

      VStack(alignment: .leading, spacing: 3) {
        if let index = lesson.index {
          Text(String(format: "%02d", index))
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.brand)
        }
        Text(lesson.title)
          .font(compact ? .footnote : .subheadline)
          .foregroundStyle(Palette.ink)
          .lineLimit(compact ? 3 : 2)
          .multilineTextAlignment(.leading)
        if let note = lesson.note, !note.isEmpty {
          Text(note)
            .font(.caption2)
            .foregroundStyle(Palette.inkDim)
            .lineLimit(1)
        }
        HStack(spacing: 6) {
          if lesson.seconds > 0 {
            Text(Format.clock(lesson.seconds))
          }
          if let bytes = lesson.bytes, bytes > 0 {
            Text(Format.bytes(bytes))
          }
          if lesson.needsDownload {
            Label("iCloud", systemImage: "icloud.and.arrow.down")
              .labelStyle(.titleAndIcon)
              .foregroundStyle(Palette.warn)
          }
        }
        .font(.caption2)
        .foregroundStyle(Palette.inkFaint)

        if let progress = lesson.progress, progress > 0.01 {
          ProgressView(value: min(progress, 1))
            .tint(Palette.brand)
            .frame(maxWidth: compact ? 120 : 140)
        }
      }

      Spacer(minLength: 0)

      accessory
    }
    .padding(.vertical, compact ? 7 : 8)
    .contentShape(Rectangle())
  }

  /// *Play* when the lesson is on this phone, because that is what tapping it
  /// does — and the queue's own readout for everything else, so the same row can
  /// say Download, 42%, Queued or Retry while a course comes down.
  @ViewBuilder private var accessory: some View {
    if lesson.local != nil {
      Image(systemName: "play.circle")
        .font(.title3)
        .foregroundStyle(Palette.inkDim)
    } else {
      HStack(spacing: 5) {
        Image(systemName: lesson.state.glyph)
          .font(.title3)
        Text(lesson.state.label)
          .font(.caption2.weight(.semibold))
      }
      .foregroundStyle(lesson.state.tint)
    }
  }
}
