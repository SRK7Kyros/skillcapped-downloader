import { describe, expect, test } from "bun:test"
import type { JobRecord } from "../../web/src/api/types.ts"
import { groupQueue, itemPercent, queueProgress } from "../../web/src/lib/progress.ts"

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

describe("groupQueue", () => {
  test("folds a course's lessons into one line and leaves a lone download alone", () => {
    const jobs = [
      job({ id: "a", groupId: "course-1", groupTitle: "Wave Control", status: "done" }),
      job({ id: "b", groupId: "course-1", groupTitle: "Wave Control", status: "done" }),
      job({ id: "c", groupId: "course-2", groupTitle: "Jungle Paths", status: "downloading" }),
      job({ id: "d", title: "Laning Basics", status: "downloading" }),
    ]
    const groups = groupQueue(jobs)
    expect(groups.map((group) => [group.kind, group.title, group.total])).toEqual([
      ["course", "Jungle Paths", 1],
      ["single", "Laning Basics", 1],
      ["course", "Wave Control", 2],
    ])
  })

  test("a course reports one bar from finished and part-finished lessons", () => {
    const jobs = [
      job({ id: "a", groupId: "course-1", status: "done" }),
      job({ id: "b", groupId: "course-1", status: "done" }),
      job({ id: "c", groupId: "course-1", status: "downloading", segmentsDone: 5, segmentsTotal: 10 }),
      job({ id: "d", groupId: "course-1", status: "queued" }),
    ]
    const [group] = groupQueue(jobs)
    expect(group.done).toBe(2)
    expect(group.percent).toBe(62.5)
    expect(group.state).toBe("active")
  })

  test("a course stays in needs-attention once it stops and something failed", () => {
    const jobs = [
      job({ id: "a", groupId: "course-1", status: "done" }),
      job({ id: "b", groupId: "course-1", status: "failed", segmentsDone: 7, segmentsTotal: 10 }),
    ]
    const [group] = groupQueue(jobs)
    expect(group.state).toBe("attention")
    expect(group.failed).toBe(1)
    expect(group.lead.id).toBe("b")
  })

  test("a course of finished lessons is finished", () => {
    const [group] = groupQueue([
      job({ id: "a", groupId: "course-1", status: "done" }),
      job({ id: "b", groupId: "course-1", status: "done" }),
    ])
    expect(group.state).toBe("finished")
    expect(group.percent).toBe(100)
  })

  test("names the lesson actually downloading while collapsed", () => {
    const [group] = groupQueue([
      job({ id: "a", groupId: "course-1", status: "queued" }),
      job({ id: "b", groupId: "course-1", title: "Warding", status: "downloading" }),
    ])
    expect(group.lead.id).toBe("b")
  })

  test("lists work in progress, then what needs attention, then finished", () => {
    const jobs = [
      job({ id: "a", groupId: "done-course", status: "done" }),
      job({ id: "b", groupId: "done-course", status: "done" }),
      job({ id: "c", groupId: "failed-course", status: "failed" }),
      job({ id: "d", groupId: "failed-course", status: "done" }),
      job({ id: "e", groupId: "live-course", status: "downloading" }),
      job({ id: "f", groupId: "live-course", status: "queued" }),
    ]
    expect(groupQueue(jobs).map((group) => group.state)).toEqual(["active", "attention", "finished"])
  })

  test("keeps lessons of a course together even when they arrive interleaved", () => {
    const jobs = [
      job({ id: "a", groupId: "course-1", status: "done" }),
      job({ id: "b", status: "downloading" }),
      job({ id: "c", groupId: "course-1", status: "queued" }),
    ]
    const course = groupQueue(jobs).find((group) => group.key === "course:course-1")
    expect(course?.jobs.map((member) => member.id)).toEqual(["a", "c"])
  })
})

describe("queueProgress", () => {
  test("reports nothing for an empty queue", () => {
    expect(queueProgress([])).toEqual({
      total: 0,
      done: 0,
      active: 0,
      attention: 0,
      percent: 0,
      bytes: 0,
      speed: 0,
      eta: 0,
    })
  })

  test("averages every item's own percentage", () => {
    const progress = queueProgress([
      job({ id: "a", status: "done" }),
      job({ id: "b", status: "downloading", segmentsDone: 5, segmentsTotal: 10 }),
      job({ id: "c", status: "queued" }),
    ])
    expect(progress.total).toBe(3)
    expect(progress.done).toBe(1)
    expect(progress.active).toBe(2)
    expect(progress.percent).toBeCloseTo(50, 5)
  })

  test("counts failed items as needing attention, not progress", () => {
    const progress = queueProgress([
      job({ id: "a", status: "done" }),
      job({ id: "b", status: "failed", segmentsDone: 0, segmentsTotal: 10 }),
    ])
    expect(progress.attention).toBe(1)
    expect(progress.percent).toBe(50)
  })

  test("sums speed and the bytes still to fetch into one ETA", () => {
    const progress = queueProgress([
      job({ id: "a", status: "downloading", bytes: 250, bytesTotal: 1000, speedBps: 500 }),
      job({ id: "b", status: "downloading", bytes: 500, bytesTotal: 1000, speedBps: 500 }),
      job({ id: "c", status: "done", sizeBytes: 2048 }),
    ])
    expect(progress.speed).toBe(1000)
    expect(progress.eta).toBeCloseTo(1.25, 5)
    expect(progress.bytes).toBe(2048)
  })

  test("has no ETA while nothing reports a transfer rate", () => {
    expect(queueProgress([job({ status: "queued" })]).eta).toBe(0)
  })
})
