import SwiftUI

struct CourseCard: View {
  let course: Course

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PosterArt(
        url: course.artURL,
        seed: course.title,
        fallback: PosterShape.portraitArt,
        window: PosterShape.portrait,
        targetWidth: 560,
        glyphSize: 22
      )
      .overlay(alignment: .topLeading) {
        if !course.role.isEmpty {
          Text(Format.roleLabel(course.role))
            .font(.caption2.weight(.heavy))
            .foregroundStyle(Palette.bg)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.brand, in: Capsule())
            .padding(8)
        }
      }

      VStack(alignment: .leading, spacing: 5) {
        Text(course.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Palette.ink)
          .lineLimit(2, reservesSpace: true)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 6) {
          Text(Format.count(course.lessons.count, "lesson", "lessons"))
          Text("·")
          Text(Format.bytes(course.bytes))
        }
        .font(.caption2)
        .foregroundStyle(Palette.inkFaint)
      }
      .padding(.horizontal, 10)
      .padding(.top, 4)
      .padding(.bottom, 9)
    }
    .background(Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Palette.line, lineWidth: 1)
    }
  }
}

/// The library's flat video rows draw the course page's row, so a lesson looks
/// the same wherever it is listed — one renderer, one geometry.
struct LessonRow: View {
  let lesson: Lesson
  var index: Int?
  var progress: Double?
  var compact = false

  var body: some View {
    CourseLessonRow(
      lesson: .here(lesson, index: index, progress: progress),
      compact: compact
    )
  }
}
