import XCTest
@testable import SkillCappedLocal

final class QualityPlanTests: XCTestCase {
  func testLadderLeadsWithTheRequestedRendition() {
    let ladder = QualityPlan.ladder(requested: "720p", priority: ["1080p", "720p"], available: [])
    XCTAssertEqual(Array(ladder.prefix(3)), ["720p", "1080p", "2160p"])
  }

  func testLadderDeduplicatesWhateverTheCasing() {
    let ladder = QualityPlan.ladder(requested: "1080p", priority: ["1080P"], available: ["1080p"])
    XCTAssertEqual(ladder.filter { $0.lowercased() == "1080p" }.count, 1)
  }

  func testLadderFallsBackThroughEveryKnownTier() {
    let ladder = QualityPlan.ladder(requested: nil, priority: [], available: [])
    XCTAssertEqual(ladder, ["2160p", "1080p", "720p"])
  }

  func testLadderOffersWhatTheCdnHasBeforeWhatItMerelyKnows() {
    let ladder = QualityPlan.ladder(requested: nil, priority: [], available: ["1440p"])
    XCTAssertEqual(ladder, ["1440p", "2160p", "1080p", "720p"])
  }

  func testPickFollowsThePriorityOrderRatherThanTheBestAvailable() {
    let picked = QualityPlan.pick(requested: nil, priority: ["720p", "1080p"], available: ["1080p", "4K"])
    XCTAssertEqual(picked, "1080p")
  }

  func testPickKeepsTheCdnsOwnSpelling() {
    XCTAssertEqual(QualityPlan.pick(requested: "4K", priority: ["4K"], available: ["4K"]), "4K")
  }

  func testPickFindsAnEquivalentTierUnderAnotherName() {
    XCTAssertEqual(QualityPlan.pick(requested: nil, priority: ["4K"], available: ["2160p"]), "2160p")
  }

  func testPickFallsBackToTheFinestRenditionWhenNothingMatches() {
    XCTAssertEqual(QualityPlan.pick(requested: "720p", priority: ["720p"], available: ["1440p"]), "1440p")
  }

  func testPickRefusesAnEmptyCatalogueOfRenditions() {
    XCTAssertNil(QualityPlan.pick(requested: "1080p", priority: ["1080p"], available: []))
  }

  func testHeightIsReadOutOfAnyLabel() {
    XCTAssertEqual(QualityTier.height(of: "2160p"), 2160)
    XCTAssertEqual(QualityTier.height(of: "1440p"), 1440)
    XCTAssertEqual(QualityTier.height(of: "4K"), 2160)
    XCTAssertEqual(QualityTier.height(of: "streaming"), 0)
  }

  func testOnlyKnownTiersCarryACdnId() {
    XCTAssertEqual(QualityTier.id(of: "1080p"), 2500)
    XCTAssertEqual(QualityTier.id(of: "4K"), 4500)
    XCTAssertNil(QualityTier.id(of: "1440p"))
  }
}
