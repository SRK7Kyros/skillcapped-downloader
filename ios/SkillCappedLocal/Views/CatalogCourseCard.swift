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

/// One catalogue lesson, remote or already here.
struct CatalogLessonRow: View {
  let item: CatalogItem
  var index: Int?
  let state: RowState
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ZStack(alignment: .bottomTrailing) {
          PosterArt(
            url: item.thumbURL,
            seed: item.title,
            fallback: PosterShape.landscape,
            window: PosterShape.landscape,
            width: 104,
            glyphSize: 18
          )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

          if item.durationSec > 0 {
            Text(Format.clock(item.durationSec))
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
          Text(item.title)
            .font(.subheadline)
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
          if let meta = subtitle {
            Text(meta)
              .font(.caption2)
              .foregroundStyle(Palette.inkFaint)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)

        HStack(spacing: 5) {
          Image(systemName: state.glyph)
            .font(.title3)
          Text(state.label)
            .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(state.tint)
      }
      .padding(.vertical, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(state.isBusy)
    .accessibilityLabel("\(item.title), \(state.label)")
  }

  private var subtitle: String? {
    var parts: [String] = []
    if let staff = item.staff, !staff.isEmpty { parts.append(staff) }
    if let champions = item.champions, !champions.isEmpty { parts.append(champions) }
    if let kda = item.kda, !kda.isEmpty { parts.append(kda) }
    if !item.category.isEmpty { parts.append(item.category) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}
