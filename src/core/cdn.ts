/**
 * The media plane. Every lesson, course video and commentary is served as a
 * numbered sequence of MPEG-TS parts from one CloudFront distribution, and each
 * rendition publishes its own VOD manifest (`HIDDEN<quality>.m3u8`) listing the
 * parts that belong to it.
 *
 * The manifest is the authority on where a video ends. The distribution also
 * keeps parts from an older, longer encode behind the manifest's last entry —
 * they answer 200 — so probing for the tail downloads footage that is not part
 * of the video (a two-minute lesson arriving as ten minutes, with the stale
 * stretch carrying its own gaps). Only a missing manifest justifies probing.
 */

export const CDN_ORIGIN = "https://d13z5uuzt1wkbz.cloudfront.net"

/** Parts are ten seconds, except the last one, which is whatever is left. */
export const SEGMENT_SECONDS = 10

export type Quality = { id: number; label: string; short: string; height: number }

export const QUALITIES: readonly Quality[] = [
  { id: 1500, label: "720p", short: "720", height: 720 },
  { id: 2500, label: "1080p", short: "1080", height: 1080 },
  { id: 4500, label: "2160p", short: "4K", height: 2160 },
]

export function qualityById(id: number): Quality | undefined {
  return QUALITIES.find((quality) => quality.id === id)
}

export function qualityLabel(id: number): string {
  return qualityById(id)?.label ?? `${id}p`
}

/** `HIDDEN{quality}-{#####}.ts` — the index is 1-based, zero-padded to five. */
export function segmentUrl(uuid: string, quality: number, index: number): string {
  const padded = String(index).padStart(5, "0")
  return `${CDN_ORIGIN}/${uuid}/HIDDEN${quality}-${padded}.ts`
}

/** `HIDDEN{quality}.m3u8` — the rendition's own segment list, published per video. */
export function playlistUrl(uuid: string, quality: number): string {
  return `${CDN_ORIGIN}/${uuid}/HIDDEN${quality}.m3u8`
}

/**
 * The same part, addressed on this server. The preview player streams through
 * `/api/segment/…` instead of straight from CloudFront: one origin for the
 * page, no CORS dependency on someone else's distribution, and a place to
 * answer a missing part with a plain 404 instead of an S3 error document.
 */
export function segmentPath(uuid: string, quality: number, index: number): string {
  const padded = String(index).padStart(5, "0")
  return `/api/segment/${encodeURIComponent(uuid)}/${quality}/${padded}.ts`
}

/** Fallback segment count when no manifest could be read (duration / 10). */
export function expectedSegmentCount(durationSec: number): number {
  return Math.max(1, Math.ceil((durationSec || 0) / SEGMENT_SECONDS))
}

export type Manifest = {
  /** Number of parts the video actually has. */
  count: number
  /** Per-part durations, parallel to the 1-based part index. */
  durations: number[]
  /** Sum of the durations — the video's real length in seconds. */
  duration: number
}

const PART_NAME = /^HIDDEN\d+-(\d+)\.ts$/i

/**
 * Read a rendition manifest. Answers `null` unless every line is understood:
 * an `#EXTM3U` header, one positive `#EXTINF` per part, and part indices that
 * run exactly 1..n. Anything else is a manifest this client cannot trust, and
 * the caller falls back to probing.
 */
export function parseManifest(text: string): Manifest | null {
  const lines = text.split(/\r?\n/)
  if (!lines.some((line) => line.trim().toUpperCase().startsWith("#EXTM3U"))) return null

  const durations: number[] = []
  let pending: number | null = null

  for (const raw of lines) {
    const line = raw.trim()
    if (line === "") continue
    if (line.toUpperCase().startsWith("#EXTINF:")) {
      const seconds = Number.parseFloat(line.slice("#EXTINF:".length))
      pending = Number.isFinite(seconds) && seconds > 0 ? seconds : null
      continue
    }
    if (line.startsWith("#")) continue

    // A URI line closes the entry it follows. Query strings and absolute
    // addresses are both tolerated; only the part number matters.
    const name = (line.split("?")[0] ?? "").split("/").pop() ?? ""
    const match = PART_NAME.exec(name)
    if (!match || pending === null) return null
    if (Number(match[1]) !== durations.length + 1) return null
    durations.push(pending)
    pending = null
  }

  if (durations.length === 0 || pending !== null) return null
  return {
    count: durations.length,
    durations,
    duration: durations.reduce((total, seconds) => total + seconds, 0),
  }
}

/**
 * A synthetic VOD playlist of this server's parts, for the preview player. Pass
 * `durations` from the rendition manifest when it is known so the timeline is
 * the video's real one; without it every part is assumed to be ten seconds.
 */
export function buildPlaylist(
  uuid: string,
  quality: number,
  segmentCount: number,
  durationSec: number,
  durations?: readonly number[],
): string {
  const exact = durations && durations.length === segmentCount ? durations : null
  const target = Math.max(
    SEGMENT_SECONDS,
    Math.ceil(exact ? Math.max(...exact) : durationSec / Math.max(1, segmentCount)),
  )
  const lines = [
    "#EXTM3U",
    "#EXT-X-VERSION:3",
    "#EXT-X-PLAYLIST-TYPE:VOD",
    `#EXT-X-TARGETDURATION:${target}`,
    "#EXT-X-MEDIA-SEQUENCE:0",
  ]
  for (let index = 1; index <= segmentCount; index++) {
    const seconds = exact ? exact[index - 1] : SEGMENT_SECONDS
    lines.push(`#EXTINF:${seconds},`, segmentPath(uuid, quality, index))
  }
  lines.push("#EXT-X-ENDLIST")
  return lines.join("\n") + "\n"
}
