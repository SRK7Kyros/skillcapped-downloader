import Foundation

/// Where a part belongs, carried by the transfer itself.
///
/// The system finishes a transfer even when this process is gone, so a task must
/// be able to say where its bytes go with none of the app's state in memory: the
/// job folder, the part's number and the lesson that folder belongs to.
struct BackgroundSegment: Codable, Equatable, Sendable {
  let uuid: String
  let jobFolder: String
  let index: Int

  init(uuid: String, jobFolder: URL, index: Int) {
    self.uuid = uuid
    self.jobFolder = jobFolder.path
    self.index = index
  }

  var partURL: URL {
    SegmentDownloader.partURL(URL(fileURLWithPath: jobFolder, isDirectory: true), index)
  }

  var encoded: String? {
    guard let data = try? JSONEncoder().encode(self) else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ description: String?) -> BackgroundSegment? {
    guard let description, let data = description.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(BackgroundSegment.self, from: data)
  }
}

/// The app's segment transfers, on a background `URLSession`.
///
/// A background session is the only way a transfer outlives the app being
/// suspended: the system runs it, writes each part to a temporary file, and wakes
/// the app to hand it over. `BackgroundSegment` rides along in the task's
/// description, so a completion arriving after a relaunch still lands in the right
/// place — with no caller and no queue in memory.
final class BackgroundTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  static let shared = BackgroundTransfer()
  static let identifier = "com.kyros.skillcappedlocal.segments"
  static let userAgent = "SkillCappedLocal/2.0 (iOS)"

  /// Called when a part lands with nobody waiting for it — the app was relaunched
  /// in the background just to take delivery — so the queue can pick its lesson
  /// up again.
  var onUnattendedPart: (@Sendable () -> Void)?

  private let lock = NSLock()
  private var waiters: [Int: CheckedContinuation<Int64, Error>] = [:]
  private var eventsCompletion: (() -> Void)?

  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    config.httpMaximumConnectionsPerHost = SegmentDownloader.segmentConcurrency
    config.timeoutIntervalForRequest = 60
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  /// Hand over the completion handler the system gives the app delegate, so the
  /// app is told it may suspend the moment this session's events are done.
  ///
  /// Touching `session` here matters as much as storing the handler: when the app
  /// is relaunched for transfers that finished while it was dead, this is the call
  /// that reconnects it to the system's session, and an app that never creates its
  /// session never receives those deliveries.
  func store(eventsCompletion completion: @escaping () -> Void) {
    lock.lock()
    let previous = eventsCompletion
    self.eventsCompletion = completion
    lock.unlock()
    _ = session
    previous?()
  }

  /// Fetch one part into its job folder and answer its size.
  func fetch(_ url: URL, part: BackgroundSegment) async throws -> Int64 {
    if Task.isCancelled { throw CancellationError() }
    let handle = CancellationHandle()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
          return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        task.taskDescription = part.encoded
        lock.lock()
        waiters[task.taskIdentifier] = continuation
        lock.unlock()
        handle.attach(task)
        // Resumed before it is cancelled: a task cancelled while still suspended
        // may never reach the delegate, which would leave this continuation — and
        // the lesson waiting on it — hanging for the rest of the session.
        task.resume()
        if Task.isCancelled { handle.cancel() }
      }
    } onCancel: {
      handle.cancel()
    }
  }

  /// Drop every transfer that belongs to a lesson, so a cancelled download does
  /// not keep writing parts into a folder nothing will ever read.
  func cancelLesson(_ uuid: String) {
    session.getAllTasks { tasks in
      for task in tasks where BackgroundSegment.decode(task.taskDescription)?.uuid == uuid {
        task.cancel()
      }
    }
  }

  // MARK: - Delegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
    guard let part = BackgroundSegment.decode(downloadTask.taskDescription) else {
      try? FileManager.default.removeItem(at: location)
      settle(downloadTask.taskIdentifier, with: .failure(DownloadError.storage))
      return
    }
    guard (200..<300).contains(status) else {
      // Past the tail a 403 is expected; the caller decides whether to retry.
      try? FileManager.default.removeItem(at: location)
      settle(
        downloadTask.taskIdentifier,
        with: .failure(DownloadError.segment(index: part.index, status: status))
      )
      return
    }
    do {
      settle(downloadTask.taskIdentifier, with: .success(try Self.place(location, at: part)))
    } catch {
      settle(downloadTask.taskIdentifier, with: .failure(error))
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    if let urlError = error as? URLError, urlError.code == .cancelled {
      settle(task.taskIdentifier, with: .failure(CancellationError()))
    } else {
      settle(task.taskIdentifier, with: .failure(error))
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    lock.lock()
    let completion = eventsCompletion
    eventsCompletion = nil
    lock.unlock()
    DispatchQueue.main.async { completion?() }
  }

  // MARK: - Landed parts

  /// The temporary file is only valid inside the delegate callback, so it is
  /// moved — never read later — and an empty body is a failure rather than a part
  /// the merge would happily concatenate.
  private static func place(_ temporary: URL, at part: BackgroundSegment) throws -> Int64 {
    let size = Int64((try? temporary.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    guard size > 0 else {
      try? FileManager.default.removeItem(at: temporary)
      throw DownloadError.emptySegment(index: part.index)
    }
    let destination = part.partURL
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: temporary, to: destination)
    return size
  }

  private func settle(_ identifier: Int, with outcome: Result<Int64, Error>) {
    lock.lock()
    let waiter = waiters.removeValue(forKey: identifier)
    lock.unlock()

    guard let waiter else {
      // Nobody is waiting: the app was relaunched just to take delivery, and the
      // part is already on disk for the next run to find.
      if case .success = outcome { onUnattendedPart?() }
      return
    }
    switch outcome {
    case let .success(size): waiter.resume(returning: size)
    case let .failure(error): waiter.resume(throwing: error)
    }
  }
}

/// Holds the task a fetch created, so cancelling the surrounding `Task` can cancel
/// the transfer too. A continuation alone cannot be reached from `onCancel`.
private final class CancellationHandle: @unchecked Sendable {
  private let lock = NSLock()
  private var task: URLSessionDownloadTask?

  func attach(_ task: URLSessionDownloadTask) {
    lock.lock()
    self.task = task
    lock.unlock()
  }

  func cancel() {
    lock.lock()
    let task = task
    lock.unlock()
    task?.cancel()
  }
}
