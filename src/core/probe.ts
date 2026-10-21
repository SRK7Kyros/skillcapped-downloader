/**
 * Segment enumeration. There is no upstream playlist, so the tail is found by
 * probing: `-> 403` means the part does not exist, `-> 200` means it does.
 *
 * The search is a bracketing exponential scan followed by a binary search —
 * NOT a walk around `duration / 10`. A duration-derived hint is only a
 * starting point, because an unknown or stale duration must never produce a
 * truncated file, and a 4K feature can run to hundreds of segments.
 */

import { expectedSegmentCount, segmentUrl } from "./cdn.ts"
import { headOk } from "./http.ts"

/** Hard cap so a broken CDN response cannot turn into an unbounded scan. */
const MAX_SEGMENTS = 20_000

const cache = new Map<string, number>()
const cacheKey = (uuid: string, quality: number) => `${uuid}:${quality}`

export class SegmentError extends Error {
  constructor(
    message: string,
    readonly code: "quality_unavailable" | "no_segments",
  ) {
    super(message)
    this.name = "SegmentError"
  }
}

/** Does this rendition exist at all? (index 1 exists for every published video) */
export async function qualityAvailable(uuid: string, quality: number, signal?: AbortSignal): Promise<boolean> {
  return headOk(segmentUrl(uuid, quality, 1), signal)
}

/**
 * Largest segment index that exists. `hint` is the duration-derived estimate;
 * only its magnitude is used, and the true answer is found by probing.
 */
export async function resolveSegmentCount(
  uuid: string,
  quality: number,
  durationSec: number,
  signal?: AbortSignal,
): Promise<number> {
  const memo = cache.get(cacheKey(uuid, quality))
  if (memo !== undefined) return memo

  const probe = (index: number) => headOk(segmentUrl(uuid, quality, index), signal)

  if (!(await probe(1))) {
    throw new SegmentError(`Rendition ${quality} is not published for ${uuid}`, "quality_unavailable")
  }

  const last = await findLastSegment(probe, expectedSegmentCount(durationSec))
  if (last < 1) throw new SegmentError(`No segments found for ${uuid} at ${quality}`, "no_segments")

  cache.set(cacheKey(uuid, quality), last)
  return last
}

type Probe = (index: number) => Promise<boolean>

/**
 * Invariant: `lo` is always an index that exists, `hi` is always one that does
 * not (or the sentinel just past the cap). Ends when the two are adjacent.
 */
export async function findLastSegment(probe: Probe, hint: number): Promise<number> {
  let lo = 1
  let hi = 0

  const anchor = Math.max(2, Math.min(Math.floor(hint) || 2, MAX_SEGMENTS))
  if (await probe(anchor)) {
    lo = anchor
    let step = Math.max(2, anchor)
    while (lo + step <= MAX_SEGMENTS && (await probe(lo + step))) {
      lo += step
      step *= 2
    }
    hi = Math.min(lo + step, MAX_SEGMENTS + 1)
  } else {
    hi = anchor
  }

  while (lo + 1 < hi) {
    const mid = (lo + hi) >> 1
    if (await probe(mid)) lo = mid
    else hi = mid
  }
  return lo
}
