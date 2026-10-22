import UIKit
import XCTest
@testable import SkillCappedLocal

final class FolderPickerTests: XCTestCase {
  func testTheFolderPickerBuilds() {
    switch FolderAccess.picker() {
    case let .ready(controller):
      XCTAssertFalse(controller.allowsMultipleSelection)
    case let .unavailable(reason):
      XCTFail("the system refused the folder picker:\n\(reason)")
    }
  }
}
