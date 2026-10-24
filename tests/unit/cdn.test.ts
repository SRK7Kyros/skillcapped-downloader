import { describe, expect, test } from "bun:test"
import {
  CDN_ORIGIN,
  QUALITIES,
  buildPlaylist,
  expectedSegmentCount,
  parseManifest,
  playlistUrl,
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

  test("uses the manifest's own durations when they are known", () => {
    const playlist = buildPlaylist("abc123abcd", 2500, 3, 27, [10, 10, 7])
    expect(playlist.match(/#EXTINF:[0-9.]+/g)).toEqual(["#EXTINF:10", "#EXTINF:10", "#EXTINF:7"])
  })

  test("ignores durations that do not match the part count", () => {
    const playlist = buildPlaylist("abc123abcd", 2500, 3, 27, [10, 10])
    expect(playlist.match(/#EXTINF:[0-9.]+/g)).toEqual(["#EXTINF:10", "#EXTINF:10", "#EXTINF:10"])
  })
})

describe("playlistUrl", () => {
  test("names the rendition's own manifest beside its parts", () => {
    expect(playlistUrl("6hktv77jyp", 2500)).toBe(`${CDN_ORIGIN}/6hktv77jyp/HIDDEN2500.m3u8`)
    expect(playlistUrl("6hktv77jyp", 4500)).toBe(`${CDN_ORIGIN}/6hktv77jyp/HIDDEN4500.m3u8`)
  })
})

describe("parseManifest", () => {
  /** A real-shaped rendition: 13 full parts and a 7-second tail. */
  const manifest = (count: number) =>
    [
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      "#EXT-X-TARGETDURATION:10",
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-PLAYLIST-TYPE:VOD",
      ...Array.from({ length: count }, (_, index) => {
        const last = index === count - 1
        return `#EXTINF:${last ? "7.000000" : "10.000000"},\nHIDDEN2500-${String(index + 1).padStart(5, "0")}.ts`
      }),
      "#EXT-X-ENDLIST",
      "",
    ].join("\n")

  test("counts the parts and sums their real durations", () => {
    const parsed = parseManifest(manifest(14))
    expect(parsed?.count).toBe(14)
    expect(parsed?.durations).toHaveLength(14)
    expect(parsed?.durations[13]).toBe(7)
    expect(parsed?.duration).toBe(137)
  })

  test("stops at the manifest's last part, even though parts continue past it", () => {
    // The distribution keeps a longer, older encode behind the manifest's tail;
    // nothing in the manifest names those parts, so the count cannot reach them.
    expect(parseManifest(manifest(13))?.count).toBe(13)
  })

  test("tolerates CRLF, absolute addresses and query strings", () => {
    const text = [
      "#EXTM3U",
      "#EXTINF:10.000,",
      `${CDN_ORIGIN}/6hktv77jyp/HIDDEN2500-00001.ts?token=abc`,
      "#EXT-X-DISCONTINUITY",
      "#EXTINF:9.500,",
      "https://example.test/6hktv77jyp/HIDDEN2500-00002.ts",
      "#EXT-X-ENDLIST",
    ].join("\r\n")
    const parsed = parseManifest(text)
    expect(parsed?.count).toBe(2)
    expect(parsed?.duration).toBeCloseTo(19.5)
  })

  test("refuses a manifest whose parts are not 1..n", () => {
    const text = ["#EXTM3U", "#EXTINF:10,", "HIDDEN2500-00001.ts", "#EXTINF:10,", "HIDDEN2500-00003.ts"].join("\n")
    expect(parseManifest(text)).toBeNull()
  })

  test("refuses anything that is not a manifest", () => {
    expect(parseManifest("")).toBeNull()
    expect(parseManifest("<html>AccessDenied</html>")).toBeNull()
    expect(parseManifest("#EXTM3U\n#EXT-X-ENDLIST\n")).toBeNull()
    expect(parseManifest("#EXTM3U\nHIDDEN2500-00001.ts\n")).toBeNull()
  })

  test("refuses a part that is not named after its rendition", () => {
    const text = ["#EXTM3U", "#EXTINF:10,", "segment-1.ts"].join("\n")
    expect(parseManifest(text)).toBeNull()
  })
})
