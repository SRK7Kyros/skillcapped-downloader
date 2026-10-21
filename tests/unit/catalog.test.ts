import { describe, expect, test } from "bun:test"
import { buildCatalog, displayTitle, ROLES } from "../../src/core/catalog.ts"
import { dumpSchema } from "../../src/types/catalog.ts"

const raw = {
  seasonLabel: "Season 16",
  patch: { patchVal: "26.16" },
  tagInfo: [{ name: "Mid - Wave Control" }, { name: "Top - Laning" }],
  videos: [
    { uuid: "aaaa111111", title: "Lesson One", durSec: 100, rDate: 3000, tId: 0, role: "mid", tSS: "", cSS: "", encoding: "x" },
    { uuid: "bbbb222222", title: "Standalone", durSec: 200, rDate: 2000, tId: 1, role: "top", tSS: "", cSS: "", encoding: "x" },
  ],
  commentaries: [
    {
      uuid: "cccc333333",
      staff: "Hector",
      yourChampion: "Ahri",
      theirChampion: "Zed",
      k: 6,
      d: 1,
      a: 4,
      durSec: 300,
      rDate: 1000,
      tId: 0,
      role: "mid",
      tSS: "",
    },
  ],
  courses: [
    { uuid: "dddd444444", title: "Wave Control {top}", role: "top", rDate: 4000, tags: ["Top", "Top - Laning"], courseImage3: "https://x/a.png" },
    { uuid: "eeee555555", title: "Empty Course {all}", role: "all", rDate: 1500, tags: ["All"], courseImage3: "https://x/b.png" },
  ],
  videosToCourses: {
    "Wave Control {top}": { chapters: [{ title: "Course Content", vids: [{ uuid: "aaaa111111" }] }] },
    "Empty Course {all}": { chapters: [{ title: "Course Content", vids: [] }] },
  },
}

const dump = dumpSchema.parse(raw)
const catalog = buildCatalog(dump, "https://example.invalid/dump.json")
const byId = new Map(catalog.items.map((item) => [item.id, item]))

describe("displayTitle", () => {
  test("substitutes the role token the site fills in at render time", () => {
    expect(displayTitle("Wave Control {top}")).toBe("Wave Control (Top)")
    expect(displayTitle("League Classic {all}")).toBe("League Classic (All Roles)")
    expect(displayTitle("Chapter 1: Wave Control {support}")).toBe("Chapter 1: Wave Control (Support)")
  })

  test("handles more than one token and ignores case", () => {
    expect(displayTitle("{mid} and {TOP}")).toBe("(Mid) and (Top)")
  })

  test("leaves a token it does not understand alone rather than deleting it", () => {
    expect(displayTitle("Cost {champion}")).toBe("Cost {champion}")
  })

  test("is a no-op for an ordinary title", () => {
    expect(displayTitle("How to Carry as Support")).toBe("How to Carry as Support")
  })
})

describe("buildCatalog", () => {
  test("reports the season, patch and canonical role order", () => {
    expect(catalog.season).toBe("Season 16")
    expect(catalog.patch).toBe("26.16")
    expect(catalog.roles).toEqual([...ROLES])
    expect(catalog.dumpUrl).toBe("https://example.invalid/dump.json")
  })

  test("renders course titles without the raw token", () => {
    expect(byId.get("dddd444444")?.title).toBe("Wave Control (Top)")
    expect(catalog.items.some((item) => item.title.includes("{"))).toBe(false)
  })

  test("attaches lessons to their course and reports the count", () => {
    const course = byId.get("dddd444444")
    expect(course?.kind).toBe("course")
    expect(course?.lessonIds).toEqual(["aaaa111111"])
    expect(course?.videoCount).toBe(1)
  })

  test("a course with no published lessons still exists, with a zero count", () => {
    const course = byId.get("eeee555555")
    expect(course?.kind).toBe("course")
    expect(course?.lessonIds).toEqual([])
    expect(course?.videoCount).toBe(0)
  })

  test("the lesson carries the display form of its course title, so the folder matches", () => {
    expect(byId.get("aaaa111111")?.courseTitle).toBe("Wave Control (Top)")
  })

  test("a video outside any course has no course title", () => {
    expect(byId.get("bbbb222222")?.courseTitle).toBeUndefined()
  })

  test("resolves a video's category from the tag table", () => {
    expect(byId.get("aaaa111111")?.category).toBe("Mid - Wave Control")
  })

  test("describes a commentary with its coach and champions", () => {
    const commentary = byId.get("cccc333333")
    expect(commentary?.kind).toBe("commentary")
    expect(commentary?.title).toBe("Hector — Ahri")
    expect(commentary?.champions).toBe("Ahri vs Zed")
    expect(commentary?.kda).toBe("6/1/4")
  })

  test("orders every item newest first so browse opens on current content", () => {
    const dates = catalog.items.map((item) => item.date)
    expect(dates).toEqual([...dates].sort((a, b) => b - a))
    expect(catalog.items[0]?.id).toBe("dddd444444")
  })

  test("derives a deduplicated, sorted category list", () => {
    expect(catalog.categories).toContain("Top - Laning")
    expect(catalog.categories).toContain("Mid - Wave Control")
    expect(catalog.categories).toEqual([...catalog.categories].sort((a, b) => a.localeCompare(b)))
    expect(new Set(catalog.categories).size).toBe(catalog.categories.length)
  })

  test("tolerates a dump where most fields are missing", () => {
    const sparse = buildCatalog(dumpSchema.parse({}), "https://example.invalid/empty.json")
    expect(sparse.items).toEqual([])
    expect(sparse.categories).toEqual([])
    expect(sparse.roles).toEqual([...ROLES])
  })
})
