import SwiftUI

struct CourseView: View {
  let course: Course

  @EnvironmentObject private var player: PlayerCoordinator
  @EnvironmentObject private var progress: ProgressStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header

        LazyVStack(spacing: 0) {
          ForEach(Array(course.lessons.enumerated()), id: \.element.id) { index, lesson in
            Button {
              player.play(lesson, in: course.lessons)
            } label: {
              LessonRow(
                lesson: lesson,
                index: index + 1,
                progress: progress.fraction(for: lesson.progressKey)
              )
            }
            .buttonStyle(.plain)

            if lesson.id != course.lessons.last?.id {
              Divider().overlay(Palette.line)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
      }
      .padding(.bottom, 36)
    }
    .background(Palette.bg.ignoresSafeArea())
    .navigationTitle(course.title)
    .navigationBarTitleDisplayMode(.inline)
  }

  /// The first lesson's frame at its own shape, whole, with the course's words
  /// under it rather than printed over the art.
  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      PosterArt(
        url: course.bannerURL,
        seed: course.title,
        fallback: PosterShape.landscape,
        targetWidth: 1_100
      )

      VStack(alignment: .leading, spacing: 8) {
        if !course.role.isEmpty {
          Text(Format.roleLabel(course.role))
            .font(.caption2.weight(.heavy))
            .foregroundStyle(Palette.bg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.brand, in: Capsule())
        }
        Text(course.title)
          .font(.title2.weight(.bold))
          .foregroundStyle(Palette.ink)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 6) {
          Text(Format.count(course.lessons.count, "lesson", "lessons"))
          Text("·")
          Text(Format.bytes(course.bytes))
          if course.seconds > 0 {
            Text("·")
            Text(Format.clock(course.seconds))
          }
        }
        .font(.caption)
        .foregroundStyle(Palette.inkDim)
      }
      .padding(.horizontal, 16)
    }
  }
}
