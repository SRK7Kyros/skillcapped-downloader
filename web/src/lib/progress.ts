import type { JobRecord, JobStatus } from "../api/types"

const ACTIVE: JobStatus[] = ["queued", "resolving", "downloading", "remuxing"]
const ATTENTION: JobStatus[] = ["failed", "interrupted", "cancelled"]

export type QueueGroupState = "active" | "attention" | "finished"

/** One course's lessons, or a lone download, as the queue panel lists it. */
export type QueueGroup = {
  key: string
  title: string
  /** `course` groups expand into their lessons; `single` ones are a lesson on its own. */
  kind: "course" | "single"
  state: QueueGroupState
  jobs: JobRecord[]
  total: number
  done: number
  failed: number
  percent: number
  /** The member worth naming while the group is collapsed: downloading, else failed. */
  lead: JobRecord
}

export type QueueProgress = {
  total: number
  done: number
  active: number
  attention: number
  percent: number
  bytes: number
  speed: number
  eta: number
}

/** How far along one lesson is, 0–100. */
export function itemPercent(job: JobRecord): number {
  if (job.status === "done") return 100
  if (job.segmentsTotal > 0) return Math.min(100, (job.segmentsDone / job.segmentsTotal) * 100)
  return 0
}

/**
 * The whole queue as one bar. Every item counts by its own percentage, so
 * finished lessons are whole, running ones are partial and failed or cancelled
 * ones count only what they actually fetched — the bar stops short when the
 * queue did not finish, which is the honest reading.
 */
export function queueProgress(jobs: JobRecord[]): QueueProgress {
  if (!jobs.length) {
    return { total: 0, done: 0, active: 0, attention: 0, percent: 0, bytes: 0, speed: 0, eta: 0 }
  }

  let weight = 0
  let done = 0
  let active = 0
  let attention = 0
  let bytes = 0
  let speed = 0
  let remaining = 0

  for (const job of jobs) {
    weight += itemPercent(job)
    if (job.status === "done") done += 1
    if (ACTIVE.includes(job.status)) active += 1
    if (ATTENTION.includes(job.status)) attention += 1
    bytes += job.sizeBytes ?? 0
    if (job.status === "downloading") {
      speed += job.speedBps
      if (job.bytesTotal > job.bytes) remaining += job.bytesTotal - job.bytes
    }
  }

  return {
    total: jobs.length,
    done,
    active,
    attention,
    percent: weight / jobs.length,
    bytes,
    speed,
    eta: speed > 0 && remaining > 0 ? remaining / speed : 0,
  }
}

function groupState(jobs: JobRecord[]): QueueGroupState {
  if (jobs.some((job) => ACTIVE.includes(job.status))) return "active"
  if (jobs.some((job) => ATTENTION.includes(job.status))) return "attention"
  return "finished"
}

function leadJob(jobs: JobRecord[]): JobRecord {
  return (
    jobs.find((job) => job.status === "downloading" || job.status === "remuxing" || job.status === "resolving") ??
    jobs.find((job) => ATTENTION.includes(job.status)) ??
    jobs[jobs.length - 1]
  )
}

const STATE_ORDER: Record<QueueGroupState, number> = { active: 0, attention: 1, finished: 2 }

/**
 * Splits the queue into courses — a bulk run of twenty lessons reads as one
 * line with its own bar — while a download that belongs to no course stays a
 * single line of its own.
 */
export function groupQueue(jobs: JobRecord[]): QueueGroup[] {
  const buckets = new Map<string, JobRecord[]>()
  for (const job of jobs) {
    const key = job.groupId ? `course:${job.groupId}` : `single:${job.id}`
    const bucket = buckets.get(key)
    if (bucket) bucket.push(job)
    else buckets.set(key, [job])
  }

  const groups: QueueGroup[] = []
  for (const [key, members] of buckets) {
    const first = members[0]
    const course = Boolean(first.groupId)
    let weight = 0
    let done = 0
    let failed = 0
    for (const job of members) {
      weight += itemPercent(job)
      if (job.status === "done") done += 1
      if (ATTENTION.includes(job.status)) failed += 1
    }
    groups.push({
      key,
      title: course ? (first.groupTitle?.trim() || first.title) : first.title,
      kind: course ? "course" : "single",
      state: groupState(members),
      jobs: [...members].sort((a, b) => a.createdAt - b.createdAt),
      total: members.length,
      done,
      failed,
      percent: weight / members.length,
      lead: leadJob(members),
    })
  }

  return groups.sort(
    (a, b) =>
      STATE_ORDER[a.state] - STATE_ORDER[b.state] ||
      a.jobs[0].createdAt - b.jobs[0].createdAt ||
      a.title.localeCompare(b.title),
  )
}
