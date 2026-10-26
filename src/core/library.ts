/**
 * What is already on disk. A file is named `<NN> - <Title> 1080p.mp4`, so the
 * library is a scan of the content root and the catalogue is what turns a name
 * back into a lesson: the folder and the title have to agree, because the name
 * no longer carries an id. Files written before numbering keep the `[uuid]` that
 * identifies them, and both shapes are read here.
 *
 * The scan is keyed by `uuid:quality` — that key is what makes bulk runs
 * idempotent.
 */

import path from "node:path"
import type { CatalogItem } from "../types/catalog.ts"
import { parseFileName, relativeFolder, sanitizeSegment, type DownloadShape } from "./naming.ts"

export type LibraryEntry = {
  /** The catalogue id, resolved from the folder and title when the name has none. */
  uuid: string
  title: string
  /** The number the file name carries, or null before numbering / for an unnumbered file. */
  number: number | null
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

/** Folder + title, normalised the same way a file name was when it was written. */
function titleKey(title: string): string {
  return sanitizeSegment(title, 90).toLowerCase()
}

function shapeOf(item: CatalogItem): DownloadShape {
  return {
    kind: item.kind,
    title: item.title,
    role: item.role,
    category: item.category,
    courseTitle: item.courseTitle,
  }
}

export type Locator = (folder: string, title: string) => CatalogItem | null

/**
 * Turns `(folder, title)` back into the lesson it is. A title is truncated to the
 * path budget when the file is written, so a name that is a long lesson's
 * opening is accepted as well. The items are walked in id order — the same order
 * the numbering pass uses — so two lessons a folder names alike resolve to the
 * same one on the phone.
 */
export function locateItems(items: readonly CatalogItem[]): Locator {
  const ordered = [...items].sort((first, second) => (first.id < second.id ? -1 : first.id > second.id ? 1 : 0))
  const byFolder = new Map<string, CatalogItem[]>()
  for (const item of ordered) {
    if (item.kind === "course") continue
    const folder = relativeFolder(shapeOf(item))
    const group = byFolder.get(folder) ?? []
    group.push(item)
    byFolder.set(folder, group)
  }

  return (folder, title) => {
    const group = byFolder.get(folder)
    if (!group?.length) return null
    const wanted = titleKey(title)
    const exact = group.find((item) => titleKey(item.title) === wanted)
    if (exact) return exact
    if (wanted.length < 12) return null
    let best: CatalogItem | null = null
    let bestLength = 0
    for (const item of group) {
      const candidate = titleKey(item.title)
      if (candidate.startsWith(wanted) && (best === null || candidate.length < bestLength)) {
        best = item
        bestLength = candidate.length
      }
    }
    return best
  }
}

/** Recursively find every finished download under the content root. */
export async function scanLibrary(root: string, items: readonly CatalogItem[] = []): Promise<LibraryIndex> {
  const glob = new Bun.Glob("**/*.{mp4,ts}")
  const locate = locateItems(items)
  const entries: LibraryEntry[] = []
  const keys = new Set<string>()
  let totalBytes = 0

  for await (const file of glob.scan({ cwd: root, onlyFiles: true })) {
    if (file.startsWith(".skillcapped/")) continue
    const parsed = parseFileName(path.basename(file))
    if (!parsed) continue
    const folder = path.dirname(file) === "." ? "" : path.dirname(file)
    const uuid = parsed.uuid ?? locate(folder, parsed.title)?.id ?? ""
    const stat = await Bun.file(path.join(root, file)).stat().catch(() => null)
    if (!stat) continue

    entries.push({
      uuid,
      title: parsed.title,
      number: parsed.number,
      qualityLabel: parsed.qualityLabel,
      quality: QUALITY_FROM_LABEL[parsed.qualityLabel.toLowerCase()] ?? null,
      extension: parsed.extension,
      relativePath: file,
      folder,
      sizeBytes: stat.size,
      modifiedAt: stat.mtimeMs,
    })
    if (uuid) keys.add(libraryKey(uuid, parsed.qualityLabel))
    totalBytes += stat.size
  }

  entries.sort((a, b) => b.modifiedAt - a.modifiedAt)
  return { entries, keys, totalBytes }
}
