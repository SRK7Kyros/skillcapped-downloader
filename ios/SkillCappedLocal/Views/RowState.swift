import SwiftUI

/// The download affordance every catalogue row carries, in one place so the
/// states cannot drift apart between the grid and the course screen.
enum RowState: Equatable {
  case remote
  case queued
  case downloading(Double)
  case remuxing
  case onDisk
  case failed(String)

  var glyph: String {
    switch self {
    case .remote: return "arrow.down.circle"
    case .queued: return "clock"
    case .downloading, .remuxing: return "arrow.down.circle.fill"
    case .onDisk: return "checkmark.circle.fill"
    case .failed: return "exclamationmark.triangle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .remote: return Palette.inkDim
    case .queued, .downloading, .remuxing: return Palette.brand
    case .onDisk: return Palette.brand
    case .failed: return Palette.warn
    }
  }

  var label: String {
    switch self {
    case .remote: return "Download"
    case .queued: return "Queued"
    case let .downloading(fraction): return "\(Int(fraction * 100))%"
    case .remuxing: return "Finishing"
    case .onDisk: return "On disk"
    case .failed: return "Retry"
    }
  }

  var isBusy: Bool {
    switch self {
    case .queued, .downloading, .remuxing: return true
    default: return false
    }
  }
}

/// What a catalogue id is doing right now: on disk (either the app's own queue or
/// a file that was already in the library), in the queue, or still remote.
@MainActor
enum CatalogState {
  static func of(
    _ id: String,
    downloads: DownloadManager,
    onDisk: Set<String>
  ) -> RowState {
    if let task = downloads.task(for: id) {
      switch task.state {
      case .queued, .paused: return .queued
      case .downloading: return .downloading(task.fraction)
      case .remuxing: return .remuxing
      case .ready: return .onDisk
      case .failed: return .failed(task.error ?? "Failed")
      case .cancelled: break
      }
    }
    return onDisk.contains(id) ? .onDisk : .remote
  }
}
