import MediaPlayer
import XCTest
@testable import SkillCappedLocal

final class NowPlayingInfoTests: XCTestCase {
  private func info(
    album: String? = "1080p",
    duration: Double = 600,
    position: Double = 90,
    rate: Float = 1.5,
    playing: Bool = true
  ) -> NowPlayingInfo {
    NowPlayingInfo(
      title: "Wave management",
      artist: "ADC",
      album: album,
      duration: duration,
      position: position,
      rate: rate,
      playing: playing
    )
  }

  func testTheLessonIsWhatControlCenterNames() {
    let dictionary = info().dictionary
    XCTAssertEqual(dictionary[MPMediaItemPropertyTitle] as? String, "Wave management")
    XCTAssertEqual(dictionary[MPMediaItemPropertyArtist] as? String, "ADC")
    XCTAssertEqual(dictionary[MPMediaItemPropertyAlbumTitle] as? String, "1080p")
    XCTAssertEqual(dictionary[MPMediaItemPropertyPlaybackDuration] as? Double, 600)
    XCTAssertEqual(dictionary[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 90)
    XCTAssertEqual(
      dictionary[MPNowPlayingInfoPropertyMediaType] as? Int,
      Int(MPNowPlayingInfoMediaType.video.rawValue),
      "the system lists it as video, which is what gives it a picture surface"
    )
  }

  func testAPlayingLessonReportsItsSpeed() {
    let dictionary = info().dictionary
    XCTAssertEqual(dictionary[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.5)
    XCTAssertEqual(dictionary[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? Double, 1.5)
  }

  func testAPausedLessonStopsTheClockWithoutForgettingItsSpeed() {
    let dictionary = info(playing: false).dictionary
    XCTAssertEqual(dictionary[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
    XCTAssertEqual(dictionary[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? Double, 1.5)
  }

  func testAQualityTheFileDoesNotHaveIsLeftOut() {
    XCTAssertNil(info(album: nil).dictionary[MPMediaItemPropertyAlbumTitle])
    XCTAssertNil(info(album: "").dictionary[MPMediaItemPropertyAlbumTitle])
  }

  func testALessonOfUnknownLengthReportsNone() {
    XCTAssertNil(info(duration: 0).dictionary[MPMediaItemPropertyPlaybackDuration])
    XCTAssertNil(info(duration: .nan).dictionary[MPMediaItemPropertyPlaybackDuration])
  }

  func testAPositionThePlayerCannotNameStartsAtZero() {
    XCTAssertEqual(
      info(position: .nan).dictionary[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double,
      0
    )
    XCTAssertEqual(
      info(position: -12).dictionary[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double,
      0
    )
  }
}
