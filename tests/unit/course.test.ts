import { describe, expect, test } from "bun:test"
import type { CatalogItem } from "../../web/src/api/types.ts"
import { courseDiskState, courseLessons, missingLessons } from "../../web/src/lib/course.ts"

const item = (over: Partial<CatalogItem>): CatalogItem => ({
  id: over.id ?? "item",
  kind: "video",
  title: "Lesson",
  role: "adc",
  durationSec: 600,
  date: 1,
  category: "Fundamentals",
  tags: [],
  thumb: "",
  ...over,
})

const course = item({
  id: "c1",
  kind: "course",
  title: "Wave Control",
  videoCount: 3,
  lessonIds: ["l2", "l1", "l3"],
  date: 10,
})

const lessons = [
  item({ id: "l1", title: "First", date: 1 }),
  item({ id: "l2", title: "Second", date: 2 }),
  item({ id: "l3", title: "Third", date: 3 }),
  item({ id: "x1", title: "Elsewhere", date: 4 }),
]

describe("courseLessons", () => {
  test("follows the course's own lesson order", () => {
    expect(courseLessons([course, ...lessons], course).map((lesson) => lesson.id)).toEqual(["l2", "l1", "l3"])
  })

  test("falls back to the lessons that name the course, oldest first", () => {
    const bare = item({ id: "c2", kind: "course", title: "Jungle Paths", date: 10 })
    const pool = [
      bare,
      item({ id: "j2", title: "Later", courseTitle: "Jungle Paths", date: 20 }),
      item({ id: "j1", title: "Earlier", courseTitle: "Jungle Paths", date: 5 }),
      item({ id: "k1", title: "Other course", courseTitle: "Laning", date: 1 }),
    ]
    expect(courseLessons(pool, bare).map((lesson) => lesson.id)).toEqual(["j1", "j2"])
  })

  test("skips lesson ids the dump no longer carries", () => {
    const stale = item({ id: "c3", kind: "course", title: "Stale", lessonIds: ["l1", "gone"] })
    expect(courseLessons([stale, ...lessons], stale).map((lesson) => lesson.id)).toEqual(["l1"])
  })

  test("has nothing to report for a course with no lessons", () => {
    const empty = item({ id: "c4", kind: "course", title: "Empty", lessonIds: [] })
    expect(courseLessons([empty, ...lessons], empty)).toEqual([])
  })
})

describe("courseDiskState", () => {
  const downloaded = new Map([
    ["l1", "1080p"],
    ["l2", "720p"],
  ])

  test("counts the lessons that are on disk", () => {
    expect(courseDiskState(lessons, downloaded)).toEqual({ have: 2, total: 4, complete: false })
  })

  test("is complete only when every lesson is on disk", () => {
    const all = new Map(lessons.map((lesson) => [lesson.id, "1080p"]))
    expect(courseDiskState(lessons, all).complete).toBe(true)
  })

  test("an empty course is never complete", () => {
    expect(courseDiskState([], downloaded)).toEqual({ have: 0, total: 0, complete: false })
  })

  test("lists what is still missing, in course order", () => {
    expect(missingLessons(lessons, downloaded).map((lesson) => lesson.id)).toEqual(["l3", "x1"])
  })
})
