import AVKit
import Combine
import SwiftUI

struct PlayerScreen: View {
  let lesson: Lesson

  @Environment(\.dismiss) private var dismiss
  @State private var player: AVPlayer?

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if let player {
        VideoSurface(player: player)
          .ignoresSafeArea()
      } else {
        ProgressView()
          .tint(.white)
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

  private func start() {
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
