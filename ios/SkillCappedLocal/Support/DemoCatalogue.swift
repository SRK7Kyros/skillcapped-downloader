import Foundation

/// A throwaway catalogue for the UI test, so Discover and the page a catalogue
/// course opens can be driven without the network. Debug builds only.
///
/// Its lesson ids are the uuids `DemoLibrary` writes into its course folder, so
/// launched with both arguments the catalogue's course is also the course this
/// phone already has — which is the state the course page's *Play* pill is for.
enum DemoCatalogue {
  static func catalog() -> RemoteCatalog? {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains("-demoCatalog") else { return nil }
    return build()
    #else
    return nil
    #endif
  }

  #if DEBUG
  private static let courseTitle = "Why You Suck at ADC (ADC)"

  private static func build() -> RemoteCatalog {
    let lessons = [
      CatalogItem(
        id: "j413lhtmz7",
        kind: "video",
        title: "What's Next",
        role: "adc",
        durationSec: 130,
        date: Date(timeIntervalSince1970: 1_760_000_000),
        category: "Laning",
        tags: ["Laning", "adc"],
        courseTitle: courseTitle
      ),
      CatalogItem(
        id: "a1b2c3d4e5",
        kind: "video",
        title: "Farming Fundamentals",
        role: "adc",
        durationSec: 615,
        date: Date(timeIntervalSince1970: 1_760_000_000),
        category: "Farming",
        tags: ["Farming", "adc"],
        courseTitle: courseTitle
      ),
      CatalogItem(
        id: "zzzzzzzzzz",
        kind: "video",
        title: "Not On This Phone",
        role: "adc",
        durationSec: 400,
        date: Date(timeIntervalSince1970: 1_760_000_000),
        category: "Farming",
        tags: ["Farming", "adc"],
        courseTitle: courseTitle
      ),
    ]

    let course = CatalogItem(
      id: "demo-course-adc",
      kind: "course",
      title: courseTitle,
      role: "adc",
      date: Date(timeIntervalSince1970: 1_760_000_000),
      category: "Laning",
      tags: ["Laning", "adc"],
      lessonIds: lessons.map(\.id),
      videoCount: lessons.count
    )

    return RemoteCatalog(
      season: "2026",
      patch: "Demo",
      generatedAt: Date(),
      dumpUrl: "demo://catalogue",
      roles: CatalogService.roles,
      categories: ["Farming", "Laning"],
      items: [course] + lessons
    )
  }
  #endif
}
