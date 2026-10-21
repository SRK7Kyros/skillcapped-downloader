import { expect, test, type APIRequestContext, type Page } from "@playwright/test"

type Item = {
  id: string
  kind: string
  title: string
  lessonIds?: string[]
}

type Catalog = { items: Item[] }

async function firstCourseWithLessons(request: APIRequestContext): Promise<{ course: Item; lessons: Item[] }> {
  const catalog = (await (await request.get("/api/catalog")).json()) as Catalog
  const byId = new Map(catalog.items.map((item) => [item.id, item]))
  const course = catalog.items.find((item) => item.kind === "course" && (item.lessonIds?.length ?? 0) >= 2)
  if (!course) throw new Error("the catalogue has no course with lessons")
  const lessons = (course.lessonIds ?? []).map((id) => byId.get(id)).filter((item): item is Item => Boolean(item))
  return { course, lessons }
}

async function openCourse(page: Page, request: APIRequestContext) {
  const { course, lessons } = await firstCourseWithLessons(request)
  await page.goto("/")
  await expect(page.locator("article").first()).toBeVisible()
  await page.getByPlaceholder(/Search/).fill(course.title)
  const card = page.locator("article").filter({ hasText: course.title }).first()
  await expect(card).toBeVisible()
  return { course, lessons, card }
}

const panelOf = (page: Page) => page.locator("[data-course-panel]")

const libraryPayload = (uuids: string[]) => ({
  count: uuids.length,
  totalBytes: uuids.length * 1024,
  contentDir: "/tmp",
  entries: uuids.map((uuid) => ({
    uuid,
    title: "Lesson",
    qualityLabel: "1080p",
    quality: 2500,
    extension: "mp4",
    relativePath: `Courses/adc/${uuid}.mp4`,
    folder: "Courses/adc",
    sizeBytes: 1024,
    modifiedAt: Date.now(),
  })),
})

