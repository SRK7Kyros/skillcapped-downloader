import { expect, test } from "@playwright/test"

/**
 * Opt-in end-to-end run against the real CDN: resolves segments, downloads,
 * remuxes, and checks the result in the UI. `LIVE=1 bun run test:live`.
 */

const live = process.env.LIVE === "1"

test.describe("live download", () => {
  test.skip(!live, "set LIVE=1 to run against the real CDN")
  test.setTimeout(360_000)

  test("downloads a lesson into its course folder and surfaces it everywhere", async ({ page, request }) => {
    const catalog = await (await request.get("/api/catalog")).json()
    const lesson = catalog.items
      .filter((item: { kind: string; courseTitle?: string; durationSec: number }) =>
        item.kind === "video" && Boolean(item.courseTitle) && item.durationSec > 0 && item.durationSec < 150,
      )
      .sort((a: { durationSec: number }, b: { durationSec: number }) => a.durationSec - b.durationSec)[0]
    expect(lesson, "expected at least one short course lesson").toBeTruthy()

    const created = await (
      await request.post("/api/jobs", {
        data: { ids: [lesson.id], quality: 1500, remux: true, skipExisting: false },
      })
    ).json()
    expect(created.created).toHaveLength(1)
    const jobId = created.created[0].id

    await expect
      .poll(
        async () => {
          const jobs = await (await request.get("/api/jobs")).json()
          return jobs.jobs.find((job: { id: string }) => job.id === jobId)?.status
        },
        { timeout: 300_000, intervals: [1000] },
      )
      .toBe("done")

    const job = (await (await request.get("/api/jobs")).json()).jobs.find((entry: { id: string }) => entry.id === jobId)
    expect(job.relativePath).toMatch(new RegExp(`^Courses/${lesson.role}/`))
    expect(job.remuxed).toBe(true)
    expect(job.sizeBytes).toBeGreaterThan(0)

    const library = await (await request.get("/api/library")).json()
    const entry = library.entries.find((row: { uuid: string }) => row.uuid === lesson.id)
    expect(entry).toBeTruthy()

    await page.goto("/")
    await page.getByRole("button", { name: /Downloads/i }).first().click()
    const drawer = page.locator("[role='dialog']")
    await expect(drawer).toContainText(/done/)
    await expect(drawer).toContainText(job.relativePath)

    await page.keyboard.press("Escape")
    await page.getByRole("tab", { name: "Library" }).click()
    await expect(page.locator("main li").first()).toBeVisible()
    await expect(page.locator("main")).toContainText(entry.title)
  })
})
