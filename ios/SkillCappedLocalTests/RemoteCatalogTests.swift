import XCTest
@testable import SkillCappedLocal

final class RemoteCatalogTests: XCTestCase {
  private func loadDump() throws -> Dump {
    let json = #"""
    {
      "seasonLabel": "Season 2026",
      "patch": { "patchVal": "26.21" },
      "tagInfo": [{ "name": "Fundamentals" }],
      "videos": [
        {
          "uuid": "v1",
          "title": "Farming from behind",
          "role": "adc",
          "tId": 0,
          "durSec": 620,
          "rDate": 1700000000000,
          "tSS": "https://cdn.example/farming.jpg"
        },
        {
          "uuid": "v2",
          "title": "Wave control",
          "role": "mid",
          "tId": 7,
          "durSec": 300,
          "rDate": 1600000000000,
          "tSS": ""
        }
      ],
      "commentaries": [
        {
          "uuid": "c1",
          "role": "adc",
          "tId": 0,
          "durSec": 1800,
          "rDate": 1650000000000,
          "tSS": "",
          "staff": "Coach",
          "yourChampion": "Jinx",
          "theirChampion": "Caitlyn",
          "k": 10,
          "d": 2,
          "a": 5
        }
      ],
      "courses": [
        {
          "uuid": "k1",
          "title": "Why You Suck {adc}",
          "role": "adc",
          "rDate": 1690000000000,
          "tags": ["Fundamentals"],
          "courseImage": "https://cdn.example/a.jpg",
          "courseImage2": "",
          "courseImage3": "https://cdn.example/c.jpg"
        }
      ],
      "videosToCourses": {
        "Why You Suck {adc}": {
          "chapters": [
            { "title": "Intro", "vids": [{ "uuid": "v1" }] }
          ]
        }
      }
    }
    """#
    return try JSONDecoder().decode(Dump.self, from: Data(json.utf8))
  }

  func testDisplayTitleSubstitutesTheRoleToken() {
    XCTAssertEqual(CatalogService.displayTitle("Why You Suck {adc}"), "Why You Suck (ADC)")
    XCTAssertEqual(CatalogService.displayTitle("Wave Control {all}"), "Wave Control (All Roles)")
  }

  func testDisplayTitleLeavesAnUnknownTokenAlone() {
    XCTAssertEqual(CatalogService.displayTitle("Wave Control {unknown}"), "Wave Control {unknown}")
  }

  func testBuildFlattensEveryKind() throws {
    let catalog = CatalogService.build(dump: try loadDump(), dumpUrl: "https://cdn.example/dump.json")
    XCTAssertEqual(catalog.season, "Season 2026")
    XCTAssertEqual(catalog.patch, "26.21")
    XCTAssertEqual(catalog.items.count, 4)
    XCTAssertEqual(catalog.items(kind: "video").count, 2)
    XCTAssertEqual(catalog.items(kind: "course").count, 1)
    XCTAssertEqual(catalog.items(kind: "commentary").count, 1)
  }

  func testNewestFirst() throws {
    let catalog = CatalogService.build(dump: try loadDump(), dumpUrl: "")
    let dates = catalog.items.compactMap(\.date)
    XCTAssertEqual(dates, dates.sorted(by: >))
  }

  func testVideoInheritsItsCourseTitleAndTheCoursesLessonOrder() throws {
    let catalog = CatalogService.build(dump: try loadDump(), dumpUrl: "")
    let video = try XCTUnwrap(catalog.item("v1"))
    XCTAssertEqual(video.courseTitle, "Why You Suck (ADC)")

    let course = try XCTUnwrap(catalog.course("k1"))
    XCTAssertEqual(course.title, "Why You Suck (ADC)")
    XCTAssertEqual(course.lessonIds, ["v1"])
    XCTAssertEqual(course.videoCount, 1)
    XCTAssertEqual(catalog.lessons(of: course).map(\.id), ["v1"])
    XCTAssertEqual(course.thumb, "https://cdn.example/c.jpg")
  }

  func testALooseVideoKeepsItsOwnCategory() throws {
    let catalog = CatalogService.build(dump: try loadDump(), dumpUrl: "")
    let video = try XCTUnwrap(catalog.item("v2"))
    XCTAssertNil(video.courseTitle)
    XCTAssertEqual(video.category, "")
  }

  func testCommentaryTitleAndScore() throws {
    let catalog = CatalogService.build(dump: try loadDump(), dumpUrl: "")
    let commentary = try XCTUnwrap(catalog.item("c1"))
    XCTAssertEqual(commentary.title, "Coach — Jinx")
    XCTAssertEqual(commentary.champions, "Jinx vs Caitlyn")
    XCTAssertEqual(commentary.kda, "10/2/5")
    XCTAssertEqual(commentary.category, "Fundamentals")
  }

  func testCatalogueIndexKnowsWhichCourseHoldsALesson() throws {
    let catalog = CatalogService.build(dump: try loadDump(), dumpUrl: "")
    let index = catalog.index
    XCTAssertEqual(index.courseByLesson["v1"], "k1")
    XCTAssertEqual(index.order(of: "v1", in: "k1"), 0)
    XCTAssertNil(index.course("v1"))
  }

  func testEveryRowGetsAThumbUrlOnlyWhenItIsHttp() throws {
    let catalog = CatalogService.build(dump: try loadDump(), dumpUrl: "")
    XCTAssertNotNil(try XCTUnwrap(catalog.item("v1")).thumbURL)
    XCTAssertNil(try XCTUnwrap(catalog.item("v2")).thumbURL)
  }

  func testADumpMissingEverythingStillDecodesToAnEmptyCatalogue() throws {
    let dump = try JSONDecoder().decode(Dump.self, from: Data("{}".utf8))
    let catalog = CatalogService.build(dump: dump, dumpUrl: "")
    XCTAssertTrue(catalog.items.isEmpty)
    XCTAssertEqual(catalog.roles, CatalogService.roles)
  }

  func testACachedCatalogueRoundTrips() throws {
    let catalog = CatalogService.build(dump: try loadDump(), dumpUrl: "https://cdn.example/dump.json")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-roundtrip.json")
    defer { JSONFile.remove(url) }
    JSONFile.save(catalog, to: url)
    let loaded = try XCTUnwrap(JSONFile.load(RemoteCatalog.self, from: url))
    XCTAssertEqual(loaded.items.count, catalog.items.count)
    XCTAssertEqual(loaded.items.first?.id, catalog.items.first?.id)
    XCTAssertEqual(loaded.items.first?.courseTitle, catalog.items.first?.courseTitle)
  }
}
