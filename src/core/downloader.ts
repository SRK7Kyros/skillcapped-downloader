/**
 * One download, from segment list to finished file.
 *
 *   resolve rendition -> probe the tail -> fetch parts in parallel ->
 *   concatenate in order -> (optionally) remux -> atomic rename into place
 *
 * Scratch lives under `<content>/.skillcapped/tmp/<jobId>` — the same
 * filesystem as the destination, so the final move is an atomic rename. The
 * merged `.ts` is a valid artifact on its own, so a missing or failing ffmpeg
 * degrades to "keep the transport stream" rather than losing the download.
 */

import { mkdir, rename, rm, unlink } from "node:fs/promises"
import { existsSync } from "node:fs"
import path from "node:path"
import type { Tool } from "../paths.ts"
import type { ItemKind } from "../types/catalog.ts"
import { QUALITIES, qualityLabel, segmentUrl } from "./cdn.ts"
import { RemuxError, probeDuration, remuxToMp4 } from "./ffmpeg.ts"
import { Semaphore, fetchWithRetry } from "./http.ts"
import { destinationPath, type DownloadShape, type FileNumber } from "./naming.ts"
import { SegmentError, qualityAvailable, resolveSegmentCount } from "./probe.ts"

export type DownloadRequest = DownloadShape & {
  /** Job id — also the scratch folder name. */
  jobId: string
  /** The media uuid (lesson, commentary or course video). */
  uuid: string
  durationSec: number
  /** Position in its collection — the leading number of the file name. */
  number?: FileNumber | null
  quality: number
  remux: boolean
}

export type DownloadContext = {
  contentDir: string
  scratchDir: string
  ffmpeg: Tool | null
  segmentConcurrency: number
}

export type ProgressUpdate = {
  segmentsDone: number
  segmentsTotal: number
  bytes: number
  bytesTotal: number
}

export type DownloadResult = {
  /** Path relative to the content root. */
  relativePath: string
  absolutePath: string
  sizeBytes: number
  segments: number
  /** The rendition actually downloaded (may be lower than requested). */
  quality: number
  qualityFellBack: boolean
  remuxed: boolean
  note?: string
}

/** Preferred rendition first, then every lower one as a fallback. */
function qualityLadder(requested: number): number[] {
  const ordered = [...QUALITIES].sort((a, b) => b.id - a.id).map((quality) => quality.id)
  const start = ordered.indexOf(requested)
  return start === -1 ? ordered : ordered.slice(start)
}

