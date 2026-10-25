import AVFoundation
import AVKit
import Combine
import SwiftUI

/// The player, with chrome of our own instead of `AVPlayerViewController`'s.
///
/// The system controller draws its own transport over the video and cannot be
/// extended, so a lesson could not show what a phone player shows: double tap a
/// side to skip, drag across to scrub, drag up the left half for brightness and
/// the right half for the sound. The surface underneath is still the platform's
/// — an `AVPlayerLayer` — so picture in picture, AirPlay and hardware decoding
/// are all still there.
@MainActor
struct PlayerScreen: View {
  let lesson: Lesson

  @EnvironmentObject private var coordinator: PlayerCoordinator
  @EnvironmentObject private var progress: ProgressStore
  @Environment(\.dismiss) private var dismiss

  /// The lesson on screen, which is not always the one the cover was opened
  /// with: the transport steps through the queue it was opened from.
  @State private var current: Lesson

  @State private var player: AVPlayer?
  @State private var playing = false
  @State private var stalled = false
  @State private var position: Double = 0
  /// Whether the bar follows the player's clock or stands on a position the
  /// user picked, which it does until the picture catches up with them.
  @State private var hold = PlayheadHold()
  @State private var duration: Double = 0
  @State private var rate: Float = 1
  @State private var waitingForCloud = false
  @State private var failure: String?
  @State private var preparing: Task<Void, Never>?
  @State private var ticker: Any?
  @State private var recorder: Any?

  @State private var chrome = true
  @State private var chromeTask: Task<Void, Never>?
  @State private var hud: PlayerHUD?
  @State private var hudTask: Task<Void, Never>?
  @State private var burst = SkipBurst()
  @State private var speed = HoldToSpeed()
  @State private var pressed = false
  @State private var drag: Drag?
  @StateObject private var pictureInPicture = PictureInPicture()

  @State private var zoom: CGFloat = PlayerZoom.minScale
  @State private var zoomOffset: CGSize = .zero
  @State private var zoomBase: CGFloat?
  @State private var zoomBaseOffset: CGSize = .zero
  @State private var zooming = false

  @StateObject private var keeper = OrientationKeeper()
  @State private var remote = RemoteControls()
  @State private var artwork: UIImage?

  /// What a drag is doing, fixed at the first movement so a gesture that starts
  /// across the screen cannot become a brightness change halfway. A zoomed
  /// picture pans instead of scrubbing, the way a photograph does.
  private enum Drag: Equatable {
    case seek(from: Double)
    case brightness(from: Double)
    case volume(from: Double)
    case pan(from: CGSize)
  }

  private static let rates: [Float] = [1, 1.25, 1.5, 2]
  /// How long a finger has to rest on the picture before it plays at double
  /// speed. Short enough to feel like a gesture, long enough that a slow tap is
  /// still a tap.
  private static let holdToSpeedAfter: TimeInterval = 0.4

  init(lesson: Lesson) {
    self.lesson = lesson
    _current = State(initialValue: lesson)
  }

  var body: some View {
    GeometryReader { proxy in
      let turn = PlayerOrientation.turn(device: keeper.device, window: proxy.size)
      let size = turn.isTurned
        ? CGSize(width: proxy.size.height, height: proxy.size.width)
        : proxy.size

      stage(size: size, insets: PlayerOrientation.insets(proxy.safeAreaInsets, turned: turn))
        .frame(width: size.width, height: size.height)
        .rotationEffect(turn.angle)
        .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .background(Color.black.ignoresSafeArea())
    .statusBarHidden()
    .onAppear(perform: begin)
    .onDisappear(perform: finish)
    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
      guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
      completed()
    }
  }

