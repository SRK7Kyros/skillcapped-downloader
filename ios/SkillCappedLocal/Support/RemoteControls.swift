import MediaPlayer
import UIKit

/// What the Lock Screen and Control Center show for the lesson that is playing.
struct NowPlayingInfo {
  let title: String
  let artist: String
  /// The quality badge the player's header shows, when the file has one.
  let album: String?
  let duration: Double
  let position: Double
  let rate: Float
  let playing: Bool

  /// The dictionary `MPNowPlayingInfoCenter` reads.
  ///
  /// A paused picture reports a playback rate of zero, which is what stops the
  /// Lock Screen's clock where it is, while `defaultPlaybackRate` keeps the speed
  /// the person chose for when it starts again.
  var dictionary: [String: Any] {
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: artist,
      MPNowPlayingInfoPropertyMediaType: Int(MPNowPlayingInfoMediaType.video.rawValue),
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position.isFinite ? max(position, 0) : 0,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(rate) : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
    ]
    if let album, !album.isEmpty {
      info[MPMediaItemPropertyAlbumTitle] = album
    }
    if duration.isFinite, duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    return info
  }
}

/// The buttons the Lock Screen, Control Center, a headset cable and AirPods press
/// — the other half of "the video really is the thing playing".
///
/// Without this the picture was invisible to the system: Control Center showed
/// whatever had been playing before it, and its transport could not reach the
/// lesson. Every handler is a closure the player fills in, so the remote side
/// drives the same functions the on-screen chrome does.
@MainActor
final class RemoteControls {
  var onPlay: (() -> Void)?
  var onPause: (() -> Void)?
  var onToggle: (() -> Void)?
  var onSkip: ((Double) -> Void)?
  var onSeek: ((Double) -> Void)?
  var onNext: (() -> Void)?
  var onPrevious: (() -> Void)?

  /// Whether the queue has a neighbour in each direction, which is what makes the
  /// Lock Screen's track buttons live or greyed out.
  var canStepBack = false
  var canStepForward = false

  private let center = MPRemoteCommandCenter.shared()
  private var connected = false

  /// Takes the transport commands while a lesson is on screen. Called once when
  /// the player opens; a second call does nothing a second time.
  func connect() {
    guard !connected else { return }
    connected = true
    UIApplication.shared.beginReceivingRemoteControlEvents()
    let center = self.center

    center.playCommand.addTarget { [weak self] _ in
      Self.forward(\.onPlay, from: self)
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Self.forward(\.onPause, from: self)
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Self.forward(\.onToggle, from: self)
    }
    center.skipForwardCommand.addTarget { [weak self] _ in
      Self.forward(from: self) { $0.onSkip?(10) }
    }
    center.skipBackwardCommand.addTarget { [weak self] _ in
      Self.forward(from: self) { $0.onSkip?(-10) }
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      let target = event.positionTime
      return Self.forward(from: self) { $0.onSeek?(target) }
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      Self.forward(from: self) { $0.onNext?() }
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      Self.forward(from: self) { $0.onPrevious?() }
    }
    refresh()
  }

  /// Gives the remote commands back and takes the lesson out of Control Center,
  /// which is also what lets the app go when the player closes: the handlers hold
  /// the view they drive.
  func detach() {
    guard connected else { return }
    connected = false
    for command in [
      center.playCommand,
      center.pauseCommand,
      center.togglePlayPauseCommand,
      center.skipForwardCommand,
      center.skipBackwardCommand,
      center.changePlaybackPositionCommand,
      center.nextTrackCommand,
      center.previousTrackCommand,
    ] {
      command.removeTarget(nil)
      command.isEnabled = false
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
    UIApplication.shared.endReceivingRemoteControlEvents()

    onPlay = nil
    onPause = nil
    onToggle = nil
    onSkip = nil
    onSeek = nil
    onNext = nil
    onPrevious = nil
  }

  /// What Control Center shows now, and which of its buttons are live.
  func show(_ info: NowPlayingInfo, artwork: UIImage? = nil) {
    var dictionary = info.dictionary
    if let artwork, artwork.size.width > 0, artwork.size.height > 0 {
      dictionary[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = dictionary
    MPNowPlayingInfoCenter.default().playbackState = info.playing ? .playing : .paused
    refresh()
  }

  /// Steps are offered only where the queue has a neighbour; skipping only once
  /// the player has a handler for it.
  func refresh() {
    center.playCommand.isEnabled = onPlay != nil
    center.pauseCommand.isEnabled = onPause != nil
    center.togglePlayPauseCommand.isEnabled = onToggle != nil
    center.skipForwardCommand.isEnabled = onSkip != nil
    center.skipBackwardCommand.isEnabled = onSkip != nil
    center.skipForwardCommand.preferredIntervals = [10]
    center.skipBackwardCommand.preferredIntervals = [10]
    center.changePlaybackPositionCommand.isEnabled = onSeek != nil
    center.nextTrackCommand.isEnabled = canStepForward && onNext != nil
    center.previousTrackCommand.isEnabled = canStepBack && onPrevious != nil
  }

  /// A handler runs on whatever thread the system picked; the player's state is
  /// main-actor, so the work hops there and the command answers at once.
  private static func forward(
    from remote: RemoteControls?,
    _ action: @escaping @MainActor (RemoteControls) -> Void
  ) -> MPRemoteCommandHandlerStatus {
    guard let remote else { return .commandFailed }
    Task { @MainActor in action(remote) }
    return .success
  }

  private static func forward(
    _ path: KeyPath<RemoteControls, (() -> Void)?>,
    from remote: RemoteControls?
  ) -> MPRemoteCommandHandlerStatus {
    guard let remote else { return .commandFailed }
    Task { @MainActor in remote[keyPath: path]?() }
    return .success
  }
}
