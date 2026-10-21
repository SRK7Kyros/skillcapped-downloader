import { describe, expect, test } from "bun:test"
import { buildFileName, destinationPath, parseFileName, relativeFolder, sanitizeSegment } from "../../src/core/naming.ts"

describe("sanitizeSegment", () => {
  test("replaces characters Windows forbids", () => {
    expect(sanitizeSegment('a<b>c:d"e/f\\g|h?i*j')).toBe("a b c d e f g h i j")
  })

  test("drops control characters", () => {
    expect(sanitizeSegment("a\u0000b\u001fc")).toBe("a b c")
  })

  test("collapses runs of whitespace and trims", () => {
    expect(sanitizeSegment("  Wave   Control  ")).toBe("Wave Control")
  })

  test("strips trailing dots and spaces that Windows would drop silently", () => {
    expect(sanitizeSegment("Chapter 1... ")).toBe("Chapter 1")
  })

  test("suffixes reserved device names", () => {
    expect(sanitizeSegment("con")).toBe("con_")
    expect(sanitizeSegment("COM1")).toBe("COM1_")
    expect(sanitizeSegment("Master COM10 settings")).toBe("Master COM10 settings")
  })

  test("falls back when nothing usable survives", () => {
    expect(sanitizeSegment("")).toBe("untitled")
    expect(sanitizeSegment("///")).toBe("untitled")
  })

  test("truncates to the length budget without leaving a trailing separator", () => {
    const long = "x".repeat(200)
    expect(sanitizeSegment(long).length).toBe(90)
    expect(sanitizeSegment("abcdefghij klmno", 8)).toBe("abcdefgh")
  })

  test("keeps apostrophes, which are legal on every target", () => {
    expect(sanitizeSegment("What's Next")).toBe("What's Next")
  })
})

describe("relativeFolder", () => {
  test("groups a standalone video by role then category", () => {
    expect(relativeFolder({ kind: "video", title: "t", role: "mid", category: "Mid - Wave Control" })).toBe(
      "Videos/mid/Mid - Wave Control",
    )
  })

  test("falls back to a General folder when the video has no category", () => {
    expect(relativeFolder({ kind: "video", title: "t", role: "adc", category: "" })).toBe("Videos/adc/General")
  })

  test("keeps a course lesson inside its course folder", () => {
    expect(relativeFolder({ kind: "video", title: "Lesson", role: "support", courseTitle: "Wave Control (Support)" })).toBe(
      "Courses/support/Wave Control (Support)",
    )
  })

  test("puts a course item under its own title", () => {
    expect(relativeFolder({ kind: "course", title: "Wave Control (Top)", role: "top" })).toBe(
      "Courses/top/Wave Control (Top)",
    )
  })

  test("groups commentaries by role only", () => {
    expect(relativeFolder({ kind: "commentary", title: "Hector — Ahri", role: "mid" })).toBe("Commentaries/mid")
  })
})

describe("buildFileName", () => {
  test("carries the uuid and quality label so files can be identified and deduped", () => {
    expect(buildFileName("What's Next", "j413lhtmz7", 1500, "mp4")).toBe("What's Next [j413lhtmz7] 720p.mp4")
  })

  test("uses the numeric label for 4K so the parser stays uniform", () => {
    expect(buildFileName("Carry", "cjex4gnn44", 4500, "ts")).toBe("Carry [cjex4gnn44] 2160p.ts")
  })

  test("truncates a long title but always keeps the uuid + label suffix", () => {
    const name = buildFileName("x".repeat(300), "aaaaaaaaaa", 2500, "mp4")
    expect(name.length).toBeLessThanOrEqual(90)
    expect(name.endsWith(" [aaaaaaaaaa] 1080p.mp4")).toBe(true)
  })
})

describe("parseFileName", () => {
  test("round-trips what buildFileName produces", () => {
    for (const quality of [1500, 2500, 4500]) {
      for (const extension of ["mp4", "ts"]) {
        const name = buildFileName("Emerald - Zyra vs Caitlyn", "vspxhjdjrw", quality, extension)
        const parsed = parseFileName(name)
        expect(parsed).not.toBeNull()
        expect(parsed?.uuid).toBe("vspxhjdjrw")
        expect(parsed?.extension).toBe(extension)
        expect(parsed?.title).toBe("Emerald - Zyra vs Caitlyn")
      }
    }
  })

  test("parses a name whose title was sanitized before it was written", () => {
    const name = buildFileName("Kai'Sa w/ Jhin", "bnb73n2hqv", 2500, "mp4")
    expect(name).toBe("Kai'Sa w Jhin [bnb73n2hqv] 1080p.mp4")
    expect(parseFileName(name)?.title).toBe("Kai'Sa w Jhin")
  })

  test("ignores a file that did not come from this app", () => {
    expect(parseFileName("random video.mp4")).toBeNull()
    expect(parseFileName("notes.txt")).toBeNull()
  })
})

describe("destinationPath", () => {
  test("nests the file under the content root", () => {
    const result = destinationPath("/content", { kind: "video", title: "Hello", role: "top", category: "C", id: "abc123456" }, 1500, "mp4")
    expect(result).toBe("/content/Videos/top/C/Hello [abc123456] 720p.mp4")
  })

  test("compacts the name rather than exceeding the Windows path budget", () => {
    const root = `/content/${"deep/".repeat(20)}`
    const shape = { kind: "course" as const, title: "t".repeat(80), role: "mid", id: "abc123456" }
    const result = destinationPath(root, shape, 1500, "mp4")
    expect(result.length).toBeLessThan(260)
    expect(result.endsWith(" 720p.mp4")).toBe(true)
  })
})
