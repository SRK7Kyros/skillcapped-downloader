import SwiftUI

/// Where a repackaging says how far along it is, and how to stop it — one banner
/// per export, whichever screen started it.
struct ExportBanner: View {
  let work: LessonExport.Work
  let onStop: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(work.stage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(Palette.ink)
        Spacer(minLength: 8)
        Text(work.fraction, format: .percent.precision(.fractionLength(0)))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(Palette.inkFaint)
        Button("Stop", action: onStop)
          .font(.caption.weight(.semibold))
          .foregroundStyle(Palette.brand)
      }

      Text(work.title)
        .font(.caption2)
        .foregroundStyle(Palette.inkFaint)
        .lineLimit(1)

      ProgressView(value: min(max(work.fraction, 0), 1))
        .tint(Palette.brand)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.surfaceStrong)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Palette.line)
        .frame(height: 1)
    }
  }
}
