import XCTest
@testable import SkillCappedLocal

final class SearchTests: XCTestCase {
  func testAnEmptyQueryMatchesEverything() {
    XCTAssertTrue(Search.matches("Wave control", query: ""))
    XCTAssertTrue(Search.matches("Wave control", query: "   "))
  }

  func testEveryWordHasToAppear() {
    XCTAssertTrue(Search.matches("Wave control from behind", query: "wave behind"))
    XCTAssertFalse(Search.matches("Wave control from behind", query: "wave recall"))
  }

  func testCasingIsIgnored() {
    XCTAssertTrue(Search.matches("Wave Control (ADC)", query: "wave adc"))
  }

  func testAccentsAreIgnored() {
    XCTAssertTrue(Search.matches("Pokémon spacing", query: "pokemon"))
    XCTAssertTrue(Search.matches("Pokemon spacing", query: "pokémon"))
  }

  func testAPartialWordMatches() {
    XCTAssertTrue(Search.matches("Wave control", query: "wav"))
  }

  func testAMisspellingDoesNotMatch() {
    XCTAssertFalse(Search.matches("Wave control", query: "wavvve"))
  }
}
