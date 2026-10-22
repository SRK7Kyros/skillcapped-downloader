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

  private var header: some View {
    PosterArt(
      url: course.bannerURL,
      seed: course.title,
      fallback: PosterShape.landscape,
      height: 208,
      targetWidth: 1_100
    )
    .overlay(alignment: .bottom) {
      LinearGradient(
        colors: [.clear, Palette.bg.opacity(0.55), Palette.bg],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .overlay(alignment: .bottomLeading) {
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
      .padding(.bottom, 12)
    }
  }
}
