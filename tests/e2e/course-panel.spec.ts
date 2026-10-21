import { expect, test, type APIRequestContext, type Locator, type Page } from "@playwright/test"

type Item = {
  id: string
  kind: string
  title: string
  lessonIds?: string[]
}

type Catalog = { items: Item[] }

async function courseWithLessons(
  request: APIRequestContext,
  min: number,
  max = Number.POSITIVE_INFINITY,
): Promise<{ course: Item; lessons: Item[] }> {
  const catalog = (await (await request.get("/api/catalog")).json()) as Catalog
  const byId = new Map(catalog.items.map((item) => [item.id, item]))
  const course = catalog.items.find(
    (item) => item.kind === "course" && (item.lessonIds?.length ?? 0) >= min && (item.lessonIds?.length ?? 0) <= max,
  )
  if (!course) throw new Error("the catalogue has no course with that many lessons")
  const lessons = (course.lessonIds ?? []).map((id) => byId.get(id)).filter((item): item is Item => Boolean(item))
  return { course, lessons }
}

const firstCourseWithLessons = (request: APIRequestContext) => courseWithLessons(request, 2)

async function openCourse(page: Page, request: APIRequestContext, min = 2, max = Number.POSITIVE_INFINITY) {
  const { course, lessons } = await courseWithLessons(request, min, max)
  await page.goto("/")
  await expect(page.locator("article").first()).toBeVisible()
  await page.getByPlaceholder(/Search/).fill(course.title)
  const card = page.locator("article").filter({ hasText: course.title }).first()
  await expect(card).toBeVisible()
  return { course, lessons, card }
}

const panelOf = (page: Page) => page.locator("[data-course-panel]")