test.describe("course panel", () => {
  test("clicking a course card opens its lessons without selecting it", async ({ page, request }) => {
    const { course, lessons, card } = await openCourse(page, request)

    await card.locator("h3 button").click()
    const panel = panelOf(page)
    await expect(panel).toBeVisible()
    await expect(panel).toContainText(course.title)
    await expect(panel.locator("ol > li")).toHaveCount(lessons.length)
    await expect(panel.locator("ol > li").first()).toContainText(lessons[0].title)

    await expect(card).toHaveAttribute("data-open", "1")
    await expect(card).not.toHaveAttribute("data-selected", "1")
    await expect(page.getByText(/^[1-9]\d* selected/)).toHaveCount(0)

    await page.keyboard.press("Escape")
    await expect(panel).toHaveCount(0)
    await expect(card).not.toHaveAttribute("data-open", "1")
  })

  test("opens beside the card, sliding the rest right and wrapping only the ones that no longer fit", async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    await page.goto("/")
    const cards = page.locator("article")
    await expect(cards.first()).toBeVisible()

    const before = await cards.nth(0).boundingBox()
    const beforeNeighbour = await cards.nth(1).boundingBox()
    expect(before).not.toBeNull()
    expect(beforeNeighbour).not.toBeNull()

    await cards.nth(0).locator("h3 button").click()
    const panel = panelOf(page)
    await expect(panel).toBeVisible()

    const card = await cards.nth(0).boundingBox()
    expect(card).not.toBeNull()

    const edgeOffset = async () => {
      const box = await panel.boundingBox()
      if (!box || !card) return 999
      return Math.round(Math.max(Math.abs(box.x - (card.x + card.width)), Math.abs(box.y - card.y)))
    }
    await expect.poll(edgeOffset).toBeLessThanOrEqual(1)

    const rowOf = async (index: number) => Math.round((await cards.nth(index).boundingBox())?.y ?? 0)
    const closedRow = Math.round(before?.y ?? 0)
    await expect.poll(() => rowOf(1)).toBe(closedRow)
    await expect
      .poll(async () => Math.round((await cards.nth(1).boundingBox())?.x ?? 0))
      .toBeGreaterThan(Math.round((beforeNeighbour?.x ?? 0) + 10))

    const panelVsCard = async () => {
      const box = await panel.boundingBox()
      if (!box || !card) return 999
      return Math.abs(Math.round(box.height) - Math.round(card.height))
    }
    await expect.poll(panelVsCard).toBeLessThanOrEqual(1)
    await expect.poll(() => rowOf(2)).toBe(Math.round((card?.y ?? 0) + (card?.height ?? 0) + 10))

    await page.getByRole("button", { name: "Close lessons" }).click()
    await expect(panel).toHaveCount(0)
  })

  test("marks the card and the lesson rows that are on disk", async ({ page, request }) => {
    const { lessons } = await firstCourseWithLessons(request)
    await page.route("**/api/library*", (route) => route.fulfill({ json: libraryPayload([lessons[0].id]) }))

    const { course, card } = await openCourse(page, request)
    await expect(card).toHaveAttribute("data-on-disk", "partial")
    await expect(card).toContainText(`1/${lessons.length}`)

    await card.locator("h3 button").click()
    const panel = panelOf(page)
    await expect(panel).toContainText(`1 of ${lessons.length} on disk`)
    await expect(panel.locator("ol > li").first()).toContainText("1080p")
    await expect(panel.locator("ol > li").nth(1)).not.toContainText("1080p")

    await page.keyboard.press("Escape")
    await page.unroute("**/api/library*")
    await page.route("**/api/library*", (route) =>
      route.fulfill({ json: libraryPayload((course.lessonIds ?? []).slice(0, lessons.length)) }),
    )
    await page.reload()
    await page.getByPlaceholder(/Search/).fill(course.title)
    const complete = page.locator("article").filter({ hasText: course.title }).first()
    await expect(complete).toHaveAttribute("data-on-disk", "1")
    await expect(complete).toContainText(/complete/i)
  })

  test("shows every lesson as a card with its poster, duration and preview", async ({ page, request }) => {
    const { lessons, card } = await openCourse(page, request)
    await card.locator("h3 button").click()

    const rows = panelOf(page).locator("ol > li")
    await expect(rows).toHaveCount(lessons.length)
    const first = rows.first()
    await expect(first.locator("[data-poster]")).toHaveAttribute("data-poster", /^(image|fallback)$/)
    await expect(first).toContainText(/\d+:\d{2}/)
    await expect(first.getByRole("button", { name: /^Preview / })).toHaveCount(1)
    await expect(first.locator("button[aria-pressed]")).toHaveCount(1)
  })

  test("clicking a lesson card selects it instead of previewing it", async ({ page, request }) => {
    const { card } = await openCourse(page, request)
    await card.locator("h3 button").click()

    const panel = panelOf(page)
    const first = panel.locator("ol > li").first()
    await expect(first).toBeVisible()

    // A plain click in the middle of the card is the selection gesture; the
    // preview button used to sit dead centre and swallow it.
    await first.click()
    await expect(first).toHaveAttribute("data-selected", "1")
    await expect(panel).toContainText("1 selected")
    await expect(page.getByRole("dialog")).toHaveCount(0)

    await first.click()
    await expect(first).not.toHaveAttribute("data-selected", "1")
    await expect(panel).toContainText("0 selected")
  })

  test("selects the whole course from the panel", async ({ page, request }) => {
    const { lessons, card } = await openCourse(page, request)
    await card.locator("h3 button").click()

    const panel = panelOf(page)
    await expect(panel).toContainText("0 selected")
    await panel.getByRole("button", { name: "Select all" }).click()
    await expect(panel).toContainText(`${lessons.length} selected`)
    await expect(panel.getByRole("button", { name: /^Download \d+ selected$/ })).toBeVisible()

    await expect(card).not.toHaveAttribute("data-selected", "1")
    await panel.getByRole("button", { name: "Clear" }).click()
    await expect(panel).toContainText("0 selected")
  })

  test("ctrl-clicking a lesson selects only that lesson", async ({ page, request }) => {
    const { lessons, card } = await openCourse(page, request)
    await card.locator("h3 button").click()

    const panel = panelOf(page)
    const rows = panel.locator("ol > li")
    await expect(rows.first()).toBeVisible()

    await rows.nth(0).locator("button[aria-pressed]").click({ modifiers: ["Control"] })
    await expect(rows.nth(0).locator("button[aria-pressed]")).toHaveAttribute("aria-pressed", "true")
    await expect(panel).toContainText("1 selected")

    await rows.nth(lessons.length - 1).locator("button[aria-pressed]").click({ modifiers: ["Control"] })
    await expect(panel).toContainText("2 selected")
    await expect(panel.locator("ol > li button[aria-pressed='true']")).toHaveCount(2)
  })

  test("shift-clicking a course title extends the selection instead of opening it", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    const cards = page.locator("article")
    await cards.nth(0).locator("button[aria-pressed]").click()
    await cards.nth(2).locator("h3 button").click({ modifiers: ["Shift"] })
    await expect(page.getByText(/3 selected/).first()).toBeVisible()
    await expect(panelOf(page)).toHaveCount(0)
  })

  test("ctrl-clicking a course title selects one instead of opening it", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    const cards = page.locator("article")
    await cards.nth(0).locator("button[aria-pressed]").click()
    await cards.nth(3).locator("h3 button").click({ modifiers: ["Control"] })

    await expect(page.getByText(/2 selected/).first()).toBeVisible()
    await expect(cards.nth(3)).toHaveAttribute("data-selected", "1")
    await expect(panelOf(page)).toHaveCount(0)

    await cards.nth(3).locator("h3 button").click({ modifiers: ["Control"] })
    await expect(page.getByText(/^1 selected/).first()).toBeVisible()
    await expect(panelOf(page)).toHaveCount(0)
  })
})
