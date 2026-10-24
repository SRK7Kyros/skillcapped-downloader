import XCTest

@testable import SkillCappedLocal

final class HlsManifestTests: XCTestCase {
  /// A real-shaped rendition: `count - 1` full parts and a 7-second tail.
  private func manifest(_ count: Int, lineEnding: String = "\n") -> String {
    let parts = (1...count).map { index -> String in
      let seconds = index == count ? "7.000000" : "10.000000"
      return "#EXTINF:\(seconds),\(lineEnding)HIDDEN2500-\(String(format: "%05d", index)).ts"
    }
    return ([
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      "#EXT-X-TARGETDURATION:10",
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-PLAYLIST-TYPE:VOD",
    ] + parts + ["#EXT-X-ENDLIST"]).joined(separator: lineEnding)
  }

  func testCountsThePartsAndSumsTheirRealDurations() {
    let listing = HlsManifest.listing(manifest(14))
    XCTAssertEqual(listing?.count, 14)
    XCTAssertEqual(listing?.seconds ?? 0, 137, accuracy: 0.001)
  }

  func testStopsAtTheManifestsLastPart() {
    XCTAssertEqual(HlsManifest.listing(manifest(13))?.count, 13)
    XCTAssertEqual(HlsManifest.listing(manifest(1))?.count, 1)
  }

  func testToleratesWindowsLineEndings() {
    XCTAssertEqual(HlsManifest.listing(manifest(4, lineEnding: "\r\n"))?.count, 4)
  }

  func testToleratesAbsoluteAddressesAndQueryStrings() {
    let text = """
    #EXTM3U
    #EXTINF:10.000,
    https://d13z5uuzt1wkbz.cloudfront.net/abc/HIDDEN2500-00001.ts?token=abc
    #EXT-X-DISCONTINUITY
    #EXTINF:9.500,
    https://example.test/abc/HIDDEN2500-00002.ts
    #EXT-X-ENDLIST
    """
    let listing = HlsManifest.listing(text)
    XCTAssertEqual(listing?.count, 2)
    XCTAssertEqual(listing?.seconds ?? 0, 19.5, accuracy: 0.001)
  }

  func testRefusesPartsThatAreNotNumberedOneToN() {
    let text = """
    #EXTM3U
    #EXTINF:10,HIDDEN2500-00001.ts
    #EXTINF:10,HIDDEN2500-00003.ts
    """
    XCTAssertNil(HlsManifest.listing(text))
  }

  func testRefusesAnythingThatIsNotAManifest() {
    XCTAssertNil(HlsManifest.listing(""))
    XCTAssertNil(HlsManifest.listing("<html>AccessDenied</html>"))
    XCTAssertNil(HlsManifest.listing("#EXTM3U\n#EXT-X-ENDLIST\n"))
    XCTAssertNil(HlsManifest.listing("#EXTM3U\nHIDDEN2500-00001.ts\n"))
    XCTAssertNil(HlsManifest.listing("#EXTM3U\n#EXTINF:0,HIDDEN2500-00001.ts\n"))
  }

  func testRefusesAPartThatIsNotNamedAfterItsRendition() {
    XCTAssertNil(HlsManifest.listing("#EXTM3U\n#EXTINF:10,segment-1.ts\n"))
  }

  func testNamesTheManifestBesideTheParts() {
    XCTAssertEqual(
      HlsManifest.url(uuid: "abc123", qualityId: 2500)?.absoluteString,
      "https://d13z5uuzt1wkbz.cloudfront.net/abc123/HIDDEN2500.m3u8"
    )
    XCTAssertEqual(
      HlsManifest.url(uuid: "abc123", qualityId: 4500)?.absoluteString,
      "https://d13z5uuzt1wkbz.cloudfront.net/abc123/HIDDEN4500.m3u8"
    )
  }
}
