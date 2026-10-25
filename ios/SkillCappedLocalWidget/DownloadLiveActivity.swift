import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SkillCappedWidgetBundle: WidgetBundle {
  var body: some Widget {
    DownloadLiveActivity()
  }
}

/// The download queue on the lock screen, and in the Dynamic Island.
///
/// It only draws what the app hands it: the activity carries no logic beyond a
/// percentage, so a card whose app has been suspended is dim rather than wrong.
struct DownloadLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
      LockScreenCard(state: context.state)
        .activityBackgroundTint(Brand.card)
        .activitySystemActionForegroundColor(Brand.brand)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: context.state.paused ? "pause.circle.fill" : "arrow.down.circle.fill")
            .font(.title2)
            .foregroundStyle(Brand.brand)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(Brand.percent(context.state.percent))
            .font(.headline.monospacedDigit())
            .foregroundStyle(Brand.brand)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.currentTitle)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: context.state.percent)
              .tint(Brand.brand)
            Text(Brand.detail(context.state))
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
      } compactLeading: {
        Image(systemName: "arrow.down.circle.fill")
          .foregroundStyle(Brand.brand)
      } compactTrailing: {
        Text(Brand.percent(context.state.percent))
          .font(.caption2.monospacedDigit())
      } minimal: {
        Image(systemName: "arrow.down.circle.fill")
          .foregroundStyle(Brand.brand)
      }
      .keylineTint(Brand.brand)
    }
  }
}

private struct LockScreenCard: View {
  let state: DownloadActivityAttributes.ContentState

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: state.paused ? "pause.circle.fill" : "arrow.down.circle.fill")
        .font(.title2)
        .foregroundStyle(Brand.brand)

      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(Brand.detail(state))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Text(Brand.percent(state.percent))
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(Brand.brand)
        }
        Text(state.currentTitle)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.white)
          .lineLimit(1)
        if let course = state.currentCourse, !course.isEmpty {
          Text(course)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        ProgressView(value: state.percent)
          .tint(Brand.brand)
      }
    }
    .padding(14)
  }
}

/// The app's palette, in the two colours a lock-screen card needs. The widget
/// cannot import the app's `Palette`, so the brand green is restated here.
private enum Brand {
  static let brand = Color(red: 0.13, green: 0.88, blue: 0.42)
  static let card = Color(red: 0.039, green: 0.039, blue: 0.047)

  static func percent(_ value: Double) -> String {
    "\(Int((min(1, max(0, value)) * 100).rounded()))%"
  }

  static func bytes(_ value: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: value)
  }

  static func detail(_ state: DownloadActivityAttributes.ContentState) -> String {
    if state.paused { return "Paused" }
    let left = state.lessonsLeft == 1 ? "1 lesson left" : "\(state.lessonsLeft) lessons left"
    return state.bytesDone > 0 ? "\(left) · \(bytes(state.bytesDone))" : left
  }
}