const detailsOf = (card: Locator) => card.locator("[data-course-details]")

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
    await expect(panel).toHaveAttribute("aria-label", `${course.title} lessons`)
    await expect(panel.locator("ol > li")).toHaveCount(lessons.length)
    await expect(panel.locator("ol > li").first()).toContainText(lessons[0].title)

    const details = detailsOf(card)
    await expect(details).toBeVisible()
    await expect(details).toContainText(/on disk/)
    await expect(panel.locator("[data-course-details]")).toHaveCount(0)

    await expect(card).toHaveAttribute("data-open", "1")
    await expect(card).not.toHaveAttribute("data-selected", "1")
    await expect(page.getByText(/^[1-9]\d* selected/)).toHaveCount(0)

    await page.keyboard.press("Escape")
    await expect(panel).toHaveCount(0)
    await expect(card).not.toHaveAttribute("data-open", "1")
    await expect(card.locator("[data-course-details]")).toHaveCount(0)
  })

  test("opens beside the card and takes the room its lessons need", async ({ page, request }) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    const { card: opened, lessons } = await openCourse(page, request, 8)
    const cards = page.locator("article")
    const before = await opened.boundingBox()
    expect(before).not.toBeNull()

    await opened.locator("h3 button").click()
    const panel = panelOf(page)
    await expect(panel).toBeVisible()

    const cardBox = async () => opened.boundingBox()

    const edgeOffset = async () => {
      const box = await panel.boundingBox()
      const card = await cardBox()
      if (!box || !card) return 999
      return Math.round(Math.max(Math.abs(box.x - (card.x + card.width)), Math.abs(box.y - card.y)))
    }
    await expect.poll(edgeOffset).toBeLessThanOrEqual(1)

    const panelVsCard = async () => {
      const box = await panel.boundingBox()
      const card = await cardBox()
      if (!box || !card) return 999
      return Math.abs(Math.round(box.height) - Math.round(card.height))
    }
    await expect.poll(panelVsCard).toBeLessThanOrEqual(1)

    const gridRight = async () =>
      Math.round(await page.locator("article").first().evaluate((el) => el.parentElement?.getBoundingClientRect().right ?? 0))
    const slackAtRight = async () => {
      const box = await panel.boundingBox()
      if (!box) return 999
      return Math.round((await gridRight()) - (box.x + box.width))
    }
    expect(lessons.length).toBeGreaterThanOrEqual(8)
    await expect.poll(slackAtRight).toBeLessThanOrEqual(1)

    const rowOf = async (index: number) => Math.round((await cards.nth(index).boundingBox())?.y ?? 0)
    const belowOpen = async () => {
      const card = await cardBox()
      return card ? Math.round(card.y + card.height + 10) : 0
    }
    await expect.poll(async () => (await rowOf(1)) - (await belowOpen())).toBe(0)
    await expect.poll(async () => (await rowOf(2)) - (await belowOpen())).toBe(0)

    await page.getByRole("button", { name: "Close lessons" }).click()
    await expect(panel).toHaveCount(0)
    await expect.poll(() => rowOf(1)).toBe(Math.round(before?.y ?? 0))
  })

  test("a course with few lessons keeps the panel narrow instead of filling the row", async ({ page, request }) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    const { card: opened } = await openCourse(page, request, 2, 2)
    await opened.locator("h3 button").click()
    const panel = panelOf(page)
    await expect(panel).toBeVisible()

    const gridRight = async () =>
      Math.round(await page.locator("article").first().evaluate((el) => el.parentElement?.getBoundingClientRect().right ?? 0))
    const slackAtRight = async () => {
      const box = await panel.boundingBox()
      if (!box) return 0
      return Math.round((await gridRight()) - (box.x + box.width))
    }
    await expect.poll(slackAtRight).toBeGreaterThan(100)
    await expect(panel.locator("ol > li")).toHaveCount(2)
  })

  test("marks the card and the lesson rows that are on disk", async ({ page, request }) => {
    const { lessons } = await firstCourseWithLessons(request)
    await page.route("**/api/library*", (route) => route.fulfill({ json: libraryPayload([lessons[0].id]) }))

    const { course, card } = await openCourse(page, request)
    await expect(card).toHaveAttribute("data-on-disk", "partial")
    await expect(card).toContainText(`1/${lessons.length}`)

    await card.locator("h3 button").click()
    const panel = panelOf(page)
    await expect(detailsOf(card)).toContainText(`1 of ${lessons.length} on disk`)
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

  test("keeps the course metadata in the banner card and never crops a poster", async ({
    page,
    request,
  }) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    const { card } = await openCourse(page, request)
    await card.locator("h3 button").click()

    const panel = panelOf(page)
    const details = detailsOf(card)
    await expect(details).toBeVisible()
    await expect(details).toContainText(/on disk/)
    await expect(panel.locator("[data-course-details]")).toHaveCount(0)

    const posters = panel.locator("ol > li [data-poster]")
    const count = await posters.count()
    expect(count).toBeGreaterThan(0)
    for (let index = 0; index < count; index += 1) {
      const box = await posters.nth(index).boundingBox()
      expect(box).not.toBeNull()
      expect((box?.width ?? 0) / (box?.height ?? 1)).toBeGreaterThanOrEqual(16 / 9 - 0.03)
    }

    const scroller = panel.locator("ol").locator("..")
    await expect(scroller).toHaveCSS("overflow-x", "auto")
    const heightGap = async () =>
      Math.abs(
        Math.round((await panel.boundingBox())?.height ?? 0) - Math.round((await card.boundingBox())?.height ?? 0),
      )
    await expect.poll(heightGap).toBeLessThanOrEqual(1)
  })

  test("clicking a lesson card selects it instead of previewing it", async ({ page, request }) => {
    const { card } = await openCourse(page, request)
    await card.locator("h3 button").click()

    const panel = panelOf(page)
    const details = detailsOf(card)
    const first = panel.locator("ol > li").first()
    await expect(first).toBeVisible()

    // A plain click in the middle of the card is the selection gesture; the
    // preview button used to sit dead centre and swallow it.
    await first.click()
    await expect(first).toHaveAttribute("data-selected", "1")
    await expect(details).toContainText("1 selected")
    await expect(page.getByRole("dialog")).toHaveCount(0)

    await first.click()
    await expect(first).not.toHaveAttribute("data-selected", "1")
    await expect(details).toContainText("0 selected")
  })

  test("selects the whole course from the banner card", async ({ page, request }) => {
    const { lessons, card } = await openCourse(page, request)
    await card.locator("h3 button").click()

    const details = detailsOf(card)
    await expect(details).toContainText("0 selected")
    await details.getByRole("button", { name: "Select all" }).click()
    await expect(details).toContainText(`${lessons.length} selected`)
    await expect(details.getByRole("button", { name: /^Download \d+ selected$/ })).toBeVisible()

    await expect(card).not.toHaveAttribute("data-selected", "1")
    await details.getByRole("button", { name: "Clear" }).click()
    await expect(details).toContainText("0 selected")
  })

  test("ctrl-clicking a lesson selects only that lesson", async ({ page, request }) => {
    const { lessons, card } = await openCourse(page, request)
    await card.locator("h3 button").click()

    const panel = panelOf(page)
    const details = detailsOf(card)
    const rows = panel.locator("ol > li")
    await expect(rows.first()).toBeVisible()

    await rows.nth(0).locator("button[aria-pressed]").click({ modifiers: ["Control"] })
    await expect(rows.nth(0).locator("button[aria-pressed]")).toHaveAttribute("aria-pressed", "true")
    await expect(details).toContainText("1 selected")

    await rows.nth(lessons.length - 1).locator("button[aria-pressed]").click({ modifiers: ["Control"] })
    await expect(details).toContainText("2 selected")
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
