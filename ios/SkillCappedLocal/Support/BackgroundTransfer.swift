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

  /// Called on the delegate's thread the moment the last transfer in flight has
  /// settled. With a lesson's whole part list handed over at once, that means its
  /// parts are all on disk and the merge is next — so whatever is listening has to
  /// keep the process alive right now, not a hop later.
  var onWentIdle: (@Sendable () -> Void)?

  private let lock = NSLock()
  private var waiters: [Int: CheckedContinuation<Int64, Error>] = [:]
  /// Parts that settled before anything asked for them. Ordinary now that a whole
  /// lesson is handed over at once: the system finishes them faster than the queue
  /// consumes the results, and a relaunch delivers some with no caller at all.
  private var landed: [Int: Result<Int64, Error>] = [:]
  /// The tasks this process started, so an awaited part can be cancelled (or a
  /// cancellation of the awaiting task reached) without a continuation in hand.
  private var transfers: [Int: URLSessionDownloadTask] = [:]
  /// Every task this process started and has not settled yet. A task the *system*
  /// carried on from a previous launch was never registered here, and answers
  /// through `onUnattendedPart` instead.
  private var inFlight: Set<Int> = []
  private var eventsCompletion: (() -> Void)?

  private lazy var session: URLSession = Self.makeSession(delegate: self)

  private static func makeSession(delegate: URLSessionDelegate) -> URLSession {
    let config = URLSessionConfiguration.background(withIdentifier: identifier)
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    config.httpMaximumConnectionsPerHost = SegmentDownloader.segmentConcurrency
    config.timeoutIntervalForRequest = 60
    return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
  }

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

  /// Hand one part to the system, without waiting for it.
  ///
  /// Synchronous on purpose: a lesson's entire part list goes over in a single
  /// turn, so the app never has to be awake a second time to finish enqueuing. The
  /// batch-at-a-time version needed a wake per batch of four, and iOS owes the app
  /// none — a phone that was left alone stopped with four parts queued and nothing
  /// in the air to wake it. `wait(for:)` collects the result.
  @discardableResult
  func start(_ url: URL, part: BackgroundSegment) -> Int? {
    guard !Task.isCancelled else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 60
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    let task = session.downloadTask(with: request)
    task.taskDescription = part.encoded
    lock.lock()
    inFlight.insert(task.taskIdentifier)
    transfers[task.taskIdentifier] = task
    lock.unlock()
    // Resumed before it is cancelled: a task cancelled while still suspended may
    // never reach the delegate, which would leave a waiter hanging for the rest of
    // the session.
    task.resume()
    return task.taskIdentifier
  }

  /// Await a part that was already handed over.
  ///
  /// Bounded on purpose. The system owns the transfer, so the app is never told
  /// when one is dropped — and a wait with no bound is a queue that never moves
  /// again (see `TransferWatchdog`). The bound is **silence**, not elapsed time: the
  /// byte count is sampled while the app is awake, so a part that stopped receiving
  /// is handed over again in 30 s, while one that was merely suspended between wakes
  /// is left alone. When the window passes the task is cancelled and the waiter
  /// answered with a timeout, which the caller retries as a fresh hand-over.
  func wait(
    for identifier: Int,
    silent: TimeInterval = TransferWatchdog.silence(for: 1)
  ) async throws -> Int64 {
    let watchdog = Task { [weak self] in
      var silence = TransferSilence()
      while !Task.isCancelled {
        // A cancelled sleep means the part came back in time, so there is nothing to
        // expire — falling through here would kill a transfer that just succeeded.
        // Sleeping in short samples is what lets the question be asked again rather
        // than asked once.
        do { try await Task.sleep(for: .seconds(TransferWatchdog.sample)) } catch { return }
        guard let self else { return }
        // Nothing to watch: the task settled, and its waiter has been resumed.
        guard let received = self.received(identifier) else { return }
        if silence.observe(received, at: Date(), lostAfter: silent) {
          self.expire(identifier, silent: silent, received: received)
          return
        }
      }
    }
    defer { watchdog.cancel() }
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        lock.lock()
        if let outcome = landed.removeValue(forKey: identifier) {
          lock.unlock()
          continuation.resume(with: outcome)
          return
        }
        if Task.isCancelled {
          let task = transfers[identifier]
          lock.unlock()
          task?.cancel()
          continuation.resume(throwing: CancellationError())
          return
        }
        waiters[identifier] = continuation
        lock.unlock()
      }
    } onCancel: {
      cancel(identifier)
    }
  }

  /// Bytes this transfer has received, or `nil` when it is no longer in flight — a
  /// task that has settled is not a task to watch.
  private func received(_ identifier: Int) -> Int64? {
    lock.lock()
    defer { lock.unlock() }
    return transfers[identifier]?.countOfBytesReceived
  }

  /// The window passed with the part still in the system's hands: stop the
  /// transfer and answer its waiter with a timeout, so the lesson hands the part
  /// over again instead of waiting for a task that is not coming back.
  ///
  /// Answering exactly once is the whole job — a continuation resumed here must not
  /// also be resumed by a `settle` that arrives a moment later, which is why the
  /// waiter is taken out of the table while the lock is held.
  private func expire(_ identifier: Int, silent: TimeInterval, received: Int64) {
    lock.lock()
    let waiter = waiters.removeValue(forKey: identifier)
    let task = transfers.removeValue(forKey: identifier)
    inFlight.remove(identifier)
    let idle = inFlight.isEmpty
    lock.unlock()
    guard let waiter else { return }
    let part = task.flatMap { BackgroundSegment.decode($0.taskDescription)?.index }
    BackgroundJournal.shared.record(
      "part \(part.map { String($0) } ?? "-") received no bytes for "
        + "\(Int(silent)) s (\(received) bytes) — handing it over again"
    )
    task?.cancel()
    // Same rule as a settle that brought the last part in: the next window is
    // handed over from this process, so it needs the app awake to hand it over.
    if idle { onWentIdle?() }
    waiter.resume(throwing: URLError(.timedOut))
  }

  func cancel(_ identifier: Int) {
    lock.lock()
    let task = transfers[identifier]
    lock.unlock()
    task?.cancel()
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
    DispatchQueue.main.async {
      BackgroundJournal.shared.record("transfer events done")
      completion?()
    }
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
    let started = inFlight.remove(identifier) != nil
    transfers.removeValue(forKey: identifier)
    if waiter == nil, started {
      // Kept until its caller asks. A batch a lesson never came back for leaves a
      // few hundred of these behind — a few tens of kilobytes — and dropping one
      // would hang the `wait` that still wants it, so nothing is evicted.
      landed[identifier] = outcome
    }
    let idle = inFlight.isEmpty
    lock.unlock()

    // Announced before the waiter is resumed: the lease this takes is queued ahead
    // of the work that needs it, which is the whole point of saying it now.
    if started, idle { onWentIdle?() }

    guard let waiter else {
      // Nobody is waiting: the app was relaunched just to take delivery, and the
      // part is already on disk for the next run to find.
      if !started, case .success = outcome { onUnattendedPart?() }
      return
    }
    switch outcome {
    case let .success(size): waiter.resume(returning: size)
    case let .failure(error): waiter.resume(throwing: error)
    }
  }

  /// A session that has been invalidated owns nothing any more: every task it was
  /// running is gone, and a waiter left behind would freeze the queue for the rest
  /// of the process's life, because nothing else ever settles it. Answer them all
  /// now, then build a fresh session so the next hand-over has somewhere to go.
  func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
    BackgroundJournal.shared.record(
      "transfer session invalidated: \(error?.localizedDescription ?? "no reason given")"
    )
    let reason = error ?? URLError(.cancelled)
    lock.lock()
    let pending = waiters
    waiters.removeAll()
    inFlight.removeAll()
    transfers.removeAll()
    lock.unlock()
    for (_, waiter) in pending { waiter.resume(throwing: reason) }
    guard self.session === session else { return }
    self.session = Self.makeSession(delegate: self)
  }
}
