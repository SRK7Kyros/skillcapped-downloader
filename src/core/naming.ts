/**
 * Where a download lands, and what it is called. All filesystem naming rules
 * (including the Windows-specific ones, since the Windows exe is a build
 * target) are applied here so nothing else has to think about them.
 *
 * A new download is named `<NN> - <Title> <quality>.<ext>`, the number being its
 * position in the collection it belongs to (a course's own lesson order, or the
 * catalogue order within a videos/commentaries folder) padded to the width of
 * that collection's size — `01 - ` in a ten-lesson course, `1 - ` in a
 * five-lesson one. Nothing else identifies a file on disk: the catalogue is
 * what says which lesson a name is (see `locateItems` in `library.ts`).
 *
 * Files written before the number existed keep their `Title [uuid] 1080p.mp4`
 * name and are still read by `parseFileName`, because a library is not
 * migrated — both shapes coexist.
 */

import path from "node:path"
import type { ItemKind } from "../types/catalog.ts"
import { qualityLabel } from "./cdn.ts"

const ILLEGAL = /[<>:"/\\|?*\u0000-\u001f]/g
const WINDOWS_RESERVED = new Set([
  "con", "prn", "aux", "nul",
  "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
  "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
])

/** Windows caps a whole path at 260 chars; leave room for the root prefix. */
const MAX_SEGMENT = 90
const MAX_PATH = 240

/** Make one path segment safe on every platform we target. */
export function sanitizeSegment(input: string, maxLength = MAX_SEGMENT): string {
  let name = (input ?? "")
    .normalize("NFC")
    .replace(ILLEGAL, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[. ]+$/, "") // Windows silently drops trailing dots/spaces

  if (!name) name = "untitled"
  if (WINDOWS_RESERVED.has(name.toLowerCase())) name = `${name}_`
  if (name.length > maxLength) name = name.slice(0, maxLength).trim().replace(/[. ]+$/, "") || "untitled"
  return name
}

export type DownloadShape = {
  kind: ItemKind
  title: string
  role: string
  category?: string
  courseTitle?: string
}

/** Where a lesson sits in its collection, and how large that collection is. */
export type FileNumber = { index: number; total: number }

/**
 * `01 - ` — the index padded to the number of digits the collection's size
 * needs, so `9 of 9` reads `9 - ` while `9 of 12` reads `09 - ` and the names
 * sort in watching order on every platform.
 */
export function numberPrefix(number: FileNumber): string {
  const width = Math.max(1, String(Math.max(1, number.total)).length)
  return `${String(number.index).padStart(width, "0")} - `
}

/**
 * Library layout, relative to the content root:
 *   Videos/<Role>/<Category>/<NN> - <Title> <label>.mp4
 *   Courses/<Role>/<Course>/<NN> - <Title> <label>.mp4
 *   Commentaries/<Role>/<NN> - <Title> <label>.mp4
 * Grouping by role then course/category is what makes a bulk download usable
 * afterwards.
 */
export function relativeFolder(shape: DownloadShape): string {
  const role = sanitizeSegment(shape.role || "all")
  if (shape.kind === "commentary") return path.join("Commentaries", role)
  if (shape.kind === "course") return path.join("Courses", role, sanitizeSegment(shape.title))
  if (shape.courseTitle) return path.join("Courses", role, sanitizeSegment(shape.courseTitle))
  return path.join("Videos", role, sanitizeSegment(shape.category || "General"))
}

/** `<NN> - <Title> 1080p.mp4`; no number when the lesson is in no collection. */
export function buildFileName(
  title: string,
  number: FileNumber | null,
  quality: number,
  extension: string,
  maxLength = MAX_SEGMENT,
): string {
  const prefix = number ? numberPrefix(number) : ""
  const suffix = ` ${qualityLabel(quality)}.${extension}`
  const room = Math.max(12, maxLength - prefix.length - suffix.length)
  return `${prefix}${sanitizeSegment(title, room)}${suffix}`
}

/** Absolute destination for a finished file, honouring the path budget. */
export function destinationPath(
  root: string,
  shape: DownloadShape & { number?: FileNumber | null },
  quality: number,
  extension: string,
): string {
  const folder = relativeFolder(shape)
  const prefix = shape.number ? numberPrefix(shape.number) : ""
  const suffixLength = prefix.length + ` ${qualityLabel(quality)}.${extension}`.length
  const room = MAX_PATH - root.length - folder.length - 1 - suffixLength
  const nameBudget = Math.max(12, Math.min(MAX_SEGMENT, room))
  return path.join(root, folder, buildFileName(shape.title, shape.number ?? null, quality, extension, nameBudget))
}

/** `Title [uuid] 1080p.mp4` — what every file written before numbering is called. */
export const LEGACY_FILE_PATTERN = /^(.*?)\s*\[([a-z0-9]{6,12})\]\s*(\d{3,4}p)\.(mp4|ts)$/i

/**
 * `01 - Title 1080p.mp4` — what a download is called now. The title is greedy
 * so a lesson whose own title mentions a rendition (`1440p settings`) keeps it
 * and the last quality token is the one that names the file.
 */
export const NUMBERED_FILE_PATTERN = /^(\d+)\s*-\s*(.*)\s+(\d{3,4}p)\.(mp4|ts)$/i

export type ParsedFileName = {
  title: string
  /** Present only on a pre-numbering name. */
  uuid: string | null
  /** Present only on a numbered name. */
  number: number | null
  qualityLabel: string
  extension: string
}

export function parseFileName(name: string): ParsedFileName | null {
  // Legacy first: a title that begins with digits ("3 - Wave Control") would
  // otherwise be read as a number and lose the uuid that identifies it.
  const legacy = LEGACY_FILE_PATTERN.exec(name)
  if (legacy) {
    return { title: legacy[1], uuid: legacy[2], number: null, qualityLabel: legacy[3], extension: legacy[4] }
  }
  const numbered = NUMBERED_FILE_PATTERN.exec(name)
  if (numbered) {
    return {
      title: numbered[2].trim(),
      uuid: null,
      number: Number(numbered[1]),
      qualityLabel: numbered[3],
      extension: numbered[4],
    }
  }
  return null
}
