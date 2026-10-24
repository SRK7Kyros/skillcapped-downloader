import SwiftUI
import UIKit

/// One export at a time: repackages a lesson when it has to, then raises the
/// share sheet.
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
    guard work == nil else { return }
    raise(lesson.url, temporary: false)
  }

  /// Repackages a transport stream into an MP4, then shares that.
  func remux(_ lesson: Lesson) {
    guard work == nil else { return }
    let folder = Self.exportsFolder
    let destination = LessonExportPlan.destination(
      folder: folder,
      title: lesson.title,
      quality: lesson.quality
    )
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      failure = "The export folder could not be made."
      return
    }

    let flag = Flag()
    cancelFlag = flag
    let source = lesson.url
    work = Work(title: lesson.title, stage: "Repackaging to MP4", fraction: 0)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let outcome: Result<Void, Error>
      do {
        try TSRemux.toMP4(
          source: source,
          destination: destination,
          progress: { value in
            DispatchQueue.main.async { self?.work?.fraction = value }
          },
          cancelled: { flag.isSet }
        )
        outcome = .success(())
      } catch {
        outcome = .failure(error)
      }

      DispatchQueue.main.async {
        guard let self else { return }
        self.work = nil
        switch outcome {
        case .success:
          self.raise(destination, temporary: true)
        case let .failure(error):
          // Stopping is an answer, not a fault: the banner that was asked to go
          // is gone, and an alert on top of that would be an accusation.
          if let remux = error as? TSRemux.Failure, case .cancelled = remux { return }
          self.failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
      }
    }
  }

  /// Stops the repackaging. The share sheet is not something to cancel.
  func cancel() {
    cancelFlag.set()
    work = nil
  }

  // MARK: - The sheet

  private func raise(_ file: URL, temporary: Bool) {
    let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
    sheet.completionWithItemsHandler = { _, _, _, _ in
      // A repackaged copy is scratch: it leaves only by being copied out.
      guard temporary else { return }
      try? FileManager.default.removeItem(at: file)
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
      if temporary { try? FileManager.default.removeItem(at: file) }
      failure = "There was no screen to share from."
      return
    }
  }

  static var exportsFolder: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
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
