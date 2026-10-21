import Foundation

/// A throwaway library for the UI test, built inside the app's own sandbox so
/// the test can prove the scanner, the cards and the course screen work without
/// shipping any sample media. Debug builds only.
enum DemoLibrary {
  static func root() -> URL? {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains("-demoLibrary") else { return nil }
    return seed()
    #else
    return nil
    #endif
  }

  #if DEBUG
  private static func seed() -> URL? {
    let manager = FileManager.default
    guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    let root = documents.appendingPathComponent("DemoLibrary", isDirectory: true)
    try? manager.createDirectory(at: root, withIntermediateDirectories: true)

    write(root, "Courses/adc/Why You Suck at ADC (ADC)/What's Next [j413lhtmz7] 1080p.mp4")
    write(root, "Courses/adc/Why You Suck at ADC (ADC)/Farming Fundamentals [a1b2c3d4e5] 1080p.mp4")
    write(root, "Courses/support/How to Carry as Support/Warding [b2c3d4e5f6] 1080p.mp4")
    write(root, "Videos/mid/Ahri vs Zed [c3d4e5f6a7] 1080p.mp4")
    write(root, "Commentaries/jungle/Coaching Session [d4e5f6a7b8] 1080p.mp4")

    let catalog = """
    {"generatedAt": 1791325154871, "items": [
      {"id":"cjex4gnn44","kind":"course","title":"Why You Suck at ADC (ADC)","role":"adc","durationSec":0,"date":1791325154871,"category":"ADC - How to Carry","tags":["ADC"],"lessonIds":["a1b2c3d4e5","j413lhtmz7"],"videoCount":2},
      {"id":"j413lhtmz7","kind":"video","title":"What's Next","role":"adc","durationSec":842,"date":1791325795762,"category":"","tags":[],"courseTitle":"Why You Suck at ADC (ADC)"},
      {"id":"a1b2c3d4e5","kind":"video","title":"Farming Fundamentals","role":"adc","durationSec":905,"date":1791325795762,"category":"","tags":[],"courseTitle":"Why You Suck at ADC (ADC)"}
    ]}
    """
    let state = root.appendingPathComponent(".skillcapped", isDirectory: true)
    try? manager.createDirectory(at: state, withIntermediateDirectories: true)
    try? Data(catalog.utf8).write(to: state.appendingPathComponent("catalog.json"))
    return root
  }

  private static func write(_ root: URL, _ relative: String) {
    let url = root.appendingPathComponent(relative)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: Data())
    }
  }
  #endif
}
