/**
 * Catalogue acquisition. The public course dump URL is not stable — it is
 * versioned by a timestamp and its location is published in a Firestore
 * document the site reads at runtime. So: discover, fetch, normalise, cache.
 */

import { mkdir, readFile, writeFile } from "node:fs/promises"
import path from "node:path"
import { stateDir } from "../paths.ts"
import { dumpSchema, type Catalog, type CatalogItem, type Dump } from "../types/catalog.ts"
import { fetchWithRetry } from "./http.ts"

const FIREBASE_API_KEY = "AIzaSyAgHWuN2OEx5R827dHlKO9HsOuBwZ017n0"
const LOCATION_DOC = `https://firestore.googleapis.com/v1/projects/sc-site-a8f24/databases/(default)/documents/content-location/lol-content-location?key=${FIREBASE_API_KEY}`

/** Canonical role order, matching the site's tab strip. */
export const ROLES = ["all", "top", "jungle", "mid", "adc", "support"] as const

const TITLE_ROLE_LABELS: Record<string, string> = {
  all: "All Roles",
  top: "Top",
  jungle: "Jungle",
  mid: "Mid",
  adc: "ADC",
  support: "Support",
}

/**
 * Course titles in the dump carry a `{role}` token the site substitutes when it
 * renders — 324 of 334 of them. The token can differ from the course's own
 * `role`, so it is information rather than noise: `Wave Control {top}` becomes
 * `Wave Control (Top)`. An unknown token is left untouched.
 */
export function displayTitle(raw: string): string {
  return raw.replace(/\{([a-z]+)\}/gi, (match, token: string) => {
    const label = TITLE_ROLE_LABELS[token.toLowerCase()]
    return label ? `(${label})` : match
  })
}

export class CatalogError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "CatalogError"
  }
}

/** Read the current dump URL out of the public content-location document. */
export async function discoverDumpUrl(signal?: AbortSignal): Promise<string> {
  const response = await fetchWithRetry(LOCATION_DOC, { attempts: 3, signal })
  if (!response.ok) throw new CatalogError(`content-location lookup failed (HTTP ${response.status})`)
  const document = (await response.json()) as { fields?: { dumpUrl?: { stringValue?: string } } }
  const url = document.fields?.dumpUrl?.stringValue
  if (!url) throw new CatalogError("content-location document carried no dumpUrl")
  return url
}

/** Fetch + validate the dump. */
export async function fetchDump(signal?: AbortSignal): Promise<{ dump: Dump; url: string }> {
  const url = await discoverDumpUrl(signal)
  const response = await fetchWithRetry(url, { attempts: 3, signal })
  if (!response.ok) throw new CatalogError(`course dump fetch failed (HTTP ${response.status})`)
  const parsed = dumpSchema.safeParse(await response.json())
  if (!parsed.success) throw new CatalogError("course dump did not match the expected shape")
  return { dump: parsed.data, url }
}

/**
 * Flatten the dump into rows the UI can render and filter locally.
 * Newest first, so the browse page opens on current content.
 */
export function buildCatalog(dump: Dump, dumpUrl: string): Catalog {
  const tagName = (tId: number) => dump.tagInfo[tId]?.name ?? ""
  const courseOfVideo = new Map<string, string>()
  const lessonIdsByTitle = new Map<string, string[]>()

  for (const [rawTitle, entry] of Object.entries(dump.videosToCourses)) {
    const title = displayTitle(rawTitle)
    const lessonIds = entry.chapters.flatMap((chapter) => chapter.vids.map((vid) => vid.uuid)).filter(Boolean)
    lessonIdsByTitle.set(title, lessonIds)
    for (const id of lessonIds) if (!courseOfVideo.has(id)) courseOfVideo.set(id, title)
  }

  const items: CatalogItem[] = []

  for (const video of dump.videos) {
    if (!video.uuid) continue
    const category = tagName(video.tId)
    const courseTitle = courseOfVideo.get(video.uuid)
    items.push({
      id: video.uuid,
      kind: "video",
      title: video.title || video.uuid,
      role: video.role || "all",
      durationSec: video.durSec,
      date: video.rDate,
      category,
      tags: [category, video.role].filter(Boolean),
      thumb: video.tSS,
      courseTitle,
    })
  }

  for (const commentary of dump.commentaries) {
    if (!commentary.uuid) continue
    const category = tagName(commentary.tId)
    items.push({
      id: commentary.uuid,
      kind: "commentary",
      title: commentary.staff ? `${commentary.staff} — ${commentary.yourChampion || "Smurf"}` : `Commentary ${commentary.uuid}`,
      role: commentary.role || "all",
      durationSec: commentary.durSec,
      date: commentary.rDate,
      category,
      tags: [category, commentary.role, commentary.staff, commentary.yourChampion].filter(Boolean),
      thumb: commentary.tSS,
      staff: commentary.staff,
      champions: [commentary.yourChampion, commentary.theirChampion].filter(Boolean).join(" vs "),
      kda: `${commentary.k}/${commentary.d}/${commentary.a}`,
    })
  }

  for (const course of dump.courses) {
    if (!course.uuid) continue
    const title = displayTitle(course.title || course.uuid)
    const lessonIds = lessonIdsByTitle.get(title) ?? []
    items.push({
      id: course.uuid,
      kind: "course",
      title,
      role: course.role || "all",
      durationSec: 0,
      date: course.rDate,
      category: course.tags[course.tags.length - 1] ?? "",
      tags: course.tags,
      thumb: course.courseImage3 || course.courseImage2 || course.courseImage,
      lessonIds,
      videoCount: lessonIds.length,
    })
  }

  items.sort((a, b) => b.date - a.date)

  const categories = [...new Set(items.flatMap((item) => item.tags))].filter(Boolean).sort((a, b) => a.localeCompare(b))

  return {
    season: dump.seasonLabel,
    patch: dump.patch.patchVal,
    generatedAt: Date.now(),
    dumpUrl,
    roles: [...ROLES],
    categories,
    items,
  }
}

type LoadOptions = {
  root: string
  /** Reuse a cache younger than this. */
  maxAgeMs?: number
  force?: boolean
  signal?: AbortSignal
  onNote?: (message: string) => void
}

/**
 * Catalog with a disk cache. A network failure falls back to the newest cached
 * copy so the browse page still works offline; only a cold start with no
 * network at all is fatal.
 */
export async function loadCatalog(options: LoadOptions): Promise<Catalog> {
  const { root, maxAgeMs = 30 * 60 * 1000, force = false, signal, onNote } = options
  const cachePath = path.join(stateDir(root), "catalog.json")

  if (!force) {
    const cached = await readCache(cachePath)
    if (cached && Date.now() - cached.generatedAt < maxAgeMs) return cached
  }

  try {
    const { dump, url } = await fetchDump(signal)
    const catalog = buildCatalog(dump, url)
    await mkdir(stateDir(root), { recursive: true })
    await writeFile(cachePath, JSON.stringify(catalog), "utf8")
    return catalog
  } catch (error) {
    if (signal?.aborted) throw error
    const cached = await readCache(cachePath)
    if (cached) {
      onNote?.(`Live catalogue unavailable (${(error as Error).message}) — serving the cached copy.`)
      return { ...cached, generatedAt: Date.now() }
    }
    throw error
  }
}

async function readCache(cachePath: string): Promise<Catalog | null> {
  try {
    const raw = await readFile(cachePath, "utf8")
    const parsed = JSON.parse(raw) as Catalog
    return Array.isArray(parsed.items) && parsed.items.length > 0 ? parsed : null
  } catch {
    return null
  }
}
