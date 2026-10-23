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
}
