import { describe, expect, test } from "bun:test"
import { mkdtemp, mkdir, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"
import { locateItems, scanLibrary } from "../../src/core/library.ts"
import type { CatalogItem } from "../../src/types/catalog.ts"

function item(overrides: Partial<CatalogItem> & Pick<CatalogItem, "id" | "title">): CatalogItem {
  return {
    kind: "video",
    role: "mid",
    durationSec: 60,
    date: 1_000,
    category: "Macro",
    tags: [],
    thumb: "",
    ...overrides,
  }
}

describe("locateItems", () => {
  test("finds a lesson from its folder and title", () => {
    const locate = locateItems([item({ id: "abc", title: "Wave Control" })])
    expect(locate("Videos/mid/Macro", "Wave Control")?.id).toBe("abc")
  })

  test("accepts a name whose title was sanitized on the way out", () => {
    const locate = locateItems([item({ id: "abc", title: 'Kai\'Sa w/ Jhin' })])
    expect(locate("Videos/mid/Macro", "Kai'Sa w Jhin")?.id).toBe("abc")
  })

  test("does not match a lesson sitting in another folder", () => {
    const locate = locateItems([item({ id: "abc", title: "Wave Control", category: "Laning" })])
    expect(locate("Videos/mid/Macro", "Wave Control")).toBeNull()
  })

  test("accepts a truncated title, because the path budget shortens long names", () => {
    const long = "A very long lesson title that will be cut at the segment limit somewhere"
    const locate = locateItems([item({ id: "abc", title: long })])
    expect(locate("Videos/mid/Macro", long.slice(0, 40))?.id).toBe("abc")
  })

  test("does not guess from a very short fragment", () => {
    const locate = locateItems([item({ id: "abc", title: "Wave Control" })])
    expect(locate("Videos/mid/Macro", "Wave")).toBeNull()
  })

  test("takes the shortest title a truncated fragment could have come from", () => {
    const locate = locateItems([
      item({ id: "abc", title: "Wave Control Advanced Laning Patterns" }),
      item({ id: "abd", title: "Wave Control Advanced" }),
    ])
    expect(locate("Videos/mid/Macro", "Wave Control Adv")?.id).toBe("abd")
  })

  test("resolves two lessons that share a title the same way on both surfaces", () => {
    const locate = locateItems([
      item({ id: "zzz", title: "Wave Control" }),
      item({ id: "aaa", title: "Wave Control" }),
    ])
    expect(locate("Videos/mid/Macro", "Wave Control")?.id).toBe("aaa")
  })

  test("ignores courses, which have no file of their own", () => {
    const locate = locateItems([item({ id: "c", kind: "course", title: "Wave Control" })])
    expect(locate("Courses/mid/Wave Control", "Wave Control")).toBeNull()
  })
})

describe("scanLibrary", () => {
  test("resolves a numbered file back to its lesson and keeps the number", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "library-"))
    try {
      await mkdir(path.join(root, "Videos", "mid", "Macro"), { recursive: true })
      await Bun.write(path.join(root, "Videos", "mid", "Macro", "02 - Wave Control 1080p.mp4"), "x")

      const library = await scanLibrary(root, [item({ id: "abc", title: "Wave Control" })])
      expect(library.entries).toHaveLength(1)
      expect(library.entries[0].uuid).toBe("abc")
      expect(library.entries[0].number).toBe(2)
      expect(library.entries[0].folder).toBe("Videos/mid/Macro")
      expect(library.keys.has("abc:1080p")).toBe(true)
      expect(library.totalBytes).toBe(1)
    } finally {
      await rm(root, { recursive: true, force: true })
    }
  })

  test("still reads a file written before numbering, by its uuid", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "library-"))
    try {
      await mkdir(path.join(root, "Courses", "mid", "Wave Control"), { recursive: true })
      const file = path.join(root, "Courses", "mid", "Wave Control", "Ch 1 [j413lhtmz7] 720p.mp4")
      await Bun.write(file, "x")

      const library = await scanLibrary(root, [])
      expect(library.entries[0].uuid).toBe("j413lhtmz7")
      expect(library.entries[0].number).toBeNull()
      expect(library.keys.has("j413lhtmz7:720p")).toBe(true)
    } finally {
      await rm(root, { recursive: true, force: true })
    }
  })

  test("skips its own scratch directory", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "library-"))
    try {
      await mkdir(path.join(root, ".skillcapped", "tmp"), { recursive: true })
      await Bun.write(path.join(root, ".skillcapped", "tmp", "1 - Partial 720p.mp4"), "x")
      const library = await scanLibrary(root, [])
      expect(library.entries).toHaveLength(0)
    } finally {
      await rm(root, { recursive: true, force: true })
    }
  })

  test("ignores files that are not downloads", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "library-"))
    try {
      await Bun.write(path.join(root, "notes.txt"), "x")
      await Bun.write(path.join(root, "home video.mp4"), "x")
      const library = await scanLibrary(root, [])
      expect(library.entries).toHaveLength(0)
    } finally {
      await rm(root, { recursive: true, force: true })
    }
  })
})
