import SwiftUI
import UIKit

/// One export at a time: repackages a lesson when it has to, then raises the
/// share sheet.
///
/// A course is the same job several times over — the transport streams are
/// repackaged one after another and every file is handed to a single sheet — so a
/// batch and a single lesson take the same path.
///
/// The file is read off the main actor — a lesson is hundreds of megabytes and a
/// repackaging is a straight copy of every byte — so the numbers it reports come
/// back to it through `DispatchQueue.main`, and the banner that shows them is the
/// only thing the user sees while it runs.
final class LessonExport: ObservableObject {
  /// What a running export is doing, in the words of the banner that shows it.
  struct Work: Equatable {
    let title: String
    var stage: String
    var fraction: Double
  }

  @Published private(set) var work: Work?
  /// The last thing that went wrong, for the view to present.
  @Published var failure: String?

  private var cancelFlag = Flag()

  // MARK: - Sharing

  /// Shares the file as it lies on disk. Nothing is copied, so this is instant.
  func asIs(_ lesson: Lesson) {
    share([lesson], converting: false)
  }

  /// Repackages a transport stream into an MP4, then shares that.
  func remux(_ lesson: Lesson) {
    share([lesson], converting: true)
  }

  /// Shares several files at once — a whole course — repackaging the transport
  /// streams first when `converting` was the answer.
  func share(_ lessons: [Lesson], converting: Bool) {
    guard work == nil else { return }
    let plan = LessonExportPlan.batch(lessons)
    guard !plan.isEmpty else {
      failure = "There is nothing on this phone to share."
      return
    }
    guard converting, !plan.converts.isEmpty else {
      raise(plan.lessons.map(\.url), temporary: [])
      return
    }

    let folder = Self.exportsFolder
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      failure = "The export folder could not be made."
      return
    }

    let flag = Flag()
    cancelFlag = flag
    let jobs = plan.converts
    let sources = plan.lessons.map(\.url)
    let total = jobs.count
    work = Work(title: jobs[0].title, stage: Self.stage(done: 0, of: total), fraction: 0)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      var made: [URL] = []

      for (index, lesson) in jobs.enumerated() {
        guard !flag.isSet else {
          Self.discard(made)
          return
        }
        let destination = Self.unique(
          LessonExportPlan.destination(folder: folder, title: lesson.title, quality: lesson.quality),
          taken: made
        )
        DispatchQueue.main.async {
          self?.work = Work(
            title: lesson.title,
            stage: Self.stage(done: index, of: total),
            fraction: Double(index) / Double(total)
          )
        }

        do {
          try TSRemux.toMP4(
            source: lesson.url,
            destination: destination,
            progress: { value in
              DispatchQueue.main.async {
                self?.work?.fraction = (Double(index) + value) / Double(total)
              }
            },
            cancelled: { flag.isSet }
          )
          made.append(destination)
        } catch {
          Self.discard(made)
          DispatchQueue.main.async {
            guard let self else { return }
            self.work = nil
            // Stopping is an answer, not a fault: the banner that was asked to go
            // is gone, and an alert on top of that would be an accusation.
            if let remux = error as? TSRemux.Failure, case .cancelled = remux { return }
            self.failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
          }
          return
        }
      }

      DispatchQueue.main.async {
        guard let self else {
          Self.discard(made)
          return
        }
        self.work = nil
        self.raise(sources + made, temporary: Set(made))
      }
    }
  }

  /// Stops the repackaging. The share sheet is not something to cancel.
  func cancel() {
    cancelFlag.set()
    work = nil
  }

  // MARK: - The sheet

  private func raise(_ files: [URL], temporary: Set<URL>) {
    guard !files.isEmpty else { return }
    let sheet = UIActivityViewController(activityItems: files, applicationActivities: nil)
    sheet.completionWithItemsHandler = { _, _, _, _ in
      // A repackaged copy is scratch: it leaves only by being copied out.
      Self.discard(Array(temporary))
    }

    // On a tablet the sheet is a popover, and a popover with no anchor is a crash
    // rather than a picture: anchor it on the middle of the screen.
    if let popover = sheet.popoverPresentationController, let host = OnScreen.top() {
      popover.sourceView = host.view
      popover.sourceRect = CGRect(
        x: host.view.bounds.midX,
        y: host.view.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }

    guard OnScreen.present(sheet) else {
      Self.discard(Array(temporary))
      failure = "There was no screen to share from."
      return
    }
  }

  static var exportsFolder: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
  }

  // MARK: - One batch's bookkeeping

  /// One file reports what it is doing; a course reports how far it has got.
  private static func stage(done: Int, of total: Int) -> String {
    total <= 1 ? "Repackaging to MP4" : "Repackaging \(min(done + 1, total)) of \(total)"
  }

  /// Two lessons of one course can be titled the same, and the second must not
  /// overwrite the first's copy while the sheet is still holding it.
  private static func unique(_ url: URL, taken: [URL]) -> URL {
    guard taken.contains(url) else { return url }
    let folder = url.deletingLastPathComponent()
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    var index = 2
    while taken.contains(folder.appendingPathComponent("\(base) \(index).\(ext)")) {
      index += 1
    }
    return folder.appendingPathComponent("\(base) \(index).\(ext)")
  }

  private static func discard(_ files: [URL]) {
    for file in files {
      try? FileManager.default.removeItem(at: file)
    }
  }

  /// A one-way switch: the reader on a background queue consults it while the
  /// main actor flips it, and it is the only state that crosses between them.
  private final class Flag {
    private let lock = NSLock()
    private var raised = false

    func set() {
      lock.lock()
      raised = true
      lock.unlock()
    }

    var isSet: Bool {
      lock.lock()
      defer { lock.unlock() }
      return raised
    }
  }
}
