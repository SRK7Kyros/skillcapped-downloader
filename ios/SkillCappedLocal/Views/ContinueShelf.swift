import SwiftUI

/// The last few lessons watched but not finished, so picking one up again is one
/// tap instead of a hunt through the library.
struct ContinueShelf: View {
  let lessons: [Lesson]

  @EnvironmentObject private var progress: ProgressStore
  @EnvironmentObject private var player: PlayerCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Continue watching")
        .font(.headline)
        .foregroundStyle(Palette.ink)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(lessons) { lesson in
            Button {
              player.play(lesson)
            } label: {
              card(lesson)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume \(lesson.title)")
          }
        }
        .padding(.vertical, 1)
      }
    }
  }

  private func card(_ lesson: Lesson) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Poster(url: lesson.url, seed: lesson.title, targetWidth: 360)
        .frame(width: 168, height: 94)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Palette.line, lineWidth: 1)
        }

      Text(lesson.title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(Palette.ink)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .frame(width: 168, alignment: .leading)

      ProgressView(value: progress.fraction(for: lesson.progressKey) ?? 0)
        .tint(Palette.brand)
        .frame(width: 168)
    }
  }
}