export async function runDownload(
  request: DownloadRequest,
  context: DownloadContext,
  signal: AbortSignal,
  onProgress: (update: ProgressUpdate) => void,
): Promise<DownloadResult> {
  // 1. Pick a rendition that actually exists.
  let quality = request.quality
  let qualityFellBack = false
  let available = false
  for (const candidate of qualityLadder(request.quality)) {
    if (await qualityAvailable(request.uuid, candidate, signal)) {
      available = true
      qualityFellBack = candidate !== request.quality
      quality = candidate
      break
    }
  }
  if (!available) {
    throw new SegmentError(`No published rendition for ${request.uuid}`, "quality_unavailable")
  }

  // 2. Enumerate segments.
  const segmentsTotal = await resolveSegmentCount(request.uuid, quality, request.durationSec, signal)

  const jobDir = path.join(context.scratchDir, request.jobId)
  await mkdir(jobDir, { recursive: true })

  let bytes = 0
  let segmentsDone = 0
  let bytesTotal = 0
  let firstSegmentBytes = 0

  const pool = new Semaphore(Math.max(1, context.segmentConcurrency))
  const parts = new Map<number, string>()

  const fetchSegment = (index: number) =>
    pool.run(async () => {
      const url = segmentUrl(request.uuid, quality, index)
      const partPath = path.join(jobDir, `${String(index).padStart(5, "0")}.ts`)

      // A 403 past the tail is expected; a 403 in the middle is transient
      // throttling — retry it once before giving up. Never truncate silently.
      const response = await fetchWithRetry(url, { attempts: 3, retryStatuses: [403], signal })
      if (!response.ok) {
        throw new Error(`segment ${index} failed (HTTP ${response.status})`)
      }
      const buffer = Buffer.from(await response.arrayBuffer())
      if (buffer.byteLength === 0) throw new Error(`segment ${index} came back empty`)
      await Bun.write(partPath, buffer)

      parts.set(index, partPath)
      bytes += buffer.byteLength
      segmentsDone++
      if (index === 1) firstSegmentBytes = buffer.byteLength
      bytesTotal = firstSegmentBytes > 0 ? firstSegmentBytes * segmentsTotal : bytes
      onProgress({ segmentsDone, segmentsTotal, bytes, bytesTotal })
    })

  try {
    await Promise.all(Array.from({ length: segmentsTotal }, (_, offset) => fetchSegment(offset + 1)))

    // 3. Concatenate in order, releasing each part as it is consumed so peak
    //    disk usage is roughly one copy of the video plus a single segment.
    const mergedTs = path.join(jobDir, "merged.ts")
    const sink = Bun.file(mergedTs).writer({ highWaterMark: 1024 * 1024 })
    for (let index = 1; index <= segmentsTotal; index++) {
      const partPath = parts.get(index)
      if (!partPath) throw new Error(`segment ${index} is missing before merge`)
      sink.write(await Bun.file(partPath).arrayBuffer())
      await unlink(partPath).catch(() => {})
    }
    await sink.end()

    const tsSize = Bun.file(mergedTs).size
    const extension = request.remux && context.ffmpeg ? "mp4" : "ts"
    const destination = destinationPath(context.contentDir, request, quality, extension)
    await mkdir(path.dirname(destination), { recursive: true })

    // 4. Remux, or keep the transport stream.
    if (extension === "mp4") {
      const partial = `${destination}.part`
      try {
        await remuxToMp4(context.ffmpeg!, mergedTs, partial, signal)
        const produced = existsSync(partial) ? Bun.file(partial).size : 0
        // A truncated remux is worse than none: verify before publishing.
        const expected = await probeDurationSafe(context.ffmpeg!, request.durationSec, mergedTs)
        const actual = await probeDuration(context.ffmpeg!, partial)
        const suspicious = produced === 0 || (expected !== null && actual !== null && actual < expected - 20)
        if (suspicious) throw new RemuxError("remuxed output failed its duration check")

        await rename(partial, destination)
        await rm(jobDir, { recursive: true, force: true })
        return {
          relativePath: path.relative(context.contentDir, destination),
          absolutePath: destination,
          sizeBytes: produced,
          segments: segmentsTotal,
          quality,
          qualityFellBack,
          remuxed: true,
        }
      } catch (error) {
        if (signal.aborted) throw error
        // Keep the perfectly good transport stream instead of nothing — under a
        // `.ts` name, because that is what the bytes actually are.
        const fallback = destinationPath(context.contentDir, request, quality, "ts")
        await Bun.write(fallback, Bun.file(mergedTs))
        await rm(partial, { force: true }).catch(() => {})
        await rm(jobDir, { recursive: true, force: true })
        return {
          relativePath: path.relative(context.contentDir, fallback),
          absolutePath: fallback,
          sizeBytes: Bun.file(fallback).size,
          segments: segmentsTotal,
          quality,
          qualityFellBack,
          remuxed: false,
          note: `Remux skipped (${(error as Error).message}) — kept the .ts transport stream.`,
        }
      }
    }

    await Bun.write(destination, Bun.file(mergedTs))
    await rm(jobDir, { recursive: true, force: true })
    return {
      relativePath: path.relative(context.contentDir, destination),
      absolutePath: destination,
      sizeBytes: Bun.file(destination).size || tsSize,
      segments: segmentsTotal,
      quality,
      qualityFellBack,
      remuxed: false,
    }
  } catch (error) {
    await rm(jobDir, { recursive: true, force: true }).catch(() => {})
    throw error
  }
}

async function probeDurationSafe(tool: Tool, fallback: number, file: string): Promise<number | null> {
  const probed = await probeDuration(tool, file)
  return probed ?? (fallback > 0 ? fallback : null)
}

export { qualityLabel }
export type { ItemKind }
