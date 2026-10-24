import AVFoundation
import XCTest
@testable import SkillCappedLocal

final class AudioSessionTests: XCTestCase {
  override func tearDown() {
    AudioSession.deactivate()
    super.tearDown()
  }

  func testThePlayerAsksForPlaybackSound() {
    XCTAssertEqual(AudioSession.category, .playback)
    XCTAssertEqual(AudioSession.mode, .moviePlayback)
  }

  func testActivatingTakesThePlaybackCategorySoTheRingerSwitchCannotSilenceALesson() {
    AudioSession.activate()

    let session = AVAudioSession.sharedInstance()
    XCTAssertEqual(session.category, .playback, "the ringer switch should not be able to silence a lesson")
    XCTAssertEqual(session.mode, .moviePlayback)
  }

  func testTheSoundMayLeaveThePhone() {
    XCTAssertTrue(
      AudioSession.options.contains(.allowAirPlay),
      "a lesson has to be able to go to an AirPlay screen or speaker"
    )
    XCTAssertTrue(
      AudioSession.options.contains(.allowBluetoothA2DP),
      "and to Bluetooth headphones in their stereo profile"
    )
  }
}
