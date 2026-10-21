import { describe, expect, test } from "bun:test"
import { findLastSegment } from "../../src/core/probe.ts"

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
