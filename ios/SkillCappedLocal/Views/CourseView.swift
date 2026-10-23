import SwiftUI

/// One course on this phone: its poster anchored on the left, its lessons
/// scrolling beside it, so the art never leaves the screen while a long course is
/// read.
struct CourseView: View {
  let course: Course

  @EnvironmentObject private var player: PlayerCoordinator
  @EnvironmentObject private var progress: ProgressStore

  var body: some View {
    GeometryReader { proxy in
      let side = Self.sideWidth(for: proxy.size.width)
      let narrow = proxy.size.width - side < 400
      HStack(alignment: .top, spacing: 0) {
        poster(width: side)
        Rectangle()
          .fill(Palette.line)
          .frame(width: 1)
        lessons(compact: narrow)
      }
    }
    .background(Palette.bg.ignoresSafeArea())
    .navigationTitle(course.title)
    .navigationBarTitleDisplayMode(.inline)
  }

  /// The column the poster takes: a little over a third of the screen, with a
  /// floor that still holds a readable title and a ceiling so an iPad's course
  /// page does not become a poster gallery.
  static func sideWidth(for width: CGFloat) -> CGFloat {
    guard width.isFinite, width > 0 else { return 156 }
    return min(max(width * 0.38, 132), 300)
  }

  private func poster(width: CGFloat) -> some View {
    let printed = course.posterURL != nil
    return ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 14) {
        PosterArt(
          url: course.artURL,
          seed: course.title,
          fallback: printed ? PosterShape.portraitArt : PosterShape.landscape,
          window: printed ? PosterShape.portrait : PosterShape.landscape,
          targetWidth: 640
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Palette.line, lineWidth: 1)
        }

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
            .font(.headline)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
          Text(meta)
            .font(.caption2)
            .foregroundStyle(Palette.inkFaint)
            .fixedSize(horizontal: false, vertical: true)

          if let first = course.lessons.first {
            Button {
              player.play(first, in: course.lessons)
            } label: {
              Label("Play", systemImage: "play.fill")
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Palette.brand, in: Capsule())
                .foregroundStyle(Palette.bg)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(course.title) from the first lesson")
            .padding(.top, 2)
          }
        }
      }
      .padding(14)
    }
    .frame(width: width)
  }

  private var meta: String {
    var parts = [Format.count(course.lessons.count, "lesson", "lessons")]
    if course.bytes > 0 { parts.append(Format.bytes(course.bytes)) }
    if course.seconds > 0 { parts.append(Format.clock(course.seconds)) }
    return parts.joined(separator: " · ")
  }

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
