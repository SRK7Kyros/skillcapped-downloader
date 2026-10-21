import { describe, expect, test } from "bun:test"
import type { JobRecord } from "../../web/src/api/types.ts"
import { courseProgress, courseProgressByGroup, itemPercent } from "../../web/src/lib/progress.ts"

const job = (over: Partial<JobRecord>): JobRecord => ({
  id: over.id ?? "job",
  uuid: "uuid",
  kind: "video",
  title: "Lesson",
  role: "ADC",
  durationSec: 60,
  quality: 1080,
  qualityLabel: "1080p",
  actualQuality: null,
  remux: true,
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
  groupId: null,
  groupTitle: null,
  createdAt: 0,
  startedAt: null,
  finishedAt: null,
  ...over,
})

describe("itemPercent", () => {
  test("counts a finished lesson whole", () => {
    expect(itemPercent(job({ status: "done", segmentsDone: 3, segmentsTotal: 9 }))).toBe(100)
  })

  test("follows the segment count while downloading", () => {
    expect(itemPercent(job({ status: "downloading", segmentsDone: 25, segmentsTotal: 50 }))).toBe(50)
  })

  test("reports nothing before the part count is known", () => {
    expect(itemPercent(job({ status: "resolving" }))).toBe(0)
  })
})

describe("courseProgress", () => {
  test("has nothing to report for a lesson queued on its own", () => {
    expect(courseProgress([job({ status: "downloading" })], null)).toBeNull()
    expect(courseProgress([job({ groupId: "course-1", status: "downloading" })], "course-1")).toBeNull()
  })

  test("counts finished lessons whole and in-flight ones by their own parts", () => {
    const jobs = [
      job({ id: "a", groupId: "course-1", status: "done" }),
      job({ id: "b", groupId: "course-1", status: "done" }),
      job({ id: "c", groupId: "course-1", status: "downloading", segmentsDone: 5, segmentsTotal: 10 }),
      job({ id: "d", groupId: "course-1", status: "queued" }),
    ]
    const progress = courseProgress(jobs, "course-1")
    expect(progress).toEqual({ total: 4, done: 2, percent: 62.5 })
  })

  test("a failed lesson does not stall the course at its partial parts", () => {
    const jobs = [
      job({ id: "a", groupId: "course-1", status: "done" }),
      job({ id: "b", groupId: "course-1", status: "failed", segmentsDone: 7, segmentsTotal: 10 }),
    ]
    expect(courseProgress(jobs, "course-1")?.percent).toBe(50)
  })

  test("ignores lessons that belong to another course", () => {
    const jobs = [
      job({ id: "a", groupId: "course-1", status: "done" }),
      job({ id: "b", groupId: "course-1", status: "done" }),
      job({ id: "c", groupId: "course-2", status: "downloading", segmentsDone: 5, segmentsTotal: 10 }),
    ]
    expect(courseProgress(jobs, "course-1")).toEqual({ total: 2, done: 2, percent: 100 })
  })
})

describe("courseProgressByGroup", () => {
  test("keys every course with more than one lesson and skips lone downloads", () => {
    const jobs = [
      job({ id: "a", groupId: "course-1", status: "done" }),
      job({ id: "b", groupId: "course-1", status: "done" }),
      job({ id: "c", groupId: "course-2", status: "downloading" }),
      job({ id: "d", status: "downloading" }),
    ]
    const groups = courseProgressByGroup(jobs)
    expect([...groups.keys()]).toEqual(["course-1"])
    expect(groups.get("course-1")?.percent).toBe(100)
  })
})
