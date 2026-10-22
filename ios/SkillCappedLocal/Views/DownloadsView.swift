import SwiftUI

/// The queue: what is coming down, what landed, and what failed. One lesson at
/// a time, four parts at once inside it.
struct DownloadsView: View {
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var player: PlayerCoordinator

  var body: some View {
    NavigationStack {
      Group {
        if downloads.tasks.isEmpty {
          empty
        } else {
          list
        }
      }
      .background(Palette.bg.ignoresSafeArea())
      .navigationTitle("Downloads")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if !downloads.finished.isEmpty {
            Button("Clear") { downloads.clearFinished() }
              .accessibilityLabel("Clear finished downloads")
          }
        }
      }
    }
  }

  private var empty: some View {
    VStack(spacing: 10) {
      Image(systemName: "arrow.down.circle")
        .font(.largeTitle)
        .foregroundStyle(Palette.inkFaint)
      Text("Nothing queued")
        .font(.headline)
        .foregroundStyle(Palette.ink)
      Text("Pick a course or a lesson in Discover and it comes down here, then into your library.")
        .font(.footnote)
        .foregroundStyle(Palette.inkDim)
        .multilineTextAlignment(.center)
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var list: some View {
    List {
      if !downloads.queue.isEmpty {
        Section {
          ForEach(downloads.queue) { task in
            DownloadRow(task: task, speed: downloads.bytesPerSecond)
          }
        } header: {
          Text("Queue")
        } footer: {
          if let active = downloads.queue.first, active.state == .downloading, downloads.bytesPerSecond > 0 {
            Text("\(Format.bytes(Int64(downloads.bytesPerSecond)))/s")
          }
        }
      }

      if !downloads.failed.isEmpty {
        Section("Failed") {
          ForEach(downloads.failed) { task in
            DownloadRow(task: task, speed: 0)
          }
        }
      }

      if !downloads.finished.isEmpty {
        Section {
          ForEach(downloads.finished) { task in
            DownloadRow(task: task, speed: 0)
          }
        } header: {
          Text("On disk")
        } footer: {
          Text("\(Format.count(downloads.finished.count, "lesson", "lessons")) · \(Format.bytes(downloads.readyBytes))")
        }
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
  }
}

private struct DownloadRow: View {
  let task: DownloadTask
  let speed: Double

  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var player: PlayerCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(task.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Palette.ink)
          .lineLimit(2)
        Spacer(minLength: 0)
        Text(status)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(tint)
      }

      if task.state == .downloading || task.state == .remuxing {
        ProgressView(value: task.state == .remuxing ? 1 : task.fraction)
          .tint(Palette.brand)
      }

      HStack(spacing: 6) {
        Text(detail)
          .font(.caption2)
          .foregroundStyle(Palette.inkFaint)
        Spacer(minLength: 0)
        controls
      }
    }
    .padding(.vertical, 4)
  }

  private var status: String {
    switch task.state {
    case .queued: return "Queued"
    case .paused: return "Paused"
    case .downloading: return "\(Int(task.fraction * 100))%"
    case .remuxing: return "Finishing"
    case .ready: return task.actualQuality ?? "On disk"
    case .failed: return "Failed"
    case .cancelled: return "Cancelled"
    }
  }

  private var tint: Color {
    switch task.state {
    case .failed: return Palette.warn
    case .ready: return Palette.brand
    default: return Palette.inkDim
    }
  }

  private var detail: String {
    switch task.state {
    case .downloading:
      let parts = "\(task.segmentsDone)/\(task.segmentsTotal) parts"
      return speed > 0 ? "\(parts) · \(Format.bytes(Int64(speed)))/s" : parts
    case .remuxing:
      return "wrapping the stream into an MP4"
    case .ready:
      return Format.bytes(task.bytes)
    case .failed:
      return task.error ?? "the download failed"
    case .queued, .paused:
      return task.quality.map { "\($0) requested" } ?? "waiting for a slot"
    case .cancelled:
      return "cancelled"
    }
  }

  @ViewBuilder
  private var controls: some View {
    switch task.state {
    case .downloading, .queued:
      Button {
        downloads.pause(task.uuid)
      } label: {
        Image(systemName: "pause.circle")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Pause \(task.title)")

    case .paused:
      Button {
        downloads.resume(task.uuid)
      } label: {
        Image(systemName: "play.circle")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Resume \(task.title)")

    case .failed:
      Button {
        downloads.retry(task.uuid)
      } label: {
        Image(systemName: "arrow.clockwise.circle")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Retry \(task.title)")

    case .ready:
      Button {
        play()
      } label: {
        Image(systemName: "play.circle")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Play \(task.title)")

    case .remuxing, .cancelled:
      EmptyView()
    }

    Button(role: .destructive) {
      if task.state == .ready {
        downloads.removeFile(task.uuid)
      } else {
        downloads.cancel(task.uuid)
      }
    } label: {
      Image(systemName: task.state == .ready ? "trash" : "xmark.circle")
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(task.state == .ready ? "Delete \(task.title)" : "Remove \(task.title)")
  }

  private func play() {
    guard let path = task.path else { return }
    let url = URL(fileURLWithPath: path)
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    player.play(Lesson(
      id: url.path,
      url: url,
      title: task.title,
      role: task.role,
      quality: task.actualQuality,
      seconds: task.durationSec,
      bytes: Int64(size),
      modified: nil,
      itemId: task.uuid,
      needsDownload: false
    ))
  }
}
