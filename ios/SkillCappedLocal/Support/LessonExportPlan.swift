import Foundation

/// What *export* means for one lesson, decided without touching a file: which
/// shape it takes and what the share sheet calls it.
///
/// The sharing itself — reading a lesson, repackaging a transport stream, raising
/// the sheet — is `LessonExport`.
enum LessonExportPlan {
  enum Shape: Equatable {
    /// Already a file a desktop opens: share it as it lies.
    case asIs
    /// A transport stream is not, so it is repackaged into an MP4 first.
    case remux
  }

  /// A transport stream is exactly what this app writes to disk and exactly what
  /// nothing else on the machine will open, so its extension decides.
  static func shape(for url: URL) -> Shape {
    url.pathExtension.lowercased() == "ts" ? .remux : .asIs
  }

  /// Whether the lesson's bytes are on this phone. One that is only in iCloud has
  /// to be fetched first — the player does that on demand — and neither a share
  /// sheet nor a delete has anywhere to say "downloading".
  static func isOnThisPhone(_ lesson: Lesson) -> Bool {
    !lesson.needsDownload
  }

  /// `Why You Suck at ADC 1080p.mp4` — the name the sheet shows. The uuid the
  /// library files a lesson under is left out: a person is choosing where this
  /// goes, and `[j413lhtmz7]` is not their business.
  static func fileName(title: String, quality: String?) -> String {
    let base = DownloadPlan.sanitize(title)
    guard let quality, !quality.trimmingCharacters(in: .whitespaces).isEmpty else {
      return base + ".mp4"
    }
    return base + " " + DownloadPlan.sanitize(quality, maxLength: 12) + ".mp4"
  }

  /// Where the repackaged copy waits for the sheet. The folder is scratch: the
  /// sheet copies the file out, and the copy here is removed when it closes.
  static func destination(folder: URL, title: String, quality: String?) -> URL {
    folder.appendingPathComponent(fileName(title: title, quality: quality), isDirectory: false)
  }
}
