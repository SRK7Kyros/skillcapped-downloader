import SwiftUI

/// One course on this phone.
///
/// Landscape is the one arrangement where the art can be an anchor rather than a
/// banner: the poster fills the left edge, whole and still, and the course's
/// words and *Play* are pinned above the lessons — the only thing that scrolls.
/// Portrait stacks instead: a poster a third of the width beside the words (never
/// cropped, never the page), then the lessons in the room below. The columns are
/// landscape-only because on a portrait phone a poster column eats the list.
struct CourseView: View {
  let course: Course

  @EnvironmentObject private var player: PlayerCoordinator
  @EnvironmentObject private var progress: ProgressStore

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
    if let first = course.lessons.first {
      Button {
        player.play(first, in: course.lessons)
      } label: {
        CoursePill(title: "Play", systemImage: "play.fill", compact: compact)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Play \(course.title) from the first lesson")
    }
  }

  private var meta: String {
    var parts = [Format.count(course.lessons.count, "lesson", "lessons")]
    if course.bytes > 0 { parts.append(Format.bytes(course.bytes)) }
    if course.seconds > 0 { parts.append(Format.clock(course.seconds)) }
    return parts.joined(separator: " · ")
  }

  // MARK: - The list that scrolls

  private func lessons(compact: Bool) -> some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(Array(course.lessons.enumerated()), id: \.element.id) { index, lesson in
          Button {
            player.play(lesson, in: course.lessons)
          } label: {
            LessonRow(
              lesson: lesson,
              index: index + 1,
              progress: progress.fraction(for: lesson.progressKey),
              compact: compact
            )
          }
          .buttonStyle(.plain)

          if lesson.id != course.lessons.last?.id {
            Divider().overlay(Palette.line)
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 4)
      .padding(.bottom, 36)
    }
  }
}
