/**
 * The download queue. Owns job records, concurrency, cancellation and the
 * event stream the browser subscribes to. The route layer hands it fully
 * resolved specs (courses arrive pre-expanded), so this file only has to worry
 * about running downloads.
 */

import { randomUUID } from "node:crypto"
import path from "node:path"
import type { Tool } from "../paths.ts"
import type { ItemKind } from "../types/catalog.ts"
import { qualityLabel } from "./cdn.ts"
import { runDownload } from "./downloader.ts"
import type { FileNumber } from "./naming.ts"
import { Emitter } from "./events.ts"
import { createDebouncedSaver, sweepScratch } from "./jobs-store.ts"

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
  /** Decides the on-disk folder: category groups plain videos, courseTitle groups lessons. */
  category: string | null
  courseTitle: string | null
  /** Position in its collection, which is what the file name starts with. */
  number: FileNumber | null
  /** Video length from the catalogue — drives the segment-count estimate. */
  durationSec: number
  quality: number
  qualityLabel: string
  /** Set when the rendition actually used differs from the requested one. */
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
  /** Course membership, so grouped bulk runs read as one thing. */
  groupId: string | null
  groupTitle: string | null
  createdAt: number
  startedAt: number | null
  finishedAt: number | null
}

/** A concrete download, resolved by the route layer. */
export type JobSpec = {
  uuid: string
  kind: ItemKind
  title: string
  role: string
  durationSec: number
  category?: string
  courseTitle?: string
  /** Position in its collection; null when the catalogue does not place it. */
  number?: FileNumber | null
  groupId?: string
  groupTitle?: string
}

export type ManagerOptions = {
  contentDir: string
  ffmpeg: Tool | null
  concurrency: number
  segmentConcurrency: number
  /** 4K is bandwidth-hungry; allow only one at a time. */
  highQualityConcurrency?: number
}

type Events = {
  changed: JobRecord
  removed: { id: string }
  /** A job reached a terminal state and the on-disk library changed. */
  settled: JobRecord
}

const HIGH_QUALITY = 4500
const PROGRESS_INTERVAL_MS = 250

export class DownloadManager {
  readonly events = new Emitter<Events>()
  private jobs = new Map<string, JobRecord>()
  private queue: string[] = []
  private controllers = new Map<string, AbortController>()
  private active = 0
  private activeHigh = 0
  private lastEmit = new Map<string, number>()
  private saver: ReturnType<typeof createDebouncedSaver>

  constructor(private readonly options: ManagerOptions) {
    this.saver = createDebouncedSaver(options.contentDir)
  }

  /** Restore a persisted queue and clear stale scratch files. */
  async restore(persisted: JobRecord[]): Promise<void> {
    await sweepScratch(this.options.contentDir)
    for (const job of persisted) {
      if (job.status === "queued" || job.status === "cancelled" || job.status === "done" || job.status === "failed") {
        this.jobs.set(job.id, { ...job })
      } else {
        // Was mid-flight when the process stopped — it never finished.
        this.jobs.set(job.id, { ...job, status: "interrupted", error: "Interrupted — the app closed mid-download." })
      }
      if (job.status === "queued") this.queue.push(job.id)
    }
    this.pump()
  }

  list(): JobRecord[] {
    return [...this.jobs.values()].sort((a, b) => b.createdAt - a.createdAt)
  }

  get(id: string): JobRecord | undefined {
    return this.jobs.get(id)
  }

  /** Add specs to the queue; returns the created records. */
  add(specs: JobSpec[], quality: number, remux: boolean): JobRecord[] {
    const created: JobRecord[] = []
    for (const spec of specs) {
      const record: JobRecord = {
        id: randomUUID(),
        uuid: spec.uuid,
        kind: spec.kind,
        title: spec.title,
        role: spec.role,
        category: spec.category ?? null,
        courseTitle: spec.courseTitle ?? null,
        number: spec.number ?? null,
        durationSec: spec.durationSec,
        quality,
        qualityLabel: qualityLabel(quality),
        actualQuality: null,
        remux,
        status: "queued",
        segmentsDone: 0,
        segmentsTotal: 0,
        bytes: 0,
        bytesTotal: 0,
        speedBps: 0,
        relativePath: null,
        sizeBytes: null,
        remuxed: null,
        error: null,
        note: null,
        groupId: spec.groupId ?? null,
        groupTitle: spec.groupTitle ?? null,
        createdAt: Date.now(),
        startedAt: null,
        finishedAt: null,
      }
      this.jobs.set(record.id, record)
      this.queue.push(record.id)
      created.push(record)
    }
    this.persist()
    for (const record of created) this.emitChanged(record, true)
    this.pump()
    return created
  }

  cancel(id: string): boolean {
    const job = this.jobs.get(id)
    if (!job) return false
    if (job.status === "queued") {
      this.queue = this.queue.filter((queued) => queued !== id)
      this.update(job, { status: "cancelled", finishedAt: Date.now() })
      this.persist()
      return true
    }
    if (job.status === "resolving" || job.status === "downloading" || job.status === "remuxing") {
      this.controllers.get(id)?.abort()
      return true
    }
    return false
  }

