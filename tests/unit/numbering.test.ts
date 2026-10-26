import { describe, expect, test } from "bun:test"
import { compareLessons, fileNumbers } from "../../src/core/numbering.ts"
import type { CatalogItem } from "../../src/types/catalog.ts"

function item(overrides: Partial<CatalogItem> & Pick<CatalogItem, "id" | "title">): CatalogItem {
  return {
    kind: "video",
    role: "mid",
    durationSec: 60,
    date: 1_000,
    category: "General",
    tags: [],
    thumb: "",
    ...overrides,
  }
}

describe("fileNumbers", () => {
  test("numbers a course's lessons by the course's own order, whatever the catalogue order", () => {
    const items = [
      item({ id: "b", title: "Second", date: 3_000 }),
      item({ id: "course", kind: "course", title: "Wave Control", lessonIds: ["c", "a", "b"] }),
      item({ id: "a", title: "First", date: 5_000 }),
      item({ id: "c", title: "Third", date: 1_000 }),
    ]
    const numbers = fileNumbers(items)
    expect(numbers.get("c")).toEqual({ index: 1, total: 3 })
    expect(numbers.get("a")).toEqual({ index: 2, total: 3 })
    expect(numbers.get("b")).toEqual({ index: 3, total: 3 })
  })

  test("numbers loose videos within their own folder, newest first", () => {
    const items = [
      item({ id: "old", title: "Old", date: 1_000, category: "Macro" }),
      item({ id: "new", title: "New", date: 9_000, category: "Macro" }),
      item({ id: "other", title: "Elsewhere", date: 5_000, category: "Laning" }),
    ]
    const numbers = fileNumbers(items)
    expect(numbers.get("new")).toEqual({ index: 1, total: 2 })
    expect(numbers.get("old")).toEqual({ index: 2, total: 2 })
    expect(numbers.get("other")).toEqual({ index: 1, total: 1 })
  })

  test("a role is its own collection", () => {
    const items = [
      item({ id: "a", title: "A", role: "top", category: "Macro" }),
      item({ id: "b", title: "B", role: "mid", category: "Macro" }),
    ]
    const numbers = fileNumbers(items)
    expect(numbers.get("a")).toEqual({ index: 1, total: 1 })
    expect(numbers.get("b")).toEqual({ index: 1, total: 1 })
  })

  test("groups commentaries by role only", () => {
    const items = [
      item({ id: "a", kind: "commentary", title: "Hector — Ahri", role: "mid", category: "Coaching" }),
      item({ id: "b", kind: "commentary", title: "Hector — Zed", role: "mid", category: "Coaching" }),
    ]
    const numbers = fileNumbers(items)
    expect(numbers.get("a")).toEqual({ index: 1, total: 2 })
    expect(numbers.get("b")).toEqual({ index: 2, total: 2 })
  })

  test("never numbers a course itself", () => {
    const numbers = fileNumbers([item({ id: "course", kind: "course", title: "Wave Control", lessonIds: ["a"] })])
    expect(numbers.has("course")).toBe(false)
  })

  test("a video pointing at a course folder the course does not list takes no number", () => {
    const items = [
      item({ id: "course", kind: "course", title: "Wave Control", lessonIds: ["a"] }),
      item({ id: "a", title: "Listed", courseTitle: "Wave Control" }),
      item({ id: "stray", title: "Stray", courseTitle: "Wave Control", date: 9_000 }),
    ]
    const numbers = fileNumbers(items)
    expect(numbers.get("a")).toEqual({ index: 1, total: 1 })
    expect(numbers.has("stray")).toBe(false)
  })

  test("ignores a lesson id the catalogue no longer carries", () => {
    const numbers = fileNumbers([
      item({ id: "course", kind: "course", title: "Wave Control", lessonIds: ["gone", "a"] }),
      item({ id: "a", title: "Listed" }),
    ])
    expect(numbers.get("a")).toEqual({ index: 2, total: 2 })
  })
})

describe("compareLessons", () => {
  test("is newest first, then title, then id — never the array's own order", () => {
    const first = item({ id: "b", title: "Wave", date: 5_000 })
    const second = item({ id: "a", title: "Wave", date: 5_000 })
    expect(compareLessons(first, second)).toBe(1)
    expect(compareLessons(second, first)).toBe(-1)
    expect(compareLessons(first, first)).toBe(0)
  })
})