  /// The picture and everything over it, at the size it is seen at — which is the
  /// window's own size unless the phone is on its side with the window held
  /// portrait, in which case the whole stage is turned and the two are swapped.
  private func stage(size: CGSize, insets: EdgeInsets) -> some View {
    ZStack {
      Color.black

      if let player {
        PlayerSurface(player: player, pictureInPicture: pictureInPicture)
          .scaleEffect(zoom)
          .offset(zoomOffset)
      }

      gestures(size: size)

      if let failure {
        message(failure)
      } else if player == nil {
        loading(waitingForCloud ? "Downloading from iCloud…" : "Opening…")
      }

      if stalled && player != nil {
        ProgressView()
          .controlSize(.large)
          .tint(.white)
      }

      if let hud {
        PlayerHUDView(hud: hud)
          .transition(.opacity.combined(with: .scale(scale: 0.94)))
          .allowsHitTesting(false)
      }

      if chrome, player != nil {
        Chrome(
          lesson: current,
          playing: playing,
          position: position,
          duration: duration,
          rate: rate,
          canStepBack: coordinator.neighbour(of: current, forward: false) != nil,
          canStepForward: coordinator.neighbour(of: current, forward: true) != nil,
          pictureInPicture: pictureInPicture.available,
          window: size,
          insets: insets,
          close: { dismiss() },
          togglePlay: { togglePlay() },
          skip: { skip($0) },
          step: { step($0) },
          scrub: { hold.choose(); position = $0 },
          commit: { commit($0) },
          changeRate: cycleRate,
          togglePictureInPicture: { pictureInPicture.toggle() }
        )
        .transition(.opacity)
      }
    }
    .ignoresSafeArea()
  }

  // MARK: - Pieces

