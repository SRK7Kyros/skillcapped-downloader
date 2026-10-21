/**
 * The media plane. Every lesson, course video and commentary is served as a
 * numbered sequence of 10-second MPEG-TS parts from one CloudFront
 * distribution; there is no manifest, so the segment list is derived.
 */

export const CDN_ORIGIN = "https://d13z5uuzt1wkbz.cloudfront.net"

/** Segment length is exactly 10 s for every rendition. */
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

/** Fallback segment count when nothing better is known (duration / 10). */
export function expectedSegmentCount(durationSec: number): number {
  return Math.max(1, Math.ceil((durationSec || 0) / SEGMENT_SECONDS))
}

/**
 * A synthetic VOD playlist. There is no upstream manifest, so the list is
 * derived from the probe and every entry is a part on this server.
 */
export function buildPlaylist(uuid: string, quality: number, segmentCount: number, durationSec: number): string {
  const target = Math.max(SEGMENT_SECONDS, Math.ceil(durationSec / Math.max(1, segmentCount)))
  const lines = [
    "#EXTM3U",
    "#EXT-X-VERSION:3",
    "#EXT-X-PLAYLIST-TYPE:VOD",
    `#EXT-X-TARGETDURATION:${target}`,
    "#EXT-X-MEDIA-SEQUENCE:0",
  ]
  for (let index = 1; index <= segmentCount; index++) {
    lines.push(`#EXTINF:${SEGMENT_SECONDS}.0,`, segmentPath(uuid, quality, index))
  }
  lines.push("#EXT-X-ENDLIST")
  return lines.join("\n") + "\n"
}
