import { describe, expect, test } from "bun:test"
import {
  CDN_ORIGIN,
  QUALITIES,
  buildPlaylist,
  expectedSegmentCount,
  qualityById,
  qualityLabel,
  segmentPath,
  segmentUrl,
} from "../../src/core/cdn.ts"

describe("segmentUrl", () => {
  test("zero-pads the 1-based index to five digits", () => {
    expect(segmentUrl("6hktv77jyp", 1500, 1)).toBe(`${CDN_ORIGIN}/6hktv77jyp/HIDDEN1500-00001.ts`)
    expect(segmentUrl("6hktv77jyp", 2500, 13)).toBe(`${CDN_ORIGIN}/6hktv77jyp/HIDDEN2500-00013.ts`)
    expect(segmentUrl("6hktv77jyp", 4500, 123)).toBe(`${CDN_ORIGIN}/6hktv77jyp/HIDDEN4500-00123.ts`)
  })
})

describe("expectedSegmentCount", () => {
  test("rounds up ten-second parts", () => {
    expect(expectedSegmentCount(10)).toBe(1)
    expect(expectedSegmentCount(11)).toBe(2)
    expect(expectedSegmentCount(21)).toBe(3)
    expect(expectedSegmentCount(120)).toBe(12)
    expect(expectedSegmentCount(123)).toBe(13)
  })

  test("never returns zero, even for an unknown duration", () => {
    expect(expectedSegmentCount(0)).toBe(1)
    expect(expectedSegmentCount(-5)).toBe(1)
  })

  test("matches the measured reality of a real video", () => {
    expect(expectedSegmentCount(123)).toBe(13)
  })
})

describe("quality table", () => {
  test("maps each id to a label and a short display name", () => {
    expect(qualityLabel(1500)).toBe("720p")
    expect(qualityLabel(2500)).toBe("1080p")
    expect(qualityLabel(4500)).toBe("2160p")
    expect(qualityById(4500)?.short).toBe("4K")
    expect(qualityById(4500)?.height).toBe(2160)
  })

  test("falls back for an unknown id rather than throwing", () => {
    expect(qualityById(999)).toBeUndefined()
    expect(qualityLabel(999)).toBe("999p")
  })

  test("is ordered low to high, which the fallback ladder relies on", () => {
    expect(QUALITIES.map((quality) => quality.id)).toEqual([1500, 2500, 4500])
  })
})

describe("buildPlaylist", () => {
  test("describes a complete VOD playlist", () => {
    const playlist = buildPlaylist("6hktv77jyp", 1500, 3, 21)
    const lines = playlist.split("\n")
    expect(lines[0]).toBe("#EXTM3U")
    expect(lines).toContain("#EXT-X-PLAYLIST-TYPE:VOD")
    expect(lines).toContain("#EXT-X-TARGETDURATION:10")
    expect(playlist.endsWith("#EXT-X-ENDLIST\n")).toBe(true)
  })

  test("emits one entry per part, in order, and nothing beyond the list", () => {
    const playlist = buildPlaylist("abc123abcd", 2500, 13, 123)
    expect(playlist.split("#EXTINF:").length - 1).toBe(13)
    expect(playlist).toContain(segmentPath("abc123abcd", 2500, 1))
    expect(playlist).toContain(segmentPath("abc123abcd", 2500, 13))
    expect(playlist).not.toContain(segmentPath("abc123abcd", 2500, 14))
  })

  test("points every part at this server, never at the CDN", () => {
    const playlist = buildPlaylist("abc123abcd", 2500, 2, 20)
    expect(playlist).not.toContain(CDN_ORIGIN)
    expect(playlist).toContain("/api/segment/abc123abcd/2500/00001.ts")
  })

  test("keeps the target duration at least one segment long", () => {
    expect(buildPlaylist("abc123abcd", 1500, 1, 0)).toContain("#EXT-X-TARGETDURATION:10")
  })
})