  /** Requeue a finished/failed job, reusing its resolution if the file is gone. */
  retry(id: string): boolean {
    const job = this.jobs.get(id)
    if (!job) return false
    if (!["failed", "cancelled", "interrupted"].includes(job.status)) return false
    this.update(job, {
      status: "queued",
      error: null,
      note: null,
      segmentsDone: 0,
      segmentsTotal: 0,
      bytes: 0,
      bytesTotal: 0,
      speedBps: 0,
      startedAt: null,
      finishedAt: null,
      relativePath: null,
      sizeBytes: null,
      remuxed: null,
      actualQuality: null,
    })
    this.queue.push(id)
    this.persist()
    this.pump()
    return true
  }

  remove(id: string): boolean {
    const job = this.jobs.get(id)
    if (!job) return false
    if (["resolving", "downloading", "remuxing", "queued"].includes(job.status)) this.cancel(id)
    this.jobs.delete(id)
    this.queue = this.queue.filter((queued) => queued !== id)
    this.events.emit("removed", { id })
    this.persist()
    return true
  }

  /** Clear every finished/failed/cancelled row. */
  clearSettled(): void {
    for (const job of this.list()) {
      if (["done", "failed", "cancelled", "interrupted"].includes(job.status)) {
        this.jobs.delete(job.id)
        this.events.emit("removed", { id: job.id })
      }
    }
    this.persist()
  }

  async shutdown(): Promise<void> {
    for (const controller of this.controllers.values()) controller.abort()
    await this.saver.flush()
  }

  private canStart(job: JobRecord): boolean {
    if (job.quality < HIGH_QUALITY) return true
    return this.activeHigh < (this.options.highQualityConcurrency ?? 1)
  }

  private pump(): void {
    while (this.active < this.options.concurrency) {
      const index = this.queue.findIndex((id) => {
        const job = this.jobs.get(id)
        return job !== undefined && job.status === "queued" && this.canStart(job)
      })
      if (index === -1) return
      const [id] = this.queue.splice(index, 1)
      void this.start(id)
    }
  }

  private async start(id: string): Promise<void> {
    const job = this.jobs.get(id)
    if (!job) return

    const controller = new AbortController()
    this.controllers.set(id, controller)
    this.active++
    if (job.quality >= HIGH_QUALITY) this.activeHigh++

    const startedAt = Date.now()
    this.update(job, { status: "resolving", startedAt })

    try {
      const result = await runDownload(
        {
          jobId: id,
          uuid: job.uuid,
          kind: job.kind,
          title: job.title,
          role: job.role,
          category: job.category ?? undefined,
          courseTitle: job.courseTitle ?? undefined,
          number: job.number ?? null,
          durationSec: job.durationSec,
          quality: job.quality,
          remux: job.remux,
        },
        {
          contentDir: this.options.contentDir,
          scratchDir: path.join(this.options.contentDir, ".skillcapped", "tmp"),
          ffmpeg: this.options.ffmpeg,
          segmentConcurrency: this.options.segmentConcurrency,
        },
        controller.signal,
        (progress) => {
          const elapsed = (Date.now() - startedAt) / 1000
          const finishedSegments = progress.segmentsDone >= progress.segmentsTotal
          this.update(job, {
            status: finishedSegments ? "remuxing" : "downloading",
            segmentsDone: progress.segmentsDone,
            segmentsTotal: progress.segmentsTotal,
            bytes: progress.bytes,
            bytesTotal: progress.bytesTotal,
            speedBps: elapsed > 0 ? Math.round(progress.bytes / elapsed) : 0,
          })
        },
      )

      this.update(job, {
        status: "done",
        actualQuality: result.quality,
        relativePath: result.relativePath,
        sizeBytes: result.sizeBytes,
        remuxed: result.remuxed,
        note: result.note ?? (result.qualityFellBack ? `Streamed at ${qualityLabel(result.quality)} (requested rendition was unavailable).` : null),
        segmentsDone: result.segments,
        segmentsTotal: result.segments,
        bytes: result.sizeBytes,
        bytesTotal: Math.max(job.bytesTotal, result.sizeBytes),
        finishedAt: Date.now(),
      })
      this.events.emit("settled", this.jobs.get(id) as JobRecord)
    } catch (error) {
      const aborted = controller.signal.aborted
      this.update(job, {
        status: aborted ? "cancelled" : "failed",
        error: aborted ? null : (error as Error).message || "Download failed",
        finishedAt: Date.now(),
      })
      if (aborted) this.events.emit("settled", this.jobs.get(id) as JobRecord)
    } finally {
      this.controllers.delete(id)
      this.active--
      if (job.quality >= HIGH_QUALITY) this.activeHigh--
      this.persist()
      this.pump()
    }
  }

  private update(job: JobRecord, patch: Partial<JobRecord>): void {
    Object.assign(job, patch)
    this.emitChanged(job, false)
  }

  /**
   * Emit at most a few times a second per job — a segment finishes every few
   * hundred ms and a 4K run would otherwise flood the event stream.
   */
  private emitChanged(job: JobRecord, force: boolean): void {
    const now = Date.now()
    const last = this.lastEmit.get(job.id) ?? 0
    const terminal = ["done", "failed", "cancelled", "interrupted"].includes(job.status)
    if (force || terminal || now - last >= PROGRESS_INTERVAL_MS) {
      this.lastEmit.set(job.id, now)
      this.events.emit("changed", { ...job })
    }
  }

  private persist(): void {
    this.saver.schedule(this.list())
  }
}
