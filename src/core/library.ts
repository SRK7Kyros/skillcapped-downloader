/**
 * What is already on disk. Files are named `Title [uuid] 1080p.mp4`, so the
 * library is a scan of the content root keyed by `uuid:quality` — that key is
 * what makes bulk runs idempotent.
 */

import path from "node:path"
import { parseFileName } from "./naming.ts"

export type LibraryEntry = {
  uuid: string
  title: string
  qualityLabel: string
  quality: number | null
  extension: string
  /** Path relative to the content root. */
  relativePath: string
  folder: string
  sizeBytes: number
  modifiedAt: number
}

export type LibraryIndex = {
  entries: LibraryEntry[]
  keys: Set<string>
  totalBytes: number
}

const QUALITY_FROM_LABEL: Record<string, number> = { "720p": 1500, "1080p": 2500, "2160p": 4500 }

export const libraryKey = (uuid: string, qualityLabel: string) => `${uuid}:${qualityLabel}`

/** Recursively find every finished download under the content root. */
export async function scanLibrary(root: string): Promise<LibraryIndex> {
  const glob = new Bun.Glob("**/*.{mp4,ts}")
  const entries: LibraryEntry[] = []
  const keys = new Set<string>()
  let totalBytes = 0

  for await (const file of glob.scan({ cwd: root, onlyFiles: true })) {
    if (file.startsWith(".skillcapped/")) continue
    const parsed = parseFileName(path.basename(file))
    if (!parsed) continue
    const stat = await Bun.file(path.join(root, file)).stat().catch(() => null)
    if (!stat) continue

    const normalizedLabel = QUALITY_FROM_LABEL[parsed.qualityLabel.toLowerCase()] ? parsed.qualityLabel : parsed.qualityLabel
    entries.push({
      uuid: parsed.uuid,
      title: parsed.title,
      qualityLabel: normalizedLabel,
      quality: QUALITY_FROM_LABEL[parsed.qualityLabel.toLowerCase()] ?? null,
      extension: parsed.extension,
      relativePath: file,
      folder: path.dirname(file) === "." ? "" : path.dirname(file),
      sizeBytes: stat.size,
      modifiedAt: stat.mtimeMs,
    })
    keys.add(libraryKey(parsed.uuid, normalizedLabel))
    totalBytes += stat.size
  }

  entries.sort((a, b) => b.modifiedAt - a.modifiedAt)
  return { entries, keys, totalBytes }
}