  private func loading(_ text: String) -> some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)
        .tint(.white)
      Text(text)
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.75))
    }
  }

  private func message(_ text: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.title)
        .foregroundStyle(Palette.warn)
      Text(text)
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.85))
        .multilineTextAlignment(.center)
      Button("Close") { dismiss() }
        .buttonStyle(.borderedProminent)
        .tint(Palette.brand)
        .foregroundStyle(Palette.bg)
    }
    .padding(28)
  }

  /// One tap toggles the chrome, two on a side skip, a drag scrubs or moves a
  /// level, a hold plays at double speed. Exclusive taps, not two recognisers:
  /// with two, the first tap of a double tap toggles the chrome as well.
  private func gestures(size: CGSize) -> some View {
    Color.clear
      .contentShape(Rectangle())
      .gesture(
        SpatialTapGesture(count: 2)
          .exclusively(before: SpatialTapGesture(count: 1))
          .onEnded { result in
            switch result {
            case let .first(value):
              let backward = value.location.x < size.width / 2
              let seconds = burst.tap(backward: backward, at: Date())
              skip(seconds)
              show(.skip(seconds))
            case .second:
              drag = nil
              zooming = false
              withAnimation(.easeInOut(duration: 0.2)) { chrome.toggle() }
              if chrome { showChrome() }
            }
          }
      )
      .onLongPressGesture(
        minimumDuration: Self.holdToSpeedAfter,
        maximumDistance: 22,
        pressing: { down in
          // A press that ends without reaching the duration never sped anything
          // up, and a hold that is dragged away is cancelled rather than ended —
          // both arrive here as the press letting go.
          pressed = down
          if !down { endHold() }
        },
        perform: { beginHold() }
      )
      .simultaneousGesture(dragGesture(size: size))
      .simultaneousGesture(magnifyGesture(size: size))
  }

  /// Pinching grows the picture around the fingers rather than the middle of the
  /// screen (`PlayerZoom`), which is what makes it possible to look at a corner
  /// of a lesson's UI. A pinch below fit springs back to fit.
  private func magnifyGesture(size: CGSize) -> some Gesture {
    MagnifyGesture(minimumScaleDelta: 0.01)
      .onChanged { value in
        let base = zoomBase ?? zoom
        if zoomBase == nil {
          zoomBase = base
          zoomBaseOffset = zoomOffset
          zooming = true
          showChrome()
        }
        let next = PlayerZoom.clampScale(base * value.magnification)
        zoom = next
        zoomOffset = PlayerZoom.offset(
          starting: zoomBaseOffset,
          from: base,
          to: next,
          anchor: value.startAnchor,
          size: size
        )
      }
      .onEnded { _ in
        zoomBase = nil
        if zoom <= PlayerZoom.minScale + 0.02 {
          withAnimation(.easeOut(duration: 0.22)) {
            zoom = PlayerZoom.minScale
            zoomOffset = .zero
          }
        }
        // The two fingers of a pinch also arrive as a drag; the flag keeps that
        // drag from turning the pinch into a seek.
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 150_000_000)
          zooming = false
        }
        showChrome()
      }
  }

  private func dragGesture(size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        guard !zooming else { return }
        if drag == nil {
          // A finger that starts moving is scrubbing or changing a level, not
          // holding for speed, even when the hold had already begun.
          endHold()
          drag = startDrag(value, size: size)
          showChrome()
        }
        switch drag {
        case let .seek(from)?:
          let target = PlayerMath.seek(
            from: from,
            translation: value.translation.width,
            width: size.width,
            duration: duration
          )
          hold.choose()
          position = target
          show(.time(target))

        case let .brightness(from)?:
          let level = PlayerMath.level(
            from: from,
            translation: value.translation.height,
            height: size.height
          )
          UIScreen.main.brightness = CGFloat(level)
          show(.brightness(level))

        case let .volume(from)?:
          let level = PlayerMath.level(
            from: from,
            translation: value.translation.height,
            height: size.height
          )
          SystemVolume.set(Float(level))
          show(.volume(level))

        case let .pan(from)?:
          zoomOffset = PlayerZoom.clamped(
            CGSize(
              width: from.width + value.translation.width,
              height: from.height + value.translation.height
            ),
            scale: zoom,
            size: size
          )

        case .none:
          break
        }
      }
      .onEnded { value in
        guard !zooming else {
          drag = nil
          return
        }
        if case let .seek(from)? = drag {
          let target = PlayerMath.seek(
            from: from,
            translation: value.translation.width,
            width: size.width,
            duration: duration
          )
          seek(to: target)
        }
        drag = nil
        hideHUD()
        showChrome()
      }
  }

  private func startDrag(_ value: DragGesture.Value, size: CGSize) -> Drag {
    if zoom > PlayerZoom.minScale + 0.01 { return .pan(from: zoomOffset) }
    let across = abs(value.translation.width) > abs(value.translation.height)
    if across { return .seek(from: position) }
    let channel = PlayerMath.channel(x: value.startLocation.x, width: size.width)
    switch channel {
    case .brightness: return .brightness(from: Double(UIScreen.main.brightness))
    case .volume: return .volume(from: Double(SystemVolume.level))
    }
  }

  // MARK: - Playback

  /// A lesson in iCloud Drive may still be a placeholder, which `AVPlayer` cannot
  /// open: ask iCloud for it and play as soon as the bytes land.
  private func begin() {
    AudioSession.activate()
    keeper.start()
    connectRemote()
    load(current)
    showChrome()
  }

  /// The Lock Screen's buttons drive the same functions the chrome does.
  private func connectRemote() {
    remote.onPlay = { if let player = self.player, player.rate == 0 { togglePlay() } }
    remote.onPause = { if let player = self.player, player.rate > 0 { togglePlay() } }
    remote.onToggle = { togglePlay() }
    remote.onSkip = { skip($0) }
    remote.onSeek = { seek(to: $0) }
    remote.onNext = { step(true) }
    remote.onPrevious = { step(false) }
    remote.connect()
  }

  /// What Control Center, the Lock Screen and AirPlay show for the lesson.
  ///
  /// Written on every state change rather than on a clock: the system advances
  /// the clock itself from the rate we report, so a frame per second would only
  /// pour writes into it.
  private func updateNowPlaying() {
    guard player != nil else { return }
    remote.canStepBack = coordinator.neighbour(of: current, forward: false) != nil
    remote.canStepForward = coordinator.neighbour(of: current, forward: true) != nil
    remote.show(
      NowPlayingInfo(
        title: current.title,
        artist: current.role,
        album: current.quality,
        duration: duration,
        position: position,
        rate: liveRate,
        playing: playing
      ),
      artwork: artwork
    )
  }

  /// The picture Control Center draws, from the site's poster and then from a
  /// frame of the lesson, which is the only art a library scanned offline has.
  private func loadArtwork() {
    let lesson = current
    artwork = nil
    Task { @MainActor in
      var image: UIImage?
      if let url = lesson.posterURL {
        image = await RemoteArtStore.shared.image(for: url)
      }
      if image == nil {
        image = await PosterStore.shared.poster(for: lesson.url, width: 600)
      }
      guard !Task.isCancelled, current.id == lesson.id else { return }
      artwork = image
      updateNowPlaying()
    }
  }

  private func load(_ lesson: Lesson) {
    preparing?.cancel()
    tearDown()
    failure = nil
    current = lesson
    position = 0
    hold = PlayheadHold()
    duration = Double(max(lesson.seconds, 0))
    zoom = PlayerZoom.minScale
    zoomOffset = .zero
    zoomBase = nil
    zooming = false
    burst.reset()
    speed = HoldToSpeed()
    drag = nil
    loadArtwork()

    let download = CloudFile.needsDownload(lesson.url)
    waitingForCloud = download
    preparing = Task { @MainActor in
      if download {
        let ready = await CloudFile.waitUntilLocal(lesson.url)
        waitingForCloud = false
        guard ready else {
          preparing = nil
          failure = "That lesson could not be downloaded from iCloud. Open it in Files once, then try again."
          return
        }
      }
      let item = await LessonMedia.item(url: lesson.url, seconds: lesson.seconds)
      guard !Task.isCancelled else { return }
      attach(item)
      preparing = nil
    }
  }

  private func attach(_ item: AVPlayerItem) {
    let player = AVPlayer(playerItem: item)
    player.allowsExternalPlayback = true

    let saved = progress.progress(for: current.progressKey)
    if let saved, WatchProgressMath.shouldResume(position: saved.position, duration: saved.duration) {
      player.seek(to: CMTime(seconds: saved.position, preferredTimescale: 600))
      hold.seek(saved.position)
      position = saved.position
    }

    // The scrubber follows the playhead four times a second; the progress store
    // is written every five, because each write is a file.
    let clock = player
    ticker = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
      queue: .main
    ) { time in
      let seconds = time.seconds
      let total = clock.currentItem?.duration.seconds ?? 0
      let running = clock.rate > 0
      let buffering = clock.timeControlStatus == .waitingToPlayAtSpecifiedRate
      Task { @MainActor in
        if total.isFinite, total > 0 { duration = total }
        if let shown = hold.follow(seconds) { position = shown }
        if playing != running { playing = running }
        if stalled != buffering { stalled = buffering }
      }
    }

    let key = current.progressKey
    let store = progress
    recorder = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 5, preferredTimescale: 600),
      queue: .main
    ) { time in
      let total = clock.currentItem?.duration.seconds ?? 0
      let seconds = time.seconds
      Task { @MainActor in
        store.record(key: key, position: seconds, duration: total.isFinite ? total : 0)
      }
    }

    player.rate = rate
    self.player = player
    playing = true
    updateNowPlaying()
    showChrome()
  }

  private func togglePlay() {
    guard let player else { return }
    showChrome()
    if player.rate > 0 {
      player.rate = 0
      playing = false
    } else {
      player.rate = rate
      playing = true
      hideHUD()
    }
    updateNowPlaying()
  }

  private func skip(_ seconds: Double) {
    guard duration > 0 else { return }
    seek(to: PlayerMath.clamp(position + seconds, 0, duration))
    showChrome()
  }

  private func seek(to seconds: Double) {
    guard let player, duration > 0 else { return }
    let target = PlayerMath.clamp(seconds, 0, duration)
    hold.seek(target)
    player.seek(
      to: CMTime(seconds: target, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    )
    position = target
    releaseHold(target)
    updateNowPlaying()
  }

  /// A seek that never lands would leave the bar standing on a position the
  /// picture is not on, so the hold expires and the clock takes the bar back.
  private func releaseHold(_ target: Double) {
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      hold.expire(target)
      if let now = player?.currentTime().seconds, now.isFinite, hold.follow(now) != nil {
        position = now
      }
    }
  }

  private func commit(_ seconds: Double) {
    seek(to: seconds)
    showChrome()
  }

  private func step(_ forward: Bool) {
    guard let neighbour = coordinator.neighbour(of: current, forward: forward) else { return }
    burst.reset()
    hud = nil
    load(neighbour)
  }

  private func cycleRate() {
    let index = Self.rates.firstIndex(of: rate) ?? 0
    rate = Self.rates[(index + 1) % Self.rates.count]
    if let player, player.rate > 0, !speed.isHolding { player.rate = rate }
    updateNowPlaying()
    showChrome()
  }

  /// The rate the picture is running at, which is double while a finger holds it.
  private var liveRate: Float {
    speed.isHolding ? HoldToSpeed.factor : rate
  }

  private func beginHold() {
    // `perform` can arrive a moment after the finger has already gone; the
    // player must never be left running at double speed with nothing holding it.
    guard pressed, let player, player.currentItem != nil, drag == nil else { return }
    player.rate = speed.begin(from: player.rate)
    playing = true
    show(.speed)
    updateNowPlaying()
  }

  private func endHold() {
    guard let player, let back = speed.end() else { return }
    player.rate = back
    playing = back > 0
    updateNowPlaying()
  }

  private func completed() {
    progress.markCompleted(
      key: current.progressKey,
      duration: duration.isFinite ? duration : 0
    )
    withAnimation(.easeInOut(duration: 0.2)) { chrome = true }
    chromeTask?.cancel()
    if let next = coordinator.neighbour(of: current, forward: true) {
      load(next)
    } else {
      playing = false
      updateNowPlaying()
    }
  }

  private func finish() {
    preparing?.cancel()
    preparing = nil
    if let player {
      progress.record(
        key: current.progressKey,
        position: player.currentTime().seconds,
        duration: player.currentItem?.duration.seconds ?? 0
      )
    }
    tearDown()
    pictureInPicture.detach()
    remote.detach()
    keeper.stop()
    chromeTask?.cancel()
    hudTask?.cancel()
    hud = nil
    AudioSession.deactivate()
  }

  private func tearDown() {
    guard let player else { return }
    if let ticker {
      player.removeTimeObserver(ticker)
      self.ticker = nil
    }
    if let recorder {
      player.removeTimeObserver(recorder)
      self.recorder = nil
    }
    player.pause()
    self.player = nil
    playing = false
    stalled = false
  }

  // MARK: - Chrome

  private func showChrome() {
    if !chrome {
      withAnimation(.easeInOut(duration: 0.2)) { chrome = true }
    }
    chromeTask?.cancel()
    chromeTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      // Only a picture that is really advancing takes the chrome away, and
      // `timeControlStatus` is the platform's own answer to that: `rate` is the
      // rate we asked for, which an item that cannot play keeps at 1 while the
      // screen shows a still frame (the demo library's empty lessons do exactly
      // that, and the transport — the only way to close the player — vanished
      // over it four seconds in).
      guard !Task.isCancelled, drag == nil, player?.timeControlStatus == .playing else { return }
      withAnimation(.easeOut(duration: 0.25)) { chrome = false }
    }
  }

  private func show(_ hud: PlayerHUD) {
    self.hud = hud
    hudTask?.cancel()
    hudTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 900_000_000)
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.18)) { self.hud = nil }
    }
  }

  private func hideHUD() {
    hudTask?.cancel()
    withAnimation(.easeOut(duration: 0.18)) { hud = nil }
  }
}

