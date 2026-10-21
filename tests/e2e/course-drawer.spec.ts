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
  await expect(card).toContainText(course.title)
  return { course, lessons, card }
}

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

test.describe("course drawer", () => {
  test("clicking a course card opens its lessons without selecting it", async ({ page, request }) => {
    const { course, lessons, card } = await openCourse(page, request)

    await card.locator("h3 button").click()
    const drawer = page.getByRole("dialog")
    await expect(drawer).toBeVisible()
    await expect(drawer).toContainText(course.title)
    await expect(drawer.locator("ol > li")).toHaveCount(lessons.length)
    await expect(drawer.locator("ol > li").first()).toContainText(lessons[0].title)

    await expect(card).toHaveAttribute("data-open", "1")
    await expect(card).not.toHaveAttribute("data-selected", "1")
    await expect(page.getByText(/^[1-9]\d* selected/)).toHaveCount(0)

    await page.keyboard.press("Escape")
    await expect(drawer).toHaveCount(0)
    await expect(card).not.toHaveAttribute("data-open", "1")
  })

  test("marks the card and the lesson rows that are on disk", async ({ page, request }) => {
    const { lessons } = await firstCourseWithLessons(request)
    await page.route("**/api/library*", (route) => route.fulfill({ json: libraryPayload([lessons[0].id]) }))

    const { course, card } = await openCourse(page, request)
    await expect(card).toHaveAttribute("data-on-disk", "partial")
    await expect(card).toContainText(`1/${lessons.length}`)

    await card.locator("h3 button").click()
    const drawer = page.getByRole("dialog")
    await expect(drawer).toContainText(`1 of ${lessons.length} lessons on disk`)
    await expect(drawer.locator("ol > li").first()).toContainText("1080p")
    await expect(drawer.locator("ol > li").nth(1)).not.toContainText("1080p")

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

  test("selects the whole course from the drawer", async ({ page, request }) => {
    const { lessons, card } = await openCourse(page, request)
    await card.locator("h3 button").click()

    const drawer = page.getByRole("dialog")
    await expect(drawer).toContainText("0 selected")
    await drawer.getByRole("button", { name: "Select all" }).click()
    await expect(drawer).toContainText(`${lessons.length} selected`)
    await expect(drawer.getByRole("button", { name: /^Download \d+ selected$/ })).toBeVisible()

    await expect(card).not.toHaveAttribute("data-selected", "1")
    await drawer.getByRole("button", { name: "Clear" }).click()
    await expect(drawer).toContainText("0 selected")
  })

  test("shift-clicking a course title extends the selection instead of opening it", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    const cards = page.locator("article")
    await cards.nth(0).locator("button[aria-pressed]").click()
    await cards.nth(2).locator("h3 button").click({ modifiers: ["Shift"] })
    await expect(page.getByText(/3 selected/).first()).toBeVisible()
    await expect(page.getByRole("dialog")).toHaveCount(0)
  })
})
