import { describe, expect, test } from "bun:test"
import { findLastSegment, resolveSegments } from "../../src/core/probe.ts"

const MAX_SEGMENTS = 20_000

/** A published rendition of exactly `count` parts, plus a probe counter. */
function rendition(count: number) {
  const calls: number[] = []
  const probe = async (index: number) => {
    calls.push(index)
    return index <= count
  }
  return { probe, calls }
}

describe("findLastSegment", () => {
  test("returns the last existing index for a single-part video", async () => {
    const { probe } = rendition(1)
    expect(await findLastSegment(probe, 1)).toBe(1)
  })

  test("finds the exact tail across a range of lengths", async () => {
    for (const count of [1, 2, 3, 4, 7, 8, 13, 64, 100, 999, 1000, 4999]) {
      const { probe } = rendition(count)
      expect(await findLastSegment(probe, 2)).toBe(count)
    }
  })

  test("is unaffected by a hint that is far too small", async () => {
    const { probe } = rendition(400)
    expect(await findLastSegment(probe, 1)).toBe(400)
  })

  test("is unaffected by a hint that is far too large", async () => {
    const { probe } = rendition(5)
    expect(await findLastSegment(probe, 1000)).toBe(5)
  })

  test("handles a video right at the segment cap", async () => {
    const { probe } = rendition(MAX_SEGMENTS)
    expect(await findLastSegment(probe, 10)).toBe(MAX_SEGMENTS)
  })

  test("stays logarithmic: one long video must not cost thousands of requests", async () => {
    const { probe, calls } = rendition(5000)
    expect(await findLastSegment(probe, 12)).toBe(5000)
    expect(calls.length).toBeLessThanOrEqual(40)
  })

  test("uses the duration hint to start close to the tail", async () => {
    const { probe } = rendition(123)
    expect(await findLastSegment(probe, 13)).toBe(123)
  })
})

/** A rendition whose manifest names `listed` parts while `onCdn` parts answer 200. */
function cdn(listed: number | null, onCdn: number) {
  const calls: string[] = []
  const original = globalThis.fetch

  globalThis.fetch = (async (input: string | URL | Request) => {
    const url = String(input)
    calls.push(url)

    if (url.endsWith(".m3u8")) {
      if (listed === null) return new Response("AccessDenied", { status: 403 })
      const parts = Array.from(
        { length: listed },
        (_, index) => `#EXTINF:10.000000,\nHIDDEN2500-${String(index + 1).padStart(5, "0")}.ts`,
      )
      return new Response(["#EXTM3U", "#EXT-X-PLAYLIST-TYPE:VOD", ...parts, "#EXT-X-ENDLIST"].join("\n"))
    }

    const index = Number(/HIDDEN\d+-(\d+)\.ts$/.exec(url)?.[1] ?? 0)
    return new Response(null, { status: index >= 1 && index <= onCdn ? 200 : 403 })
  }) as typeof fetch

  return { calls, restore: () => void (globalThis.fetch = original) }
}

describe("resolveSegments", () => {
  test("takes the tail from the manifest even when the CDN still has stale parts", async () => {
    const stub = cdn(13, 40)
    try {
      const plan = await resolveSegments("manifestwins", 2500, 122)
      expect(plan.count).toBe(13)
      expect(plan.source).toBe("manifest")
      expect(plan.durations).toHaveLength(13)
      expect(plan.duration).toBe(130)
      expect(stub.calls).toHaveLength(1)
    } finally {
      stub.restore()
    }
  })

  test("probes the tail only when the video publishes no manifest", async () => {
    const stub = cdn(null, 13)
    try {
      const plan = await resolveSegments("nomanifest", 2500, 122)
      expect(plan.count).toBe(13)
      expect(plan.source).toBe("probe")
      expect(plan.durations).toEqual([])
      expect(stub.calls.some((url) => url.endsWith(".ts"))).toBe(true)
    } finally {
      stub.restore()
    }
  })

  test("reports a missing rendition rather than an empty file", async () => {
    const stub = cdn(null, 0)
    try {
      await expect(resolveSegments("unpublished", 2500, 122)).rejects.toThrow(/not published|No segments/)
    } finally {
      stub.restore()
    }
  })

  test("costs one request per rendition, whatever the part count", async () => {
    const stub = cdn(null, 4999)
    try {
      await resolveSegments("cachedprobe", 2500, 100)
      const first = stub.calls.length
      expect(first).toBeGreaterThan(1)
      await resolveSegments("cachedprobe", 2500, 100)
      expect(stub.calls.length).toBe(first)
    } finally {
      stub.restore()
    }
  })
})
