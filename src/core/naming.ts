/**
 * Where a download lands, and what it is called. All filesystem naming rules
 * (including the Windows-specific ones, since the Windows exe is a build
 * target) are applied here so nothing else has to think about them.
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

/**
 * Library layout, relative to the content root:
 *   Videos/<Role>/<Category>/<Title> [uuid] <label>.mp4
 *   Courses/<Role>/<Course>/<Title> [uuid] <label>.mp4
 *   Commentaries/<Role>/<Title> [uuid] <label>.mp4
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

/** `Title [uuid] 1080p.mp4` — the uuid + label is what makes dedupe possible. */
export function buildFileName(title: string, id: string, quality: number, extension: string, maxLength = MAX_SEGMENT): string {
  const suffix = ` [${id}] ${qualityLabel(quality)}.${extension}`
  const room = Math.max(12, maxLength - suffix.length)
  const base = sanitizeSegment(title, room)
  return `${base}${suffix}`
}

/** Absolute destination for a finished file, honouring the path budget. */
export function destinationPath(
  root: string,
  shape: DownloadShape & { id: string },
  quality: number,
  extension: string,
): string {
  const folder = relativeFolder(shape)
  const suffixLength = ` [${shape.id}] ${qualityLabel(quality)}.${extension}`.length
  const room = MAX_PATH - root.length - folder.length - 1 - suffixLength
  const nameBudget = Math.max(12, Math.min(MAX_SEGMENT, room))
  return path.join(root, folder, buildFileName(shape.title, shape.id, quality, extension, nameBudget))
}

/** Filename pattern the library scanner recognises. */
export const FILE_PATTERN = /^(.*?)\s*\[([a-z0-9]{6,12})\]\s*(\d{3,4}p)\.(mp4|ts)$/i

export type ParsedFileName = { title: string; uuid: string; qualityLabel: string; extension: string }

export function parseFileName(name: string): ParsedFileName | null {
  const match = FILE_PATTERN.exec(name)
  if (!match) return null
  return { title: match[1], uuid: match[2], qualityLabel: match[3], extension: match[4] }
}


