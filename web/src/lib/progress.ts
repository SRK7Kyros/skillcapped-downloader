import type { JobRecord, JobStatus } from "../api/types"

const ACTIVE: JobStatus[] = ["queued", "resolving", "downloading", "remuxing"]

export type CourseProgress = {
  total: number
  done: number
  percent: number
}

/** How far along one lesson is, 0–100. */
export function itemPercent(job: JobRecord): number {
  if (job.status === "done") return 100
  if (job.segmentsTotal > 0) return Math.min(100, (job.segmentsDone / job.segmentsTotal) * 100)
  return 0
}

/**
 * Progress across every lesson queued for one course (`groupId`), so a bulk run
 * of twenty lessons reads as one job. In-flight lessons count by their own
 * percentage, finished ones count whole, and failed or cancelled ones count
 * nothing. `null` for a lone download — there is no course to report on.
 */
export function courseProgress(jobs: JobRecord[], groupId: string | null): CourseProgress | null {
  if (!groupId) return null
  const members = jobs.filter((job) => job.groupId === groupId)
  if (members.length < 2) return null

  let done = 0
  let finished = 0
  for (const job of members) {
    if (job.status === "done") {
      done += 1
      finished += 1
    } else if (ACTIVE.includes(job.status)) {
      finished += itemPercent(job) / 100
    }
  }

  return { total: members.length, done, percent: (finished / members.length) * 100 }
}

/** One lookup per course for a whole job list. */
export function courseProgressByGroup(jobs: JobRecord[]): Map<string, CourseProgress> {
  const byGroup = new Map<string, CourseProgress>()
  for (const job of jobs) {
    if (!job.groupId || byGroup.has(job.groupId)) continue
    const progress = courseProgress(jobs, job.groupId)
    if (progress) byGroup.set(job.groupId, progress)
  }
  return byGroup
}
