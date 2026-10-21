import { expect, test } from "@playwright/test"

const NOW = Date.now()

type JobOverrides = {
  id: string
  title: string
  groupId?: string | null
  groupTitle?: string | null
  status?: string
  segmentsDone?: number
  segmentsTotal?: number
  bytes?: number
  bytesTotal?: number
  speedBps?: number
  startedAt?: number | null
  finishedAt?: number | null
  error?: string | null
}

const job = (over: JobOverrides) => ({
  id: over.id,
  uuid: `uuid-${over.id}`,
  kind: "video",
  title: over.title,
  role: "ADC",
  durationSec: 900,
  quality: 1080,
  qualityLabel: "1080p",
  actualQuality: null,
  remux: true,
  status: over.status ?? "queued",
  segmentsDone: over.segmentsDone ?? 0,
  segmentsTotal: over.segmentsTotal ?? 0,
  bytes: over.bytes ?? 0,
  bytesTotal: over.bytesTotal ?? 0,
  speedBps: over.speedBps ?? 0,
  relativePath: null,
  sizeBytes: null,
  remuxed: null,
  error: over.error ?? null,
  note: null,
  groupId: over.groupId ?? null,
  groupTitle: over.groupTitle ?? null,
  createdAt: NOW,
  startedAt: over.startedAt ?? null,
  finishedAt: over.finishedAt ?? null,
})

const finished = (id: string, title: string, groupId: string, groupTitle: string) =>
  job({
    id,
    title,
    groupId,
    groupTitle,
    status: "done",
    segmentsDone: 60,
    segmentsTotal: 60,
    bytes: 240 * 1024 * 1024,
    bytesTotal: 240 * 1024 * 1024,
    finishedAt: NOW - 60_000,
  })

const JOBS = [
  finished("w1", "Intro to wave states", "wave", "Wave Control for Supports"),
  finished("w2", "Freezing outside tower", "wave", "Wave Control for Supports"),
  job({
    id: "w3",
    title: "Holding a freeze under pressure",
    groupId: "wave",
    groupTitle: "Wave Control for Supports",
    status: "downloading",
    segmentsDone: 30,
    segmentsTotal: 60,
    bytes: 100 * 1024 * 1024,
    bytesTotal: 200 * 1024 * 1024,
    speedBps: 2 * 1024 * 1024,
    startedAt: NOW - 60_000,
  }),
  job({
    id: "s1",
    title: "Smurf review — Emerald Zyra",
    status: "downloading",
    segmentsDone: 10,
    segmentsTotal: 20,
    bytes: 40 * 1024 * 1024,
    bytesTotal: 90 * 1024 * 1024,
    speedBps: 1024 * 1024,
    startedAt: NOW - 30_000,
  }),
]

async function openDownloads(page: import("@playwright/test").Page, jobs = JOBS) {
  await page.route("**/api/jobs", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ jobs }) }),
  )
  await page.goto("/")
  await page.getByRole("button", { name: /^Downloads/ }).click()
  return page.getByRole("dialog")
}

test.describe("downloads queue", () => {
  test("reports the whole queue in one bar and one line per course", async ({ page }) => {
    const errors: string[] = []
    page.on("pageerror", (error) => errors.push(String(error)))

    const drawer = await openDownloads(page)

    await expect(drawer.getByText("Queue progress")).toBeVisible()
    await expect(drawer.getByText("2 of 4 downloads")).toBeVisible()
    await expect(drawer.getByText("75%").first()).toBeVisible()

    const course = drawer.getByRole("button", { name: /Wave Control for Supports/ })
    await expect(course).toBeVisible()
    await expect(course).toHaveAttribute("aria-expanded", "false")
    await expect(course).toContainText("3 lessons")
    await expect(course).toContainText("2/3 lessons")
    await expect(course).toContainText("Holding a freeze under pressure")

    expect(errors).toEqual([])
  })

  test("opens a course into its lessons and folds it back", async ({ page }) => {
    const drawer = await openDownloads(page)
    const lesson = drawer.getByText("Freezing outside tower")

    await expect(lesson).toHaveCount(0)

    const course = drawer.getByRole("button", { name: /Wave Control for Supports/ })
    await course.click()
    await expect(course).toHaveAttribute("aria-expanded", "true")
    await expect(lesson).toBeVisible()
    await expect(drawer.getByText("Intro to wave states")).toBeVisible()

    await course.click()
    await expect(course).toHaveAttribute("aria-expanded", "false")
    await expect(lesson).toHaveCount(0)
  })

  test("a download outside any course stays a line of its own", async ({ page }) => {
    const drawer = await openDownloads(page)

    await expect(drawer.getByText("Smurf review — Emerald Zyra")).toBeVisible()
    await expect(drawer.locator("button[aria-expanded]").filter({ hasText: "Smurf review" })).toHaveCount(0)
  })

  test("counts what needs attention and names the failed lesson", async ({ page }) => {
    const jobs = [
      finished("j1", "First clear", "jungle", "Jungle Pathing 201"),
      job({
        id: "j2",
        title: "Vertical jungling",
        groupId: "jungle",
        groupTitle: "Jungle Pathing 201",
        status: "failed",
        segmentsDone: 12,
        segmentsTotal: 48,
        error: "The CDN stopped answering after part 12.",
      }),
    ]
    const drawer = await openDownloads(page, jobs)

    await expect(drawer.getByText("Needs attention")).toBeVisible()
    await expect(drawer.getByText("1 need attention")).toBeVisible()

    const course = drawer.getByRole("button", { name: /Jungle Pathing 201/ })
    await expect(course).toContainText("1/2 lessons")
    await expect(course).toContainText("1 failed")

    await course.click()
    await expect(drawer.getByText("The CDN stopped answering after part 12.")).toBeVisible()
  })
})
