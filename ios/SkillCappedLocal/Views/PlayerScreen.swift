import AVKit
import Combine
import SwiftUI

struct PlayerScreen: View {
  let lesson: Lesson

  @Environment(\.dismiss) private var dismiss
  @State private var player: AVPlayer?
  @State private var waitingForCloud = false
  @State private var failure: String?
  @State private var preparing: Task<Void, Never>?

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if let player {
        VideoSurface(player: player)
          .ignoresSafeArea()
      } else if let failure {
        Text(failure)
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.85))
          .multilineTextAlignment(.center)
          .padding(28)
      } else {
        VStack(spacing: 10) {
          ProgressView()
            .tint(.white)
          if waitingForCloud {
            Text("Downloading from iCloud…")
              .font(.footnote)
              .foregroundStyle(.white.opacity(0.75))
          }
        }
      }

      VStack {
        HStack {
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(.white)
              .padding(11)
              .background(.black.opacity(0.55), in: Circle())
              .overlay { Circle().stroke(Color.white.opacity(0.15), lineWidth: 1) }
          }
          .padding(.trailing, 16)
          .padding(.top, 8)
        }
        Spacer()
      }
    }
    .statusBarHidden()
    .onAppear(perform: start)
    .onDisappear(perform: stop)
    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
      Playback.clear(for: lesson)
    }
  }

  /// A lesson in iCloud Drive may still be a placeholder, which `AVPlayer` cannot
  /// open: ask iCloud for it and play as soon as the bytes land.
  private func start() {
    guard player == nil, preparing == nil else { return }
    guard CloudFile.needsDownload(lesson.url) else {
      attach()
      return
    }
    waitingForCloud = true
    preparing = Task {
      let ready = await CloudFile.waitUntilLocal(lesson.url)
      await MainActor.run {
        preparing = nil
        waitingForCloud = false
        if ready {
          attach()
        } else {
          failure = "That lesson could not be downloaded from iCloud. Open it in Files once, then try again."
        }
      }
    }
  }

  private func attach() {
    guard player == nil else { return }
    let item = AVPlayerItem(url: lesson.url)
    let player = AVPlayer(playerItem: item)
    player.allowsExternalPlayback = true

    let resume = Playback.saved(lesson)
    if resume > 5 {
      player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
    }
    player.play()
    self.player = player
  }

  private func stop() {
    preparing?.cancel()
    preparing = nil
    guard let player else { return }
    Playback.save(player.currentTime().seconds, for: lesson)
    player.pause()
    self.player = nil
  }
}

private struct VideoSurface: UIViewControllerRepresentable {
  let player: AVPlayer

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.player = player
    controller.showsPlaybackControls = true
    controller.allowsPictureInPicturePlayback = true
    controller.entersFullScreenWhenPlaybackBegins = false
    controller.exitsFullScreenWhenPlaybackEnds = true
    return controller
  }

  func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
    if controller.player !== player {
      controller.player = player
    }
  }
}
