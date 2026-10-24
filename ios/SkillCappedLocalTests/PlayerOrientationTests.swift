import SwiftUI
import UIKit
import XCTest
@testable import SkillCappedLocal

final class PlayerOrientationTests: XCTestCase {
  func testTheTwoEnumsNameTheLandscapesTheOtherWayRound() {
    XCTAssertEqual(PlayerOrientation.mask(for: UIDeviceOrientation.landscapeLeft), .landscapeRight)
    XCTAssertEqual(PlayerOrientation.mask(for: UIDeviceOrientation.landscapeRight), .landscapeLeft)
    XCTAssertEqual(PlayerOrientation.mask(for: UIDeviceOrientation.portrait), .portrait)
  }

  func testAFlatPhoneAsksTheWindowForNothing() {
    XCTAssertNil(PlayerOrientation.mask(for: UIDeviceOrientation.faceUp))
    XCTAssertNil(PlayerOrientation.mask(for: UIDeviceOrientation.faceDown))
    XCTAssertNil(PlayerOrientation.mask(for: UIDeviceOrientation.unknown))
  }

  func testAWindowAlreadyOnItsSideNeedsNoTurn() {
    for device in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
      XCTAssertEqual(
        PlayerOrientation.turn(device: device, window: CGSize(width: 852, height: 393)),
        .upright,
        "a landscape window is already the way the phone is held"
      )
    }
  }

  func testAPhoneOnItsSideWithALockedWindowTurnsThePicture() {
    XCTAssertEqual(
      PlayerOrientation.turn(device: .landscapeLeft, window: CGSize(width: 393, height: 852)),
      .clockwise
    )
    XCTAssertEqual(
      PlayerOrientation.turn(device: .landscapeRight, window: CGSize(width: 393, height: 852)),
      .counterClockwise
    )
  }

  func testAPhoneUprightWithAPortraitWindowStaysUpright() {
    XCTAssertEqual(
      PlayerOrientation.turn(device: .portrait, window: CGSize(width: 393, height: 852)),
      .upright
    )
    XCTAssertEqual(
      PlayerOrientation.turn(device: .faceUp, window: CGSize(width: 393, height: 852)),
      .upright
    )
  }

  func testATurnIsAQuarterCircleEachWay() {
    XCTAssertEqual(PlayerOrientation.Turn.upright.angle, .zero)
    XCTAssertEqual(PlayerOrientation.Turn.clockwise.angle, .degrees(90))
    XCTAssertEqual(PlayerOrientation.Turn.counterClockwise.angle, .degrees(-90))
    XCTAssertFalse(PlayerOrientation.Turn.upright.isTurned)
    XCTAssertTrue(PlayerOrientation.Turn.clockwise.isTurned)
  }

  func testAnUprightPictureKeepsItsOwnSafeArea() {
    let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    XCTAssertEqual(PlayerOrientation.insets(insets, turned: .upright), insets)
  }

  func testATurnedPictureTakesItsSafeAreaFromTheOtherEdges() {
    let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    let clockwise = PlayerOrientation.insets(insets, turned: .clockwise)
    XCTAssertEqual(clockwise.top, 0, "the window's right edge is the picture's top")
    XCTAssertEqual(clockwise.leading, 59, "the notch is on the picture's leading side")
    XCTAssertEqual(clockwise.trailing, 34, "the home indicator is on its trailing side")
    XCTAssertEqual(clockwise.bottom, 0)

    let counter = PlayerOrientation.insets(insets, turned: .counterClockwise)
    XCTAssertEqual(counter.top, 0)
    XCTAssertEqual(counter.leading, 34, "the home indicator is on the leading side now")
    XCTAssertEqual(counter.trailing, 59)
    XCTAssertEqual(counter.bottom, 0)
  }

  func testAWindowIsJudgedByItsShapeRatherThanItsSide() {
    XCTAssertFalse(
      PlayerOrientation.agrees(device: .landscapeLeft, window: .portrait),
      "a phone on its side with a portrait window is the locked case"
    )
    XCTAssertTrue(PlayerOrientation.agrees(device: .landscapeLeft, window: .landscapeLeft))
    XCTAssertTrue(
      PlayerOrientation.agrees(device: .landscapeLeft, window: .landscapeRight),
      "either landscape is the shape the phone is held in, so neither is a reason to turn the window"
    )
    XCTAssertTrue(PlayerOrientation.agrees(device: .portrait, window: .portraitUpsideDown))
    XCTAssertFalse(PlayerOrientation.agrees(device: .portrait, window: .landscapeLeft))
  }

  func testAFlatPhoneDisagreesWithNothing() {
    for window in [UIInterfaceOrientation.portrait, .landscapeLeft] {
      XCTAssertTrue(PlayerOrientation.agrees(device: .faceUp, window: window))
      XCTAssertTrue(PlayerOrientation.agrees(device: .unknown, window: window))
    }
  }
}
