import SwiftUI

/// The handful of choices the app remembers: which rendition to fetch first, the
/// order to fall back through, and how the player fills the window. Stored as
/// labels rather than tier ids, so a rendition the CDN adds later needs no
/// migration.
@MainActor
final class PreferencesStore: ObservableObject {
  @Published var qualityPriority: [String] {
    didSet { persist() }
  }

  @Published var videoFit: VideoFit {
    didSet { persist() }
  }

  private struct Saved: Codable {
    var qualityPriority: [String]?
    var videoFit: VideoFit?
  }

  private let url = JSONFile.url("preferences")

  init() {
    let saved = JSONFile.load(Saved.self, from: url)
    let kept = saved?.qualityPriority ?? []
    let usable = kept.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    videoFit = saved?.videoFit ?? .fit
    // A full order, always: the saved picks first, then every other known tier.
    qualityPriority = QualityPlan.ladder(
      requested: nil,
      priority: usable.isEmpty ? QualityPlan.defaultPriority : usable,
      available: []
    )
  }

  /// Reordering the list is the whole settings screen, so it is one move.
  func move(from source: IndexSet, to destination: Int) {
    qualityPriority.move(fromOffsets: source, toOffset: destination)
  }

  func reset() {
    qualityPriority = QualityPlan.ladder(
      requested: nil,
      priority: QualityPlan.defaultPriority,
      available: []
    )
  }

  private func persist() {
    JSONFile.save(Saved(qualityPriority: qualityPriority, videoFit: videoFit), to: url)
  }
}