/// The transport, floating over the picture rather than a drawer over the bottom
/// of it, in the order a thumb expects — skip back, play, skip forward, the
/// timeline, the speed, the queue's neighbours — with the Picture in Picture
/// switch alone in the screen's top-right corner, where it no longer competes
/// with the controls that are touched every few seconds.
///
/// It has two shapes. A wide window holds all of it in one row. A portrait phone
/// cannot, so the rate and the two queue steps float above the bar as their own
/// buttons, and the bar keeps the three controls a thumb reaches for plus a
/// timeline wide enough for both readouts (`PlayerChromeLayout`).
@MainActor
private struct Chrome: View {
  let lesson: Lesson
  let playing: Bool
  let position: Double
  let duration: Double
  let rate: Float
  let canStepBack: Bool
  let canStepForward: Bool
  let pictureInPicture: Bool

  /// The window the chrome is drawn in and the safe area it has to clear. Both
  /// come from the layout rather than from the window: the picture runs through
  /// the safe area, so the chrome needs the insets itself, and the layout is
  /// re-run when the phone turns — which a UIKit read inside a body is not.
  let window: CGSize
  let insets: EdgeInsets

  let close: () -> Void
  let togglePlay: () -> Void
  let skip: (Double) -> Void
  let step: (Bool) -> Void
  let scrub: (Double) -> Void
  let commit: (Double) -> Void
  let changeRate: () -> Void
  let togglePictureInPicture: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, headerSide)
        .padding(.top, topMargin)

      Spacer(minLength: 0)

      VStack(alignment: .trailing, spacing: 10) {
        if floatsControls {
          floating
        }
        bar
      }
      .padding(.horizontal, barSide)
      .padding(.bottom, bottomMargin)
    }
  }

  private var floatsControls: Bool {
    PlayerChromeLayout.floatsControls(width: window.width)
  }

  /// The display's own corner, which every margin here is measured against.
  private var corner: CGFloat { DisplayCorner.current }

  /// Where the header and the bar sit from the edge they are nearest. The top and
  /// bottom insets carry the island, the status bar and the home indicator; the
  /// leads and trails are deliberately unused — the island sits halfway along a
  /// side, so it is not in the way of a row that runs along an edge, and adding
  /// its inset to both sides is what emptied the corners.
  private var topMargin: CGFloat { PlayerChromeLayout.away(safe: insets.top) }
  private var bottomMargin: CGFloat { PlayerChromeLayout.away(safe: insets.bottom) }

  /// …and how far each row sits from the glass sideways, which follows the
  /// display's corner at that row's height rather than a flat margin.
  private var headerSide: CGFloat {
    PlayerChromeLayout.side(radius: corner, fromCorner: topMargin)
  }

  private var barSide: CGFloat {
    PlayerChromeLayout.side(radius: corner, fromCorner: bottomMargin)
  }

  private var rateLabel: String {
    rate == 1 ? "1×" : String(format: "%g×", rate)
  }

  private var rateAccessibilityLabel: String {
    "Playback speed, " + (rate == 1 ? "normal" : String(format: "%g", rate) + " times")
  }

  /// Floating too: a close button and the name of the lesson at the left, then
  /// the output switch (AirPlay and the phone's own speaker) and the Picture in
  /// Picture switch in the top-right corner, with the picture still
  /// visible behind them — a full-screen scrim is what made the old chrome read
  /// as a drawer.
  private var header: some View {
    HStack(spacing: 10) {
      Button(action: close) {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 32, height: 32)
          .glass(Circle(), tint: 0.36, rim: 0.5)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Close")

      VStack(alignment: .leading, spacing: 1) {
        Text(lesson.title)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
        if let quality = lesson.quality, !quality.isEmpty {
          Text(quality)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white.opacity(0.7))
        }
      }
      .shadow(color: .black.opacity(0.6), radius: 4, y: 1)

      Spacer(minLength: 0)

      RoutePicker(diameter: 32)
        .frame(width: 32, height: 32)
        .glass(Circle(), tint: 0.36, rim: 0.5)
        .accessibilityLabel("Audio and video output")

      if pictureInPicture {
        Button(action: togglePictureInPicture) {
          Image(systemName: "pip.enter")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .glass(Circle(), tint: 0.36, rim: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Picture in picture")
      }
    }
  }

  /// The three controls a portrait phone cannot fit in the bar, each one its own
  /// round button above it and sitting where it used to be in the row, so the
  /// thumb finds them in the same place it left them.
  private var floating: some View {
    HStack(spacing: 12) {
      floatingButton {
        Button(action: changeRate) {
          Text(rateLabel)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(rate == 1 ? 0.78 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rateAccessibilityLabel)
      }

      floatingButton { previous }
      floatingButton { next }
    }
  }

  private func floatingButton<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .frame(width: 44, height: 44)
      .glass(Circle(), tint: 0.36, rim: 0.46)
  }

  /// One row: every control at the same height, and the timeline the only thing
  /// that stretches. The bar is a capsule, which is the shape the display's own
  /// corner gives a surface this tall on every phone — the two curves share a
  /// centre, so the bar reads as cut from the same glass as the screen.
  private var bar: some View {
    HStack(spacing: 2) {
      PlayerButton(glyph: "gobackward.10", size: 16, label: "Back 10 seconds") { skip(-10) }

      playButton

      PlayerButton(glyph: "goforward.10", size: 16, label: "Forward 10 seconds") { skip(10) }

      timeline

      if !floatsControls {
        rateChip
        previous
        next
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 6)
    .glass(Capsule(), tint: 0.44, rim: 0.46, lift: 0.36)
  }

  private var playButton: some View {
    Button(action: togglePlay) {
      Image(systemName: playing ? "pause.fill" : "play.fill")
        .font(.system(size: 19, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(playing ? "Pause" : "Play")
  }

  private var rateChip: some View {
    Button(action: changeRate) {
      Text(rateLabel)
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .foregroundStyle(.white.opacity(rate == 1 ? 0.75 : 1))
        .frame(width: 34, height: 26)
        .background(Capsule().fill(.white.opacity(rate == 1 ? 0.1 : 0.2)))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(rateAccessibilityLabel)
  }

  private var previous: some View {
    PlayerButton(
      glyph: "backward.end.fill",
      size: 13,
      disabled: !canStepBack,
      label: "Previous lesson"
    ) { step(false) }
  }

  private var next: some View {
    PlayerButton(
      glyph: "forward.end.fill",
      size: 13,
      disabled: !canStepForward,
      label: "Next lesson"
    ) { step(true) }
  }

  /// The track with the elapsed time on its left and the time left on its right.
  private var timeline: some View {
    HStack(spacing: 8) {
      time(PlayerMath.clock(position), width: 38, alignment: .trailing, id: "player.elapsed")

      PlayerScrubber(position: position, duration: duration, onScrub: scrub, onCommit: commit)
        .frame(maxWidth: .infinity)

      time(
        duration > 0 ? "−" + PlayerMath.clock(max(duration - position, 0)) : "--:--",
        width: 44,
        alignment: .leading,
        id: "player.remaining"
      )
    }
  }

  private func time(_ text: String, width: CGFloat, alignment: Alignment, id: String) -> some View {
    Text(text)
      .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
      .foregroundStyle(.white.opacity(0.82))
      .frame(width: width, alignment: alignment)
      .accessibilityIdentifier(id)
  }
}
