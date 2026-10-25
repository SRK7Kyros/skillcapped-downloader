import SwiftUI
import WidgetKit

/// A home-screen widget whose only job is to answer a question the app cannot ask
/// itself: is this app's widget extension loading at all?
///
/// The lock-screen card and this widget are drawn by the same extension, so a
/// sideloaded build whose extension iOS never launches shows neither. A card that
/// was requested and never drawn leaves no trace inside the app; an empty widget
/// gallery is that same silence made visible, without needing device logs.
struct ExtensionCheckEntry: TimelineEntry {
  let date: Date
}

struct ExtensionCheckProvider: TimelineProvider {
  func placeholder(in context: Context) -> ExtensionCheckEntry {
    ExtensionCheckEntry(date: .now)
  }

  func getSnapshot(in context: Context, completion: @escaping (ExtensionCheckEntry) -> Void) {
    completion(ExtensionCheckEntry(date: .now))
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<ExtensionCheckEntry>) -> Void
  ) {
    completion(Timeline(entries: [ExtensionCheckEntry(date: .now)], policy: .never))
  }
}

struct ExtensionCheckWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "ExtensionCheck", provider: ExtensionCheckProvider()) { _ in
      ExtensionCheckCard()
        .containerBackground(for: .widget) {
          Color(red: 0.039, green: 0.039, blue: 0.047)
        }
    }
    .configurationDisplayName("Extension check")
    .description(
      "Confirms this app's widget extension loads — the same extension that draws the download card."
    )
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct ExtensionCheckCard: View {
  private let brand = Color(red: 0.13, green: 0.88, blue: 0.42)

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: "checkmark.seal.fill")
        .font(.title2)
        .foregroundStyle(brand)
      Spacer(minLength: 0)
      Text("Extension loaded")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
      Text("This is the extension the download card is drawn by.")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}
