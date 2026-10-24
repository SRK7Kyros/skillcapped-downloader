/**
 * Segment enumeration.
 *
 * A rendition's own manifest is read first: it lists exactly the parts that
 * belong to the video, so its last entry is where the video ends. That matters,
 * because the distribution also keeps 200-answering parts from an older, longer
 * encode behind that entry — probing for the tail happily appends them.
 *
 * Only when a video publishes no manifest is the tail found by probing:
 * `-> 403` means the part does not exist, `-> 200` means it does. The search is
 * a bracketing exponential scan followed by a binary search — NOT a walk around
 * `duration / 10`, because an unknown or stale duration must never produce a
 * truncated file, and a 4K feature can run to hundreds of parts.
 */

import { expectedSegmentCount, parseManifest, playlistUrl, SEGMENT_SECONDS, segmentUrl } from "./cdn.ts"
import { fetchWithRetry, headOk } from "./http.ts"

/** Hard cap so a broken CDN response cannot turn into an unbounded scan. */
const MAX_SEGMENTS = 20_000

const cache = new Map<string, SegmentPlan>()
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

export type SegmentPlan = {
  count: number
  /** Per-part durations from the manifest; empty when the tail was probed. */
  durations: number[]
  /** The video's length in seconds, exact when a manifest was read. */
  duration: number
  source: "manifest" | "probe"
}

/** Does this rendition exist at all? (index 1 exists for every published video) */
export async function qualityAvailable(uuid: string, quality: number, signal?: AbortSignal): Promise<boolean> {
  return headOk(segmentUrl(uuid, quality, 1), signal)
}

/**
 * The parts that belong to this rendition: from its manifest when it has one,
 * otherwise from a probe of the tail.
 */
export async function resolveSegments(
  uuid: string,
  quality: number,
  durationSec: number,
  signal?: AbortSignal,
): Promise<SegmentPlan> {
  const key = cacheKey(uuid, quality)
  const memo = cache.get(key)
  if (memo) return memo

  const manifest = await readManifest(uuid, quality, signal)
  if (manifest) {
    cache.set(key, manifest)
    return manifest
  }

  const probe = (index: number) => headOk(segmentUrl(uuid, quality, index), signal)

  if (!(await probe(1))) {
    throw new SegmentError(`Rendition ${quality} is not published for ${uuid}`, "quality_unavailable")
  }

  const last = await findLastSegment(probe, expectedSegmentCount(durationSec))
  if (last < 1) throw new SegmentError(`No segments found for ${uuid} at ${quality}`, "no_segments")

  const plan: SegmentPlan = {
    count: last,
    durations: [],
    duration: last * SEGMENT_SECONDS,
    source: "probe",
  }
  cache.set(key, plan)
  return plan
}

/** Largest segment index that exists — the manifest's length when there is one. */
export async function resolveSegmentCount(
  uuid: string,
  quality: number,
  durationSec: number,
  signal?: AbortSignal,
): Promise<number> {
  return (await resolveSegments(uuid, quality, durationSec, signal)).count
}

/**
 * The rendition's published manifest, or `null` when it has none. A transient
 * failure is retried: falling back to the probe after one flaky response is how
 * stale parts get appended again.
 */
async function readManifest(
  uuid: string,
  quality: number,
  signal?: AbortSignal,
): Promise<SegmentPlan | null> {
  try {
    const response = await fetchWithRetry(playlistUrl(uuid, quality), { attempts: 3, signal })
    if (!response.ok) return null
    const manifest = parseManifest(await response.text())
    if (!manifest) return null
    return {
      count: manifest.count,
      durations: manifest.durations,
      duration: manifest.duration,
      source: "manifest",
    }
  } catch (error) {
    if ((error as Error)?.name === "AbortError") throw error
    return null
  }
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
