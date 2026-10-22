import UIKit
import XCTest
@testable import SkillCappedLocal

final class FolderPickerTests: XCTestCase {
  private let start = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

  func testTheFolderPickerBuilds() {
    switch FolderAccess.picker(startingAt: start) {
    case let .ready(controller):
      XCTAssertTrue(
        controller.allowsMultipleSelection,
        "a folder is selectable only while multiple selection is on, and the folder-only presentation is refused"
      )
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

  /// iOS 26 refuses a folder-only picker whatever `asCopy` says
  /// (`folder import is not supported, use asCopy:false`, raised even though the
  /// call already passes `asCopy:NO`), so the ladder has to ask for a folder
  /// *beside* `UTTypeItem` — LiveContainer's guest-app shim rewrites every request
  /// to `[UTTypeItem, UTTypeFolder]` — with multiple selection on, since a folder is
  /// selectable only while it is. Pinned by name so a return to `[.folder]` cannot
  /// slip back in silently.
  func testTheFirstPickerAsksForAFolderBesideAnItem() {
    let attempts = FolderAccess.survey()
    XCTAssertEqual(attempts.first?.name, "item + folder, multiple, in place")
    XCTAssertEqual(attempts.first?.ok, true, "the first rung must build: \(attempts.first?.detail ?? "no detail")")
  }

  /// The sheet's diagnostics list is the survey, so it has to name every rung.
  func testTheSurveyReportsEverySpellingItTries() {
    let attempts = FolderAccess.survey()
    XCTAssertEqual(attempts.count, 5)
    XCTAssertGreaterThanOrEqual(
      attempts.filter(\.ok).count,
      2,
      "item + folder and folder-only both build in the simulator:\n\(attempts.map { "\($0.name): \($0.ok)" })"
    )
  }
}
