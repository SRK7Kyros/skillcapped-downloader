import { describe, expect, test } from "bun:test"
import type { LibraryEntry } from "../../src/core/library.ts"
import { mediaUrl, planPreview, playlistUrl } from "../../src/core/preview.ts"

function entry(overrides: Partial<LibraryEntry>): LibraryEntry {
  return {
    uuid: "abc123abcd",
    title: "Lesson",
    qualityLabel: "1080p",
    quality: 2500,
    extension: "mp4",
    relativePath: "Course/Lesson.mp4",
    folder: "Course",
    sizeBytes: 1_000,
    modifiedAt: 0,
    ...overrides,
  }
}

describe("planPreview", () => {
  test("streams from the CDN when nothing is on disk", () => {
    const plan = planPreview("abc123abcd", 1500, 600, [])
    expect(plan.mode).toBe("remote")
    expect(plan.url).toBe(playlistUrl("abc123abcd", 1500, 600))
    expect(plan.label).toBe("720p")
  })

  test("plays the downloaded file instead", () => {
    const plan = planPreview("abc123abcd", 1500, 600, [entry({})])
    expect(plan.mode).toBe("local")
    expect(plan.url).toBe(mediaUrl("abc123abcd", "1080p"))
  })

  test("prefers the finest rendition on disk over the requested quality", () => {
    const plan = planPreview("abc123abcd", 1500, 600, [
      entry({ quality: 800, qualityLabel: "360p", relativePath: "A.mp4" }),
      entry({ quality: 4000, qualityLabel: "2160p", relativePath: "B.mp4" }),
    ])
    expect(plan).toMatchObject({ mode: "local", quality: 4000, label: "2160p" })
  })

  test("ignores files belonging to another video", () => {
    const plan = planPreview("abc123abcd", 1500, 600, [entry({ uuid: "zzz9999999" })])
    expect(plan.mode).toBe("remote")
  })

  test("still prefers a local file when its quality is unknown", () => {
    const plan = planPreview("abc123abcd", 1500, 600, [entry({ quality: null, qualityLabel: "" })])
    expect(plan.mode).toBe("local")
    expect(plan.url).toBe("/api/media/abc123abcd")
  })
})

describe("mediaUrl", () => {
  test("encodes the quality label and omits an empty one", () => {
    expect(mediaUrl("abc", "1080p")).toBe("/api/media/abc?quality=1080p")
    expect(mediaUrl("abc", "")).toBe("/api/media/abc")
  })
})

describe("playlistUrl", () => {
  test("carries a whole-second duration", () => {
    expect(playlistUrl("abc", 2500, 601.4)).toBe("/api/stream/abc.m3u8?quality=2500&dur=601")
  })
})
