/**
 * Wire types for the local API, plus a tolerant reader for each response. The
 * catalogue is a few million characters of third-party data, so parsing is
 * permissive: one odd record must not blank the browse page.
 */

import { z } from "zod"

export type ItemKind = "video" | "commentary" | "course"

export type CatalogItem = {
  id: string
  kind: ItemKind
  title: string
  role: string
  durationSec: number
  date: number
  category: string
  tags: string[]
  thumb: string
  courseTitle?: string
  lessonIds?: string[]
  videoCount?: number
  staff?: string
  champions?: string
  kda?: string
}

export type CatalogResponse = {
  season: string
  patch: string
  generatedAt: number
  dumpUrl: string
  roles: string[]
  categories: string[]
  items: CatalogItem[]
  note: string | null
}

export type Quality = { id: number; label: string; short: string; height: number }

export type ToolInfo = { path: string; source: string; version: string } | null

export type Meta = {
  app: string
  version: string
  standalone: boolean
  contentDir: string
  stateDir: string
  tmpDir: string
  appDir: string
  execPath: string
  port: number
  startedAt: number
  uiBytes: number
  qualities: Quality[]
  defaults: { quality: number; remux: boolean; concurrency: number }
  tools: { ffmpeg: ToolInfo; ffprobe: ToolInfo }
}

export type JobStatus =
  | "queued"
  | "resolving"
  | "downloading"
  | "remuxing"
  | "done"
  | "failed"
  | "cancelled"
  | "interrupted"

export type JobRecord = {
  id: string
  uuid: string
  kind: ItemKind
  title: string
  role: string
  durationSec: number
  quality: number
  qualityLabel: string
  actualQuality: number | null
  remux: boolean
  status: JobStatus
  segmentsDone: number
  segmentsTotal: number
  bytes: number
  bytesTotal: number
  speedBps: number
  relativePath: string | null
  sizeBytes: number | null
  remuxed: boolean | null
  error: string | null
  note: string | null
  groupId: string | null
  groupTitle: string | null
  createdAt: number
  startedAt: number | null
  finishedAt: number | null
}

export type LibraryEntry = {
  uuid: string
  title: string
  qualityLabel: string
  quality: number | null
  extension: string
  relativePath: string
  folder: string
  sizeBytes: number
  modifiedAt: number
}

export type LibraryResponse = {
  count: number
  totalBytes: number
  contentDir: string
  entries: LibraryEntry[]
}

export type CreateJobsResponse = {
  created: JobRecord[]
  skipped: Array<{ id: string; title: string }>
  missing: string[]
  expanded: number
}

const itemSchema = z.object({
  id: z.string(),
  kind: z.enum(["video", "commentary", "course"]),
  title: z.string(),
  role: z.string().catch("all"),
  durationSec: z.number().catch(0),
  date: z.number().catch(0),
  category: z.string().catch(""),
  tags: z.array(z.string()).catch([]),
  thumb: z.string().catch(""),
  courseTitle: z.string().optional(),
  lessonIds: z.array(z.string()).optional(),
  videoCount: z.number().optional(),
  staff: z.string().optional(),
  champions: z.string().optional(),
  kda: z.string().optional(),
})

export const catalogSchema = z.object({
  season: z.string().catch(""),
  patch: z.string().catch(""),
  generatedAt: z.number().catch(0),
  dumpUrl: z.string().catch(""),
  roles: z.array(z.string()).catch(["all"]),
  categories: z.array(z.string()).catch([]),
  items: z.array(itemSchema).catch([]),
  note: z.string().nullable().catch(null),
})

const jobSchema = z.object({
  id: z.string(),
  uuid: z.string(),
  kind: z.enum(["video", "commentary", "course"]),
  title: z.string(),
  role: z.string().catch("all"),
  durationSec: z.number().catch(0),
  quality: z.number().catch(0),
  qualityLabel: z.string().catch(""),
  actualQuality: z.number().nullable().catch(null),
  remux: z.boolean().catch(true),
  status: z.enum([
    "queued",
    "resolving",
    "downloading",
    "remuxing",
    "done",
    "failed",
    "cancelled",
    "interrupted",
  ]),
  segmentsDone: z.number().catch(0),
  segmentsTotal: z.number().catch(0),
  bytes: z.number().catch(0),
  bytesTotal: z.number().catch(0),
  speedBps: z.number().catch(0),
  relativePath: z.string().nullable().catch(null),
  sizeBytes: z.number().nullable().catch(null),
  remuxed: z.boolean().nullable().catch(null),
  error: z.string().nullable().catch(null),
  note: z.string().nullable().catch(null),
  groupId: z.string().nullable().catch(null),
  groupTitle: z.string().nullable().catch(null),
  createdAt: z.number().catch(0),
  startedAt: z.number().nullable().catch(null),
  finishedAt: z.number().nullable().catch(null),
})

export const jobsResponseSchema = z.object({ jobs: z.array(jobSchema).catch([]) })
export const jobSchemaExport = jobSchema

export const createJobsSchema = z.object({
  created: z.array(jobSchema).catch([]),
  skipped: z.array(z.object({ id: z.string(), title: z.string() })).catch([]),
  missing: z.array(z.string()).catch([]),
  expanded: z.number().catch(0),
})

export const metaSchema = z.object({
  app: z.string().catch("skillcapped-downloader"),
  version: z.string().catch(""),
  standalone: z.boolean().catch(false),
  contentDir: z.string().catch(""),
  stateDir: z.string().catch(""),
  tmpDir: z.string().catch(""),
  appDir: z.string().catch(""),
  execPath: z.string().catch(""),
  port: z.number().catch(0),
  startedAt: z.number().catch(0),
  uiBytes: z.number().catch(0),
  qualities: z
    .array(z.object({ id: z.number(), label: z.string(), short: z.string(), height: z.number() }))
    .catch([]),
  defaults: z
    .object({ quality: z.number().catch(2500), remux: z.boolean().catch(true), concurrency: z.number().catch(3) })
    .catch({ quality: 2500, remux: true, concurrency: 3 }),
  tools: z
    .object({ ffmpeg: z.any().catch(null), ffprobe: z.any().catch(null) })
    .catch({ ffmpeg: null, ffprobe: null }),
})

export const librarySchema = z.object({
  count: z.number().catch(0),
  totalBytes: z.number().catch(0),
  contentDir: z.string().catch(""),
  entries: z
    .array(
      z.object({
        uuid: z.string(),
        title: z.string(),
        qualityLabel: z.string().catch(""),
        quality: z.number().nullable().catch(null),
        extension: z.string().catch("mp4"),
        relativePath: z.string(),
        folder: z.string().catch(""),
        sizeBytes: z.number().catch(0),
        modifiedAt: z.number().catch(0),
      }),
    )
    .catch([]),
})

/** Where the preview player should load this video from. */
export const previewSchema = z.object({
  uuid: z.string(),
  durationSec: z.number().catch(0),
  mode: z.enum(["local", "remote"]).catch("remote"),
  url: z.string(),
  quality: z.number().nullable().catch(null),
  label: z.string().catch(""),
  sizeBytes: z.number().catch(0),
})

export type PreviewInfo = z.infer<typeof previewSchema>
