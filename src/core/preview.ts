/**
 * Which source a preview plays.
 *
 * A file already on disk wins outright: it seeks instantly, costs no bandwidth,
 * and — because a lot of the catalogue is no longer published on the CDN (every
 * item added after September 2026 answers 403) — it may be the only copy that
 * still exists. Everything else streams from the CDN through this server, so
 * the browser only ever talks to one origin.
 */

import { qualityLabel } from "./cdn.ts"
import type { LibraryEntry } from "./library.ts"

export type PreviewPlan =
  | { mode: "local"; url: string; quality: number | null; label: string; sizeBytes: number }
  | { mode: "remote"; url: string; quality: number; label: string }

/** The downloaded file, served with byte ranges so the player can seek. */
export function mediaUrl(uuid: string, label: string): string {
  const query = label ? `?quality=${encodeURIComponent(label)}` : ""
  return `/api/media/${encodeURIComponent(uuid)}${query}`
}

/** The synthetic VOD playlist, whose parts are proxied by this server. */
export function playlistUrl(uuid: string, quality: number, durationSec: number): string {
  const params = new URLSearchParams({
    quality: String(quality),
    dur: String(Math.max(0, Math.round(durationSec || 0))),
  })
  return `/api/stream/${encodeURIComponent(uuid)}.m3u8?${params.toString()}`
}

/**
 * Prefer the finest rendition that is actually on disk, whatever the requested
 * quality said — the bytes are already paid for, and a 4K request against a
 * 720p download would otherwise re-fetch the whole video.
 */
export function planPreview(
  uuid: string,
  quality: number,
  durationSec: number,
  entries: readonly LibraryEntry[],
): PreviewPlan {
  const local = entries.filter((entry) => entry.uuid === uuid)

  if (local.length) {
    const best = local.reduce((a, b) => ((b.quality ?? 0) > (a.quality ?? 0) ? b : a))
    return {
      mode: "local",
      url: mediaUrl(uuid, best.qualityLabel),
      quality: best.quality,
      label: best.qualityLabel,
      sizeBytes: best.sizeBytes,
    }
  }

  return { mode: "remote", url: playlistUrl(uuid, quality, durationSec), quality, label: qualityLabel(quality) }
}
