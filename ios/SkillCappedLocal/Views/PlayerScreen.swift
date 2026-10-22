import AVFoundation
import AVKit
import Combine
import SwiftUI
import UIKit

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
  @State private var drag: Drag?
  @StateObject private var pictureInPicture = PictureInPicture()

  /// What a drag is doing, fixed at the first movement so a gesture that starts
  /// across the screen cannot become a brightness change halfway.
  private enum Drag: Equatable {
    case seek(from: Double)
    case brightness(from: Double)
    case volume(from: Double)
  }

  private static let rates: [Float] = [1, 1.25, 1.5, 2]

  init(lesson: Lesson) {
    self.lesson = lesson
    _current = State(initialValue: lesson)
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black

        if let player {
          PlayerSurface(player: player, pictureInPicture: pictureInPicture)
        }

        gestures(size: proxy.size)

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
            close: { dismiss() },
            togglePlay: { togglePlay() },
            skip: { skip($0) },
            step: { step($0) },
            scrub: { position = $0 },
            commit: { commit($0) },
            changeRate: cycleRate,
            togglePictureInPicture: { pictureInPicture.toggle() }
          )
          .transition(.opacity)
        }
      }
      .ignoresSafeArea()
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
  /// level. Exclusive taps, not two recognisers: with two, the first tap of a
  /// double tap toggles the chrome as well.
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
              withAnimation(.easeInOut(duration: 0.2)) { chrome.toggle() }
              if chrome { showChrome() }
            }
          }
      )
      .simultaneousGesture(dragGesture(size: size))
  }

  private func dragGesture(size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        if drag == nil {
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

        case .none:
          break
        }
      }
      .onEnded { value in
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
    load(current)
    showChrome()
  }

  private func load(_ lesson: Lesson) {
    preparing?.cancel()
    tearDown()
    failure = nil
    current = lesson
    position = 0
    duration = Double(max(lesson.seconds, 0))

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
        if !isSeeking, seconds.isFinite { position = seconds }
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
    showChrome()
  }

  private var isSeeking: Bool {
    if case .seek? = drag { return true }
    return false
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
  }

  private func skip(_ seconds: Double) {
    guard duration > 0 else { return }
    seek(to: PlayerMath.clamp(position + seconds, 0, duration))
    showChrome()
  }

  private func seek(to seconds: Double) {
    guard let player, duration > 0 else { return }
    let target = PlayerMath.clamp(seconds, 0, duration)
    player.seek(
      to: CMTime(seconds: target, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    )
    position = target
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
    if let player, player.rate > 0 { player.rate = rate }
    showChrome()
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
    chromeTask?.cancel()
    hudTask?.cancel()
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
      guard !Task.isCancelled, playing, drag == nil else { return }
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

/// The transport: a title bar, a scrubber, and the row of buttons under it.
private struct Chrome: View {
  let lesson: Lesson
  let playing: Bool
  let position: Double
  let duration: Double
  let rate: Float
  let canStepBack: Bool
  let canStepForward: Bool
  let pictureInPicture: Bool

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
      top

      Spacer(minLength: 0)

      bottom
    }
    .background(
      LinearGradient(
        colors: [.black.opacity(0.62), .clear, .clear, .black.opacity(0.78)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)
    )
  }

  private var top: some View {
    HStack(alignment: .top, spacing: 12) {
      PlayerButton(glyph: "xmark", size: 15, label: "Close", action: close)

      VStack(alignment: .leading, spacing: 2) {
        Text(lesson.title)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(2)
        if let quality = lesson.quality, !quality.isEmpty {
          Text(quality)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white.opacity(0.65))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 4)

      if pictureInPicture {
        PlayerButton(glyph: "pip.enter", size: 15, label: "Picture in picture", action: togglePictureInPicture)
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
  }

  private var bottom: some View {
    VStack(spacing: 2) {
      PlayerScrubber(
        position: position,
        duration: duration,
        onScrub: scrub,
        onCommit: commit
      )

      HStack(spacing: 0) {
        Text(PlayerMath.clock(position))
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(duration > 0 ? "−\(PlayerMath.clock(max(duration - position, 0)))" : "--:--")
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
      .foregroundStyle(.white.opacity(0.72))
      .padding(.horizontal, 4)

      HStack(spacing: 0) {
        PlayerButton(
          glyph: "backward.end.fill",
          size: 17,
          disabled: !canStepBack,
          label: "Previous lesson"
        ) { step(false) }

        Spacer(minLength: 0)

        PlayerButton(glyph: "gobackward.10", size: 22, label: "Back 10 seconds") { skip(-10) }

        Button(action: togglePlay) {
          Image(systemName: playing ? "pause.fill" : "play.fill")
            .font(.system(size: 25, weight: .bold))
            .foregroundStyle(Palette.bg)
            .frame(width: 62, height: 62)
            .background(Palette.brand, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "Pause" : "Play")
        .padding(.horizontal, 18)

        PlayerButton(glyph: "goforward.10", size: 22, label: "Forward 10 seconds") { skip(10) }

        Spacer(minLength: 0)

        Button(action: changeRate) {
          Text(rate == 1 ? "1×" : String(format: "%g×", rate))
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(rate == 1 ? 0.7 : 1))
            .frame(width: 46, height: 32)
            .background(
              Capsule().fill(.white.opacity(rate == 1 ? 0.08 : 0.18))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Playback speed, \(rate == 1 ? "normal" : String(format: "%g", rate) + " times")")
      }
      .padding(.horizontal, 8)
    }
    .padding(.bottom, 6)
  }
}
