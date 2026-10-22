import UIKit
import XCTest
@testable import SkillCappedLocal

final class FolderPickerTests: XCTestCase {
  private let start = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

  func testTheFolderPickerBuilds() {
    switch FolderAccess.picker(startingAt: start) {
    case let .ready(controller):
      XCTAssertFalse(controller.allowsMultipleSelection)
    case let .unavailable(reason):
      XCTFail("the system refused the folder picker:\n\(reason)")
    }
  }

  /// A picker left on its default root can keep Files' Open button disabled, so
  /// it must be handed a directory the user can actually select from.
  func testTheFolderPickerOpensInTheGivenDirectory() {
    switch FolderAccess.picker(startingAt: start) {
    case let .ready(controller):
      XCTAssertEqual(controller.directoryURL?.standardizedFileURL.path, start.standardizedFileURL.path)
    case let .unavailable(reason):
      XCTFail("the system refused the folder picker:\n\(reason)")
    }
  }
}
