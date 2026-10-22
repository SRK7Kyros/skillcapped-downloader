import SwiftUI

struct CourseCard: View {
  let course: Course

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topLeading) {
        Poster(url: course.bannerURL, seed: course.title, targetWidth: 560)
          .frame(height: 124)

        LinearGradient(
          colors: [.clear, Palette.bg.opacity(0.92)],
          startPoint: .center,
          endPoint: .bottom
        )

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
      .frame(height: 124)

      VStack(alignment: .leading, spacing: 5) {
        Text(course.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Palette.ink)
          .lineLimit(2)
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
      .padding(.vertical, 9)
    }
    .background(Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Palette.line, lineWidth: 1)
    }
  }
}

struct LessonRow: View {
  let lesson: Lesson
  var index: Int?
  var progress: Double?

  var body: some View {
    HStack(spacing: 12) {
      ZStack(alignment: .bottomTrailing) {
        Poster(url: lesson.url, seed: lesson.title, targetWidth: 320)
          .frame(width: 104, height: 59)
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
        if let index {
          Text(String(format: "%02d", index))
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.brand)
        }
        Text(lesson.title)
          .font(.subheadline)
          .foregroundStyle(Palette.ink)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        HStack(spacing: 6) {
          if lesson.seconds > 0 {
            Text(Format.clock(lesson.seconds))
          }
          Text(Format.bytes(lesson.bytes))
          if lesson.needsDownload {
            Label("iCloud", systemImage: "icloud.and.arrow.down")
              .labelStyle(.titleAndIcon)
              .foregroundStyle(Palette.warn)
          }
        }
        .font(.caption2)
        .foregroundStyle(Palette.inkFaint)

        if let progress, progress > 0.01 {
          ProgressView(value: min(progress, 1))
            .tint(Palette.brand)
            .frame(maxWidth: 140)
        }
      }

      Spacer(minLength: 0)

      Image(systemName: "play.circle")
        .font(.title3)
        .foregroundStyle(Palette.inkDim)
    }
    .padding(.vertical, 8)
    .contentShape(Rectangle())
  }
}
