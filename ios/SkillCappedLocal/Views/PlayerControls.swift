import SwiftUI

/// One control in the player's chrome: a glyph with a comfortable hit area, and
/// a label a screen reader can read.
struct PlayerButton: View {
  let glyph: String
  var size: CGFloat = 20
  var disabled = false
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: glyph)
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(disabled ? Color.white.opacity(0.3) : .white)
        .frame(width: size + 26, height: size + 26)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityLabel(label)
  }
}

/// The bar under the transport: a track, a knob, and a drag that seeks — a
/// fingertip a little off the line still scrubs, because the whole 24-point row
/// is the target.
struct PlayerScrubber: View {
  var position: Double
  var duration: Double
  var onScrub: (Double) -> Void
  var onCommit: (Double) -> Void

  @State private var dragging = false

  var body: some View {
    GeometryReader { proxy in
      let width = max(proxy.size.width, 1)
      let fraction = PlayerMath.fraction(position: position, duration: duration)
      let knob: CGFloat = dragging ? 15 : 11

      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.white.opacity(0.22))
          .frame(height: 4)

        Capsule()
          .fill(Palette.brand)
          .frame(width: width * fraction, height: 4)

        Circle()
          .fill(Color.white)
          .frame(width: knob, height: knob)
          .offset(x: min(max(width * fraction - knob / 2, 0), width - knob))
          .opacity(dragging ? 1 : 0.9)
      }
      .frame(height: 24)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard duration > 0 else { return }
            dragging = true
            onScrub(PlayerMath.seconds(x: value.location.x, width: width, duration: duration))
          }
          .onEnded { value in
            dragging = false
            guard duration > 0 else { return }
            onCommit(PlayerMath.seconds(x: value.location.x, width: width, duration: duration))
          }
      )
    }
    .frame(height: 24)
  }
}

/// The lessons the player can reach without leaving it: the queue it was opened
/// from, each with the picture it is known by, how far into it the viewer got and
/// how long it runs. Tapping one plays it, so a course can be worked through from
/// inside the player instead of backing out to the list between lessons.
struct PlayerQueueDrawer: View {
  let queue: [Lesson]
  let current: Lesson
  /// Where the picture on screen has got to, for the row of the lesson playing.
  /// The store only learns a position every few seconds, so a row drawn from it
  /// alone would sit still while the lesson ran.
  let liveFraction: Double?
  let window: CGSize
  let select: (Lesson) -> Void

  @EnvironmentObject private var progress: ProgressStore

  /// As wide as the transport's own sheet allows on the narrowest phone, and no
  /// wider than a comfortable reading measure on a phone on its side.
  private var width: CGFloat { min(340, max(220, window.width - 56)) }

  /// Tall enough for the lessons a course has, never so tall that the drawer
  /// would climb into the header of a phone on its side.
  private var listHeight: CGFloat {
    let cap = min(320, max(150, window.height * 0.55))
    return min(cap, CGFloat(queue.count) * PlayerQueueRow.height)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Text("Queue")
          .font(.system(size: 12, weight: .heavy))
          .foregroundStyle(.white)
        if let place = PlayerQueueSummary.position(of: current.id, in: queue) {
          Text(place)
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .padding(.bottom, 6)

      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(queue) { lesson in
            PlayerQueueRow(
              lesson: lesson,
              playing: lesson.id == current.id,
              watched: lesson.id == current.id ? (liveFraction ?? stored(lesson)) : stored(lesson),
              action: { select(lesson) }
            )
          }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
      }
      .frame(height: listHeight)
      .scrollIndicators(.hidden)
    }
    .frame(width: width)
    .glass(
      RoundedRectangle(cornerRadius: 26, style: .continuous),
      tint: 0.80,
      rim: 0.58,
      rimWidth: 1.2,
      lift: 0.5
    )
  }

  private func stored(_ lesson: Lesson) -> Double? {
    progress.fraction(for: lesson.progressKey)
  }
}

/// One lesson in the queue drawer: its picture, its name, a bar for how much of
/// it is behind the viewer, and how long it runs.
struct PlayerQueueRow: View {
  /// The height a row is drawn at, so the drawer can size itself to the number of
  /// lessons in it instead of being a fixed sheet with a band of empty glass.
  static let height: CGFloat = 66

  let lesson: Lesson
  let playing: Bool
  let watched: Double?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        PosterArt(
          url: lesson.url,
          seed: lesson.id,
          remote: lesson.posterURL,
          window: PosterShape.landscape,
          width: 68,
          targetWidth: 200,
          glyphSize: 15
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

        VStack(alignment: .leading, spacing: 3) {
          Text(lesson.title)
            .font(.system(size: 12.5, weight: playing ? .semibold : .medium))
            .foregroundStyle(.white.opacity(playing ? 1 : 0.88))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

          track

          Text(PlayerQueueSummary.detail(seconds: lesson.seconds, watched: watched))
            .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.58))
            .lineLimit(1)
        }

        Spacer(minLength: 4)

        if playing {
          Image(systemName: "waveform")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.brand)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .frame(height: Self.height)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(playing ? Color.white.opacity(0.10) : Color.clear)
      )
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(lesson.title)
    .accessibilityValue(PlayerQueueSummary.detail(seconds: lesson.seconds, watched: watched))
  }

  private var track: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.16))
        Capsule()
          .fill(Palette.brand)
          .frame(width: proxy.size.width * CGFloat(min(max(watched ?? 0, 0), 1)))
      }
    }
    .frame(height: 3)
  }
}

/// What the last gesture did, held on screen long enough to read.
enum PlayerHUD: Equatable {
  /// Seconds skipped: positive forward, negative back.
  case skip(Double)
  /// A level, 0…1 — the screen's brightness or the sound's volume.
  case brightness(Double)
  case volume(Double)
  /// The playhead a drag is aiming at.
  case time(Double)
  /// Double speed, for as long as the picture is held.
  case speed

  var glyph: String {
    switch self {
    case let .skip(seconds): return seconds < 0 ? "gobackward" : "goforward"
    case .brightness: return "sun.max.fill"
    case .volume: return "speaker.wave.2.fill"
    case .time: return "timer"
    case .speed: return "speedometer"
    }
  }

  var label: String {
    switch self {
    case let .skip(seconds):
      let rounded = Int(abs(seconds).rounded())
      return seconds < 0 ? "−\(rounded)s" : "+\(rounded)s"
    case let .brightness(level):
      return "\(Int((level * 100).rounded()))%"
    case let .volume(level):
      return "\(Int((level * 100).rounded()))%"
    case let .time(seconds):
      return PlayerMath.clock(seconds)
    case .speed:
      return "\(Int(HoldToSpeed.factor))×"
    }
  }
}

struct PlayerHUDView: View {
  let hud: PlayerHUD

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: hud.glyph)
        .font(.system(size: 22, weight: .semibold))
      Text(hud.label)
        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 18)
    .padding(.vertical, 13)
    .glass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: 0.80, rim: 0.54)
  }
}
