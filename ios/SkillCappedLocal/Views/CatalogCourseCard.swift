import SwiftUI

/// A course as the site lists it, before anything is downloaded. The green
/// border is the same signal the web console uses: this course is already here.
struct CatalogCourseCard: View {
  let item: CatalogItem
  let downloaded: Int
  let total: Int

  private var complete: Bool { total > 0 && downloaded >= total }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PosterArt(
        url: item.thumbURL,
        seed: item.title,
        fallback: PosterShape.portrait,
        window: PosterShape.portrait,
        glyphSize: 24
      )
      .overlay(alignment: .topLeading) {
        HStack(spacing: 4) {
          if !item.role.isEmpty {
            Text(Format.roleLabel(item.role))
              .font(.caption2.weight(.heavy))
              .foregroundStyle(Palette.bg)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(Palette.brand, in: Capsule())
          }
          if complete {
            Text("On disk")
              .font(.caption2.weight(.heavy))
              .foregroundStyle(Palette.bg)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(Palette.brand, in: Capsule())
          }
        }
        .padding(8)
      }

      VStack(alignment: .leading, spacing: 5) {
        Text(item.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Palette.ink)
          .lineLimit(2, reservesSpace: true)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 6) {
          Text(total > 0 ? "\(downloaded)/\(total) lessons" : "no lessons listed")
          if let date = Format.date(item.date) {
            Text("·")
            Text(date)
          }
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
    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(complete ? Palette.brand : Palette.line, lineWidth: complete ? 1.5 : 1)
    }
  }
}

/// One catalogue row that is not inside a course — a video or a commentary in a
/// Discover list. It draws the same row the course page draws, so a lesson looks
/// the same wherever it appears; only its action differs.
struct CatalogLessonRow: View {
  let item: CatalogItem
  let state: RowState
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      CourseLessonRow(lesson: .catalogue(item, state: state), compact: false)
    }
    .buttonStyle(.plain)
    .disabled(state.isBusy)
    .accessibilityLabel("\(item.title), \(state.label)")
  }
}
