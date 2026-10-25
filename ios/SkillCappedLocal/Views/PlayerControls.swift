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
    .glass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: 0.58, rim: 0.54)
  }
}
